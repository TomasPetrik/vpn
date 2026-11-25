package admin

import (
	"context"
	"math"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/TomasPetrik/vpn/backend/internal/usage"
)

// 5 GiB reference used for cap planning bars.
const usageCapBytes = 5 * 1024 * 1024 * 1024

// An hour counts toward speed only when the device actually downloaded.
// Keepalive / idle samples stay out so they cannot pull the average down.
const activeHourMinRX = 1 << 20 // 1 MiB

// peer stats are sampled about every 15s (same interval as usage.LoadSpeed).
const sampleIntervalSec = 15.0

type usageWindowStats struct {
	RX, TX      uint64
	RXHuman     string
	TXHuman     string
	RXPctOfCap  float64
	BarWidthPct float64
	NearCap     bool
	OverCap     bool
}

type usageBar struct {
	Key, Label          string
	AvgLabel, BestLabel string
	usageWindowStats
}

type usageRangeOpt struct {
	Key, Label, Href string
	On               bool
}

const usageRangesCookie = "vpn_admin_usage_ranges"

var usageRangeCatalog = []struct{ Key, Label string }{
	{"24h", "24h"},
	{"3d", "3d"},
	{"7d", "7d"},
	{"1m", "1m"},
	{"life", "Lifetime"},
}

type deviceUsageRow struct {
	ID, Name, Platform, Country string
	LastSeen                    string
	W24h, W3d, W7d, W30d, WAll  usageWindowStats
	Bars                        []usageBar
	// Avg of each active hour's peak download (MB/s). Idle hours excluded.
	AvgDownMBps   float64
	AvgDownLabel  string
	BestDownMBps  float64
	BestDownLabel string
	AvgUpLabel    string
	ActiveHours   int
	Link          string
	Tone          string // "", "near", "over"
}

type usageAnalyticsView struct {
	Range            string
	RangeLabel       string
	ShownLabel       string
	Ranges           []usageRangeOpt
	Devices          []deviceUsageRow
	CapHuman         string
	DeviceCount      int
	ActiveDevices    int
	NearCap          int
	OverCap          int
	TotalRXHuman     string
	TotalTXHuman     string
	AvgPeakLabel     string
	BestPeakLabel    string
}

func (h *Handler) AnalyticsUsage(w http.ResponseWriter, r *http.Request) {
	selected := parseUsageRanges(r)
	persistUsageRanges(w, selected)
	view, err := h.loadUsageAnalytics(r.Context(), selected)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	_ = h.Tmpl.ExecuteTemplate(w, "analytics.html", map[string]any{
		"View": view,
		"CSRF": csrfFrom(r),
	})
}

