package wg

import (
	"net"
	"testing"
)

func TestFakeDriver(t *testing.T) {
	d, err := New("fake", "wg1")
	if err != nil {
		t.Fatal(err)
	}
	if err := d.UpsertPeer("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", net.IPv4(10, 201, 0, 4)); err != nil {
		t.Fatal(err)
	}
	if err := d.RemovePeer("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="); err != nil {
		t.Fatal(err)
	}
}

func TestUnknownDriver(t *testing.T) {
	_, err := New("nope", "wg1")
	if err == nil {
		t.Fatal("expected error")
	}
}
