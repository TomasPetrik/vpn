package limits

import (
	"database/sql"
	"testing"
)

func TestResolvePrecedence(t *testing.T) {
	global := Policy{DownloadKbps: sql.NullInt64{Int64: 1000, Valid: true}}
	plan := Policy{DownloadKbps: sql.NullInt64{Int64: 5000, Valid: true}}
	user := Policy{} // inherit
	device := Policy{DownloadKbps: sql.NullInt64{Int64: 2000, Valid: true}}

	c := Resolve(device, user, plan, global)
	if c.DownloadKbps == nil || *c.DownloadKbps != 2000 {
		t.Fatalf("device should win: %+v", c.DownloadKbps)
	}
	if c.DownloadSource != SourceDevice {
		t.Fatalf("source=%s", c.DownloadSource)
	}
}

func TestResolveExplicitUnlimited(t *testing.T) {
	global := Policy{DownloadKbps: sql.NullInt64{Int64: 1000, Valid: true}}
	user := Policy{DownloadKbps: sql.NullInt64{Int64: 0, Valid: true}} // unlimited
	c := Resolve(Policy{}, user, Policy{}, global)
	if c.DownloadKbps != nil {
		t.Fatalf("expected unlimited, got %v", *c.DownloadKbps)
	}
	if c.DownloadSource != SourceUser {
		t.Fatalf("source=%s", c.DownloadSource)
	}
}

func TestResolveInheritToGlobal(t *testing.T) {
	global := Policy{UploadKbps: sql.NullInt64{Int64: 800, Valid: true}}
	c := Resolve(Policy{}, Policy{}, Policy{}, global)
	if c.UploadKbps == nil || *c.UploadKbps != 800 {
		t.Fatalf("got %+v", c.UploadKbps)
	}
	if c.UploadSource != SourceGlobal {
		t.Fatalf("source=%s", c.UploadSource)
	}
}

func TestParseFormField(t *testing.T) {
	n, err := ParseFormField("")
	if err != nil || n.Valid {
		t.Fatalf("empty: %+v %v", n, err)
	}
	n, err = ParseFormField("0")
	if err != nil || !n.Valid || n.Int64 != 0 {
		t.Fatalf("0: %+v %v", n, err)
	}
	n, err = ParseFormField("1500")
	if err != nil || !n.Valid || n.Int64 != 1500 {
		t.Fatalf("1500: %+v %v", n, err)
	}
}