func (h *Handler) loadUsageAnalytics(ctx context.Context, selected map[string]bool) (usageAnalyticsView, error) {
	rangeKey := widestUsageRange(selected)
	now := time.Now().UTC()
	until := now
	since24h := now.Add(-24 * time.Hour)
	since3d := now.Add(-3 * 24 * time.Hour)
	since7d := now.Add(-7 * 24 * time.Hour)
	since30d := now.Add(-30 * 24 * time.Hour)

	rows, err := h.DB.QueryContext(ctx, `
		SELECT
			d.id,
			d.platform,
			COALESCE(d.model, ''),
			COALESCE(NULLIF(TRIM(d.last_client_country), ''), '?'),
			COALESCE(DATE_FORMAT(d.last_seen_at, '%Y-%m-%d %H:%i:%s'), ''),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.rx_delta ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.tx_delta ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.rx_delta ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.tx_delta ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.rx_delta ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.tx_delta ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.rx_delta ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.sampled_at >= ? THEN s.tx_delta ELSE 0 END), 0),
			COALESCE(SUM(s.rx_delta), 0),
			COALESCE(SUM(s.tx_delta), 0)
		FROM devices d
		LEFT JOIN wireguard_peers p ON p.device_id = d.id
		LEFT JOIN peer_stats_samples s
			ON s.peer_id = p.id
			AND s.sampled_at < ?
		GROUP BY d.id, d.platform, d.model, d.last_client_country, d.last_seen_at`,
		since24h, since24h,
		since3d, since3d,
		since7d, since7d,
		since30d, since30d,
		until,
	)
	if err != nil {
		return usageAnalyticsView{}, err
	}
	defer rows.Close()

	speeds, err := h.loadPeriodPeakSpeeds(ctx, until, since24h, since3d, since7d, since30d)
	if err != nil {
		return usageAnalyticsView{}, err
	}

	out := usageAnalyticsView{
		Range:      rangeKey,
		RangeLabel: usageRangeLabel(rangeKey),
		ShownLabel: usageShownLabel(selected),
		Ranges:     usageRangeOptions(selected),
		CapHuman:   humanBytes(usageCapBytes),
	}
	var totalRX, totalTX uint64
	var peakSum float64
	var peakDevices int
	var bestPeak float64

	for rows.Next() {
		var (
			id, platform, model, country, lastSeenRaw string
			rx24, tx24, rx3, tx3, rx7, tx7            uint64
			rx30, tx30, rxAll, txAll                  uint64
		)
		if err := rows.Scan(
			&id, &platform, &model, &country, &lastSeenRaw,
			&rx24, &tx24, &rx3, &tx3, &rx7, &tx7, &rx30, &tx30, &rxAll, &txAll,
		); err != nil {
			return usageAnalyticsView{}, err
		}
		name := strings.TrimSpace(model)
		if name == "" {
			name = platform
		}
		if name == "" {
			name = "device"
		}
		lastSeen := "—"
		if lastSeenRaw != "" {
			if t, err := time.ParseInLocation("2006-01-02 15:04:05", lastSeenRaw, time.UTC); err == nil {
				lastSeen = compactTime(t)
			} else {
				lastSeen = lastSeenRaw
			}
		}
		w24 := makeWindowStats(rx24, tx24)
		w3 := makeWindowStats(rx3, tx3)
		w7 := makeWindowStats(rx7, tx7)
		w30 := makeWindowStats(rx30, tx30)
		wall := makeWindowStats(rxAll, txAll)
		headerWindow := selectedWindow(rangeKey, w24, w3, w7, w30, wall)
		byPeriod := speeds[id]
		visible := visibleUsageBars(selected, byPeriod, w24, w3, w7, w30, wall)
		sp := byPeriod[rangeKey]
		row := deviceUsageRow{
			ID:            id,
			Name:          name,
			Platform:      platform,
			Country:       country,
			LastSeen:      lastSeen,
			W24h:          w24,
			W3d:           w3,
			W7d:           w7,
			W30d:          w30,
			WAll:          wall,
			Bars:          visible,
			AvgDownMBps:   sp.AvgDown,
			AvgDownLabel:  usage.FormatMBps(sp.AvgDown),
			BestDownMBps:  sp.BestDown,
			BestDownLabel: usage.FormatMBps(sp.BestDown),
			AvgUpLabel:    usage.FormatMBps(sp.AvgUp),
			ActiveHours:   sp.Hours,
			Link:          "/admin/devices/" + id,
			Tone:          usageTone(windowsOf(visible)...),
		}
		out.Devices = append(out.Devices, row)
		totalRX += headerWindow.RX
		totalTX += headerWindow.TX
		if headerWindow.RX > 0 {
			out.ActiveDevices++
		}
		if headerWindow.NearCap {
			out.NearCap++
		}
		if headerWindow.OverCap {
			out.OverCap++
		}
		if sp.Hours > 0 {
			peakSum += sp.AvgDown
			peakDevices++
		}
		if sp.BestDown > bestPeak {
			bestPeak = sp.BestDown
		}
	}
	if err := rows.Err(); err != nil {
		return usageAnalyticsView{}, err
	}

	out.DeviceCount = len(out.Devices)
	out.TotalRXHuman = humanBytes(totalRX)
	out.TotalTXHuman = humanBytes(totalTX)
	fleetAvg := 0.0
	if peakDevices > 0 {
		fleetAvg = peakSum / float64(peakDevices)
	}
	out.AvgPeakLabel = usage.FormatMBps(math.Round(fleetAvg*100)/100) + " MB/s"
	out.BestPeakLabel = usage.FormatMBps(bestPeak) + " MB/s"
	sortDeviceUsage(out.Devices, rangeKey)
	return out, nil
}

func parseUsageRanges(r *http.Request) map[string]bool {
	raw := strings.TrimSpace(r.URL.Query().Get("ranges"))
	if raw == "" {
		if c, err := r.Cookie(usageRangesCookie); err == nil {
			raw = strings.TrimSpace(c.Value)
		}
	}
	set := map[string]bool{}
	if raw == "" {
		for _, opt := range usageRangeCatalog {
			set[opt.Key] = true
		}
		return set
	}
	for _, part := range strings.Split(raw, ",") {
		key := strings.ToLower(strings.TrimSpace(part))
		if usageRangeKnown(key) {
			set[key] = true
		}
	}
	if len(set) == 0 {
		set["7d"] = true
	}
	return set
}

