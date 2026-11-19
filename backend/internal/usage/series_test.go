package usage

import (
	"testing"
	"time"
)

func TestParseRange7d(t *testing.T) {
	now := time.Date(2026, 11, 18, 15, 30, 0, 0, time.UTC)
	ar := ParseRange("7d", now)
	if ar.Key != "7d" || ar.Hourly {
		t.Fatalf("unexpected range: %+v", ar)
	}
	if got, want := ar.Until, time.Date(2026, 11, 19, 0, 0, 0, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("until=%v want=%v", got, want)
	}
	if got, want := ar.Since, time.Date(2026, 11, 12, 0, 0, 0, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("since=%v want=%v", got, want)
	}
}

func TestFillBucketsDailyZeros(t *testing.T) {
	ar := ParseRange("7d", time.Date(2026, 11, 18, 12, 0, 0, 0, time.UTC))
	points := fillBuckets(ar, map[string]Point{
		"2026-11-15": {Date: "2026-11-15", Label: "Sun", RxBytes: 100, TxBytes: 50},
	})
	if len(points) != 7 {
		t.Fatalf("len=%d want 7", len(points))
	}
	var found bool
	for _, p := range points {
		if p.Date == "2026-11-15" {
			found = true
			if p.RxBytes != 100 || p.TxBytes != 50 {
				t.Fatalf("point=%+v", p)
			}
		}
		if p.Date == "2026-11-12" && (p.RxBytes != 0 || p.TxBytes != 0) {
			t.Fatalf("expected zero day, got %+v", p)
		}
	}
	if !found {
		t.Fatal("missing populated day")
	}
}

func TestParseRangeAllMonthly(t *testing.T) {
	now := time.Date(2026, 11, 19, 11, 0, 0, 0, time.UTC)
	ar := ParseRange("all", now)
	if ar.Key != "all" || !ar.Monthly || ar.Hourly {
		t.Fatalf("unexpected range: %+v", ar)
	}
	if got, want := ar.Since, time.Date(2025, 12, 1, 0, 0, 0, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("since=%v want=%v", got, want)
	}
	if got, want := ar.Until, time.Date(2026, 12, 1, 0, 0, 0, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("until=%v want=%v", got, want)
	}
}

func TestFillBucketsMonthly(t *testing.T) {
	ar := ParseRange("all", time.Date(2026, 11, 19, 11, 0, 0, 0, time.UTC))
	points := fillBuckets(ar, map[string]Point{
		"2026-03-01": {Date: "2026-03-01", Label: "Mar", RxBytes: 1000, TxBytes: 200},
	})
	if len(points) != 12 {
		t.Fatalf("len=%d want 12", len(points))
	}
	if points[0].Date != "2025-12-01" || points[0].Label != "Dec" {
		t.Fatalf("first=%+v", points[0])
	}
	if points[len(points)-1].Date != "2026-11-01" || points[len(points)-1].Label != "Nov" {
		t.Fatalf("last=%+v", points[len(points)-1])
	}
	var found bool
	for _, p := range points {
		if p.Date == "2026-03-01" {
			found = true
			if p.RxBytes != 1000 || p.TxBytes != 200 {
				t.Fatalf("march=%+v", p)
			}
		}
	}
	if !found {
		t.Fatal("missing march bucket")
	}
}
