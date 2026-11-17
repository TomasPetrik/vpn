package wg

import (
	"encoding/base64"
	"fmt"
	"net"

	"golang.zx2c4.com/wireguard/wgctrl"
	"golang.zx2c4.com/wireguard/wgctrl/wgtypes"
)

type Netlink struct {
	iface  string
	client *wgctrl.Client
}

func NewNetlink(iface string) (*Netlink, error) {
	if iface == "" {
		iface = "wg1"
	}
	client, err := wgctrl.New()
	if err != nil {
		return nil, fmt.Errorf("wgctrl: %w", err)
	}
	return &Netlink{iface: iface, client: client}, nil
}

func (n *Netlink) UpsertPeer(publicKey string, allowedIPv4 net.IP) error {
	key, err := parseKey(publicKey)
	if err != nil {
		return err
	}
	ip := allowedIPv4.To4()
	if ip == nil {
		return fmt.Errorf("allowed IP must be IPv4")
	}
	prefix := net.IPNet{IP: ip, Mask: net.CIDRMask(32, 32)}
	cfg := wgtypes.Config{
		Peers: []wgtypes.PeerConfig{{
			PublicKey:         key,
			ReplaceAllowedIPs: true,
			AllowedIPs:        []net.IPNet{prefix},
		}},
	}
	if err := n.client.ConfigureDevice(n.iface, cfg); err != nil {
		return fmt.Errorf("configure %s: %w", n.iface, err)
	}
	return nil
}

func (n *Netlink) RemovePeer(publicKey string) error {
	key, err := parseKey(publicKey)
	if err != nil {
		return err
	}
	cfg := wgtypes.Config{
		Peers: []wgtypes.PeerConfig{{
			PublicKey: key,
			Remove:    true,
		}},
	}
	if err := n.client.ConfigureDevice(n.iface, cfg); err != nil {
		return fmt.Errorf("remove peer on %s: %w", n.iface, err)
	}
	return nil
}

func (n *Netlink) PeerStats() ([]PeerStat, error) {
	dev, err := n.client.Device(n.iface)
	if err != nil {
		return nil, fmt.Errorf("device %s: %w", n.iface, err)
	}
	out := make([]PeerStat, 0, len(dev.Peers))
	for _, p := range dev.Peers {
		st := PeerStat{
			PublicKey: p.PublicKey.String(),
			// Map kernel → admin (client) direction.
			RxBytes: uint64(p.TransmitBytes),
			TxBytes: uint64(p.ReceiveBytes),
		}
		if !p.LastHandshakeTime.IsZero() {
			st.LastHandshake = p.LastHandshakeTime.UTC()
			st.HasHandshake = true
		}
		out = append(out, st)
	}
	return out, nil
}

func parseKey(publicKey string) (wgtypes.Key, error) {
	raw, err := base64.StdEncoding.DecodeString(publicKey)
	if err != nil {
		return wgtypes.Key{}, fmt.Errorf("public key base64: %w", err)
	}
	if len(raw) != wgtypes.KeyLen {
		return wgtypes.Key{}, fmt.Errorf("public key length %d, want %d", len(raw), wgtypes.KeyLen)
	}
	var key wgtypes.Key
	copy(key[:], raw)
	return key, nil
}