func persistUsageRanges(w http.ResponseWriter, selected map[string]bool) {
	http.SetCookie(w, &http.Cookie{
		Name:     usageRangesCookie,
		Value:    joinUsageRanges(selected),
		Path:     "/admin",
		MaxAge:   10 * 365 * 24 * 60 * 60,
		SameSite: http.SameSiteLaxMode,
		Secure:   true,
	})
}

func usageRangeKnown(key string) bool {
	for _, opt := range usageRangeCatalog {
		if opt.Key == key {
			return true
		}
	}
	return false
}

func joinUsageRanges(selected map[string]bool) string {
	parts := make([]string, 0, len(usageRangeCatalog))
	for _, opt := range usageRangeCatalog {
		if selected[opt.Key] {
			parts = append(parts, opt.Key)
		}
	}
	return strings.Join(parts, ",")
}

func usageRangeOptions(selected map[string]bool) []usageRangeOpt {
	out := make([]usageRangeOpt, 0, len(usageRangeCatalog))
	for _, opt := range usageRangeCatalog {
		on := selected[opt.Key]
		next := map[string]bool{}
		for k, v := range selected {
			if v {
				next[k] = true
			}
		}
		if on {
			if len(next) > 1 {
				delete(next, opt.Key)
			}
		} else {
			next[opt.Key] = true
		}
		q := url.Values{}
		q.Set("ranges", joinUsageRanges(next))
		out = append(out, usageRangeOpt{
			Key:   opt.Key,
			Label: opt.Label,
			On:    on,
			Href:  "/admin/analytics?" + q.Encode(),
		})
	}
	return out
}

func usageShownLabel(selected map[string]bool) string {
	parts := make([]string, 0, len(usageRangeCatalog))
	for _, opt := range usageRangeCatalog {
		if selected[opt.Key] {
			parts = append(parts, opt.Label)
		}
	}
	return strings.Join(parts, ", ")
}

func widestUsageRange(selected map[string]bool) string {
	for _, key := range []string{"life", "1m", "7d", "3d", "24h"} {
		if selected[key] {
			return key
		}
	}
	return "7d"
}

func visibleUsageBars(selected map[string]bool, byPeriod map[string]hourlyPeakSpeed, w24, w3, w7, w30, wall usageWindowStats) []usageBar {
	all := []usageBar{
		barWithSpeed("24h", "24h", w24, byPeriod),
		barWithSpeed("3d", "3d", w3, byPeriod),
		barWithSpeed("7d", "7d", w7, byPeriod),
		barWithSpeed("1m", "1m", w30, byPeriod),
		barWithSpeed("life", "life", wall, byPeriod),
	}
	out := make([]usageBar, 0, len(all))
	for _, bar := range all {
		if selected[bar.Key] {
			out = append(out, bar)
		}
	}
	return out
}

func barWithSpeed(key, label string, stats usageWindowStats, byPeriod map[string]hourlyPeakSpeed) usageBar {
	sp := byPeriod[key]
	return usageBar{
		Key:              key,
		Label:            label,
		AvgLabel:         usage.FormatMBps(sp.AvgDown),
		BestLabel:        usage.FormatMBps(sp.BestDown),
		usageWindowStats: stats,
	}
}

func windowsOf(bars []usageBar) []usageWindowStats {
	out := make([]usageWindowStats, 0, len(bars))
	for _, bar := range bars {
		out = append(out, bar.usageWindowStats)
	}
	return out
}

func usageRangeLabel(key string) string {
	switch key {
	case "24h":
		return "Last 24 hours"
	case "3d":
		return "Last 3 days"
	case "1m":
		return "Last 30 days"
	case "life":
		return "Lifetime"
	default:
		return "Last 7 days"
	}
}

func selectedWindow(key string, w24, w3, w7, w30, wall usageWindowStats) usageWindowStats {
	switch key {
	case "24h":
		return w24
	case "3d":
		return w3
	case "1m":
		return w30
	case "life":
		return wall
	default:
		return w7
	}
}

type hourlyPeakSpeed struct {
	AvgDown, BestDown, AvgUp float64
	Hours                    int
}

