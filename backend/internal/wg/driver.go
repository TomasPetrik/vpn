package wg

import (
	"fmt"
	"net"
	"time"
)

// Driver applies WireGuard peer state to a kernel interface (or a no-op fake).
type Driver interface {
	UpsertPeer(publicKey string, allowedIPv4 net.IP) error
	RemovePeer(publicKey string) error
	// PeerStats returns live kernel counters for peers on the managed interface.
	PeerStats() ([]PeerStat, error)
}

// PeerStat is one peer's live counters from the WireGuard device.
//
// Admin UI labels (client perspective):
//   - RxBytes = download to client  = kernel TransmitBytes
//   - TxBytes = upload from client  = kernel ReceiveBytes
type PeerStat struct {
	PublicKey     string
	RxBytes       uint64 // download to client
	TxBytes       uint64 // upload from client
	LastHandshake time.Time
	HasHandshake  bool
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
func (Fake) PeerStats() ([]PeerStat, error)  { return nil, nil }
