// Package tunnel is the gomobile-bound API used by the Android app.
package tunnel

import (
	"context"
	"fmt"
	"os"

	"andromac/tunnel/core"

	// Android denies apps /proc/net and netlink; DNS needs a fallback when there is no resolv.conf.
	_ "tailscale.com/feature/androiddns"
)

// Listener receives state changes. state: starting | login | running | error.
type Listener interface {
	OnState(state string, detail string)
}

var node *core.Node

// Start joins the tailnet. dir is the app's private storage; safe to call once per process.
func Start(dir, hostname string, l Listener) error {
	if node != nil {
		return nil
	}
	// Android apps have no HOME / cache dir in the environment; tailscale's log policy panics without one.
	os.MkdirAll(dir, 0o700)
	os.Setenv("TS_LOGS_DIR", dir)
	os.Setenv("HOME", dir)
	os.Setenv("XDG_CACHE_HOME", dir)
	os.Setenv("XDG_CONFIG_HOME", dir)
	os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true") // don't upload logs to Tailscale
	node = core.NewNode(dir, hostname, "", func(s, d string) { l.OnState(s, d) })
	return node.Start(context.Background())
}

// Proxy returns a localhost port that forwards to remote ("100.x.y.z:8765") over the tailnet.
func Proxy(remote string) (int, error) {
	if node == nil {
		return 0, errNotStarted
	}
	p, err := node.LocalProxy(remote)
	return p, err
}

// ProxyOn forwards 127.0.0.1:<port> to remote over the tailnet (e.g. a terminal bridge: 2222 -> Mac:22).
func ProxyOn(port int, remote string) error {
	if node == nil {
		return errNotStarted
	}
	_, err := node.LocalProxyOn(port, remote)
	return err
}

// Serve exposes this phone's local port (e.g. Termux sshd on 127.0.0.1:8022) on the tailnet at the same port number.
func Serve(port int, target string) error {
	if node == nil {
		return errNotStarted
	}
	return node.ServeForward(fmt.Sprintf("%d", port), target)
}

// Account returns "login|hostname|ip" ("" if not signed in).
func Account() string {
	if node == nil {
		return ""
	}
	return node.Account()
}

// Logout signs out and starts a new login (a "login" event with a fresh URL follows).
func Logout() error {
	if node == nil {
		return errNotStarted
	}
	return node.Logout()
}

// IP returns this device's tailnet IPv4, or "" if not up yet.
func IP() string {
	if node == nil {
		return ""
	}
	return node.IP()
}

type tunnelErr string

func (e tunnelErr) Error() string { return string(e) }

const errNotStarted = tunnelErr("tunnel not started")