// loadPeriodPeakSpeeds returns, per device and window, the average and best
// hourly download peaks. An hour counts only when it downloaded at least 1 MiB,
// so idle time does not lower the average. The hour's peak is its fastest ~15s sample.
func (h *Handler) loadPeriodPeakSpeeds(ctx context.Context, until, since24h, since3d, since7d, since30d time.Time) (map[string]map[string]hourlyPeakSpeed, error) {
	rows, err := h.DB.QueryContext(ctx, `
		SELECT p.device_id,
			DATE_FORMAT(MIN(s.sampled_at), '%Y-%m-%d %H:%i:%s'),
			CAST(MAX(s.rx_delta) AS DOUBLE)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at < ?
		GROUP BY p.device_id, DATE_FORMAT(s.sampled_at, '%Y-%m-%d %H')
		HAVING SUM(s.rx_delta) >= ?`, until, activeHourMinRX)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	type acc struct {
		sum  float64
		best float64
		n    int
	}
	add := func(a *acc, peak float64) {
		mbps := bytesDeltaToMBps(peak)
		a.sum += mbps
		a.n++
		if mbps > a.best {
			a.best = mbps
		}
	}
	raw := map[string]map[string]*acc{}
	ensure := func(id, key string) *acc {
		byKey := raw[id]
		if byKey == nil {
			byKey = map[string]*acc{}
			raw[id] = byKey
		}
		a := byKey[key]
		if a == nil {
			a = &acc{}
			byKey[key] = a
		}
		return a
	}

	for rows.Next() {
		var id, hourRaw string
		var peak float64
		if err := rows.Scan(&id, &hourRaw, &peak); err != nil {
			return nil, err
		}
		hour, err := time.ParseInLocation("2006-01-02 15:04:05", hourRaw, time.UTC)
		if err != nil {
			continue
		}
		add(ensure(id, "life"), peak)
		if !hour.Before(since30d) {
			add(ensure(id, "1m"), peak)
		}
		if !hour.Before(since7d) {
			add(ensure(id, "7d"), peak)
		}
		if !hour.Before(since3d) {
			add(ensure(id, "3d"), peak)
		}
		if !hour.Before(since24h) {
			add(ensure(id, "24h"), peak)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	out := make(map[string]map[string]hourlyPeakSpeed, len(raw))
	for id, byKey := range raw {
		out[id] = map[string]hourlyPeakSpeed{}
		for key, a := range byKey {
			avg := 0.0
			if a.n > 0 {
				avg = math.Round((a.sum/float64(a.n))*100) / 100
			}
			out[id][key] = hourlyPeakSpeed{AvgDown: avg, BestDown: a.best, Hours: a.n}
		}
	}
	return out, nil
}

func usageTone(windows ...usageWindowStats) string {
	over, near := false, false
	for _, w := range windows {
		if w.OverCap {
			over = true
		} else if w.NearCap {
			near = true
		}
	}
	if over {
		return "over"
	}
	if near {
		return "near"
	}
	return ""
}

func makeWindowStats(rx, tx uint64) usageWindowStats {
	pct := 0.0
	if usageCapBytes > 0 {
		pct = float64(rx) / float64(usageCapBytes) * 100
	}
	bar := pct
	if bar > 100 {
		bar = 100
	}
	return usageWindowStats{
		RX:          rx,
		TX:          tx,
		RXHuman:     humanBytes(rx),
		TXHuman:     humanBytes(tx),
		RXPctOfCap:  math.Round(pct*10) / 10,
		BarWidthPct: math.Round(bar*10) / 10,
		NearCap:     rx >= uint64(float64(usageCapBytes)*0.8),
		OverCap:     rx >= usageCapBytes,
	}
}

func bytesDeltaToMBps(delta float64) float64 {
	if delta <= 0 {
		return 0
	}
	mbps := delta / sampleIntervalSec / 1_000_000.0
	return math.Round(mbps*100) / 100
}

func sortDeviceUsage(list []deviceUsageRow, sortKey string) {
	sort.SliceStable(list, func(i, j int) bool {
		a, b := list[i], list[j]
		switch sortKey {
		case "24h":
			if a.W24h.RX != b.W24h.RX {
				return a.W24h.RX > b.W24h.RX
			}
		case "3d":
			if a.W3d.RX != b.W3d.RX {
				return a.W3d.RX > b.W3d.RX
			}
		case "1m":
			if a.W30d.RX != b.W30d.RX {
				return a.W30d.RX > b.W30d.RX
			}
		case "life":
			if a.WAll.RX != b.WAll.RX {
				return a.WAll.RX > b.WAll.RX
			}
		case "speed":
			if a.AvgDownMBps != b.AvgDownMBps {
				return a.AvgDownMBps > b.AvgDownMBps
			}
		default:
			if a.W7d.RX != b.W7d.RX {
				return a.W7d.RX > b.W7d.RX
			}
		}
		return a.Name < b.Name
	})
}
