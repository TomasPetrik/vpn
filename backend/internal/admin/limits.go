package admin

import (
	"net/http"
	"time"

	"github.com/TomasPetrik/vpn/backend/internal/limits"
)

func (h *Handler) limitsStore() *limits.Store {
	return &limits.Store{DB: h.DB}
}

type policyFormView struct {
	Code               string
	DownloadKbps       string
	UploadKbps         string
	MonthlyQuotaBytes  string
}

func policyForm(code string, p limits.Policy) policyFormView {
	return policyFormView{
		Code:              code,
		DownloadKbps:      limits.FormatFormValue(p.DownloadKbps),
		UploadKbps:        limits.FormatFormValue(p.UploadKbps),
		MonthlyQuotaBytes: limits.FormatFormValue(p.MonthlyQuotaBytes),
	}
}

func (h *Handler) LimitsGet(w http.ResponseWriter, r *http.Request) {
	store := h.limitsStore()
	global, err := store.LoadGlobal(r.Context())
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	plans, err := store.ListPlans(r.Context())
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	planViews := make([]policyFormView, 0, len(plans))
	for _, p := range plans {
		planViews = append(planViews, policyForm(p.Code, p.Policy))
	}
	_ = h.Tmpl.ExecuteTemplate(w, "limits.html", map[string]any{
		"Global": policyForm("", global.Policy),
		"Plans":  planViews,
		"CSRF":   csrfFrom(r),
		"Flash":  r.URL.Query().Get("saved"),
	})
}

func (h *Handler) LimitsPost(w http.ResponseWriter, r *http.Request) {
	_ = r.ParseForm()
	if r.Form.Get("csrf") != csrfFrom(r) {
		http.Error(w, "csrf", 403)
		return
	}
	store := h.limitsStore()
	scope := r.Form.Get("scope")
	switch scope {
	case "global":
		p, err := parsePolicyForm(r, "")
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err := store.SaveGlobal(r.Context(), p); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	case "plan":
		code := r.Form.Get("plan")
		p, err := parsePolicyForm(r, "")
		if err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		if err := store.SavePlan(r.Context(), code, p); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
	default:
		http.Error(w, "unknown scope", 400)
		return
	}
	http.Redirect(w, r, "/admin/limits?saved=1", http.StatusSeeOther)
}

func (h *Handler) UserLimitsPost(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.NotFound(w, r)
		return
	}
	_ = r.ParseForm()
	if r.Form.Get("csrf") != csrfFrom(r) {
		http.Error(w, "csrf", 403)
		return
	}
	plan := r.Form.Get("plan")
	p, err := parsePolicyForm(r, "")
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	if err := h.limitsStore().SaveUserOverrides(r.Context(), id, plan, p); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	http.Redirect(w, r, "/admin/users/"+id, http.StatusSeeOther)
}

func (h *Handler) DeviceLimitsPost(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.NotFound(w, r)
		return
	}
	_ = r.ParseForm()
	if r.Form.Get("csrf") != csrfFrom(r) {
		http.Error(w, "csrf", 403)
		return
	}
	p, err := parsePolicyForm(r, "")
	if err != nil {
		http.Error(w, err.Error(), 400)
		return
	}
	if err := h.limitsStore().SaveDeviceOverrides(r.Context(), id, p); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	http.Redirect(w, r, "/admin/devices/"+id, http.StatusSeeOther)
}

func parsePolicyForm(r *http.Request, _ string) (limits.Policy, error) {
	var p limits.Policy
	var err error
	if p.DownloadKbps, err = limits.ParseFormField(r.Form.Get("download_kbps")); err != nil {
		return p, err
	}
	if p.UploadKbps, err = limits.ParseFormField(r.Form.Get("upload_kbps")); err != nil {
		return p, err
	}
	if p.MonthlyQuotaBytes, err = limits.ParseFormField(r.Form.Get("monthly_quota_bytes")); err != nil {
		return p, err
	}
	return p, nil
}

type limitsView struct {
	Effective        limits.Effective
	Override         limits.Policy
	Plan             string
	DownloadHuman    string
	UploadHuman      string
	QuotaHuman       string
	UsedHuman        string
	DownloadKbpsForm string
	UploadKbpsForm   string
	QuotaBytesForm   string
}

func (h *Handler) loadLimitsViewForDevice(r *http.Request, deviceID string) (limitsView, error) {
	store := h.limitsStore()
	eff, err := store.ForDevice(r.Context(), deviceID, time.Now().UTC())
	if err != nil {
		return limitsView{}, err
	}
	_, pol, err := store.DevicePolicy(r.Context(), deviceID)
	if err != nil {
		return limitsView{}, err
	}
	return limitsView{
		Effective:        eff,
		Override:         pol,
		Plan:             eff.PlanCode,
		DownloadHuman:    limits.DisplayCap(eff.DownloadKbps, "kbps"),
		UploadHuman:      limits.DisplayCap(eff.UploadKbps, "kbps"),
		QuotaHuman:       limits.DisplayCap(eff.MonthlyQuotaBytes, "bytes"),
		UsedHuman:        limits.HumanBytes(eff.MonthlyUsedBytes),
		DownloadKbpsForm: limits.FormatFormValue(pol.DownloadKbps),
		UploadKbpsForm:   limits.FormatFormValue(pol.UploadKbps),
		QuotaBytesForm:   limits.FormatFormValue(pol.MonthlyQuotaBytes),
	}, nil
}

func (h *Handler) loadLimitsViewForUser(r *http.Request, userID string) (limitsView, error) {
	store := h.limitsStore()
	eff, err := store.ForUser(r.Context(), userID, time.Now().UTC())
	if err != nil {
		return limitsView{}, err
	}
	plan, pol, err := store.UserPolicy(r.Context(), userID)
	if err != nil {
		return limitsView{}, err
	}
	return limitsView{
		Effective:        eff,
		Override:         pol,
		Plan:             plan,
		DownloadHuman:    limits.DisplayCap(eff.DownloadKbps, "kbps"),
		UploadHuman:      limits.DisplayCap(eff.UploadKbps, "kbps"),
		QuotaHuman:       limits.DisplayCap(eff.MonthlyQuotaBytes, "bytes"),
		UsedHuman:        limits.HumanBytes(eff.MonthlyUsedBytes),
		DownloadKbpsForm: limits.FormatFormValue(pol.DownloadKbps),
		UploadKbpsForm:   limits.FormatFormValue(pol.UploadKbps),
		QuotaBytesForm:   limits.FormatFormValue(pol.MonthlyQuotaBytes),
	}, nil
}
