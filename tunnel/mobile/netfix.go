package tunnel

import (
	"errors"
	"net"
	"net/netip"
	"time"

	"tailscale.com/net/netmon"
)

// Android (11+) forbids app processes from netlink and net.Interfaces(), which tsnet needs at start-up.
// Register our own interface list: one synthetic interface carrying the addresses the kernel picks for
// outbound sockets (dialing UDP sends no packets and is permitted).
func init() {
	netmon.RegisterInterfaceGetter(func() ([]netmon.Interface, error) {
		var addrs []net.Addr
		if ip, ok := outboundIP("udp4", "8.8.8.8:53"); ok {
			addrs = append(addrs, &net.IPNet{IP: ip.AsSlice(), Mask: net.CIDRMask(32, 32)})
		}
		if ip, ok := outboundIP("udp6", "[2001:4860:4860::8888]:53"); ok {
			addrs = append(addrs, &net.IPNet{IP: ip.AsSlice(), Mask: net.CIDRMask(128, 128)})
		}
		if len(addrs) == 0 {
			return nil, errors.New("no outbound route (offline?)")
		}
		return []netmon.Interface{{
			Interface: &net.Interface{Index: 1, MTU: 1500, Name: "android", Flags: net.FlagUp | net.FlagRunning},
			AltAddrs:  addrs,
		}}, nil
	})
}

func outboundIP(network, addr string) (netip.Addr, bool) {
	c, err := (&net.Dialer{Timeout: 2 * time.Second}).Dial(network, addr)
	if err != nil {
		return netip.Addr{}, false
	}
	defer c.Close()
	ua, ok := c.LocalAddr().(*net.UDPAddr)
	if !ok {
		return netip.Addr{}, false
	}
	ip, ok := netip.AddrFromSlice(ua.IP)
	if !ok {
		return netip.Addr{}, false
	}
	ip = ip.Unmap()
	if ip.IsLoopback() || ip.IsUnspecified() {
		return netip.Addr{}, false
	}
	return ip, true
}
