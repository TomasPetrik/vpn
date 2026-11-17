package wg

import (
	"fmt"
	"net"
)

// Driver applies WireGuard peer state to a kernel interface (or a no-op fake).
type Driver interface {
	UpsertPeer(publicKey string, allowedIPv4 net.IP) error
	RemovePeer(publicKey string) error
}

func New(driverName, iface string) (Driver, error) {
	switch driverName {
	case "", "fake":
		return Fake{}, nil
	case "netlink":
		return NewNetlink(iface)
	default:
		return nil, fmt.Errorf("unknown WG_DRIVER %q", driverName)
	}
}

// Fake is used in unit tests / local runs without WireGuard.
type Fake struct{}

func (Fake) UpsertPeer(string, net.IP) error { return nil }
func (Fake) RemovePeer(string) error         { return nil }
