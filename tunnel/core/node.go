// Package core embeds a Tailscale node (tsnet) inside Andromac so users never
// need the separate Tailscale app. It only forwards raw TCP; Andromac's own
// encrypted protocol runs on top.
package core

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"
	"io"
	"net"
	"sync"

	"tailscale.com/ipn"
	"tailscale.com/tsnet"
)

// EventFn receives state changes: ("starting"|"login"|"running"|"error", detail).
// login -> detail is the URL the user must open once; running -> detail is the node's tailnet IPv4.
type EventFn func(state, detail string)

type Node struct {
	srv  *tsnet.Server
	emit EventFn
	mu      sync.Mutex
	ip      string
	proxies map[int]net.Listener
}

func NewNode(dir, hostname, authKey string, emit EventFn) *Node {
	quiet := func(string, ...any) {}
	return &Node{
		emit: emit,
		srv: &tsnet.Server{
			Dir: dir, Hostname: hostname, AuthKey: authKey,
			Logf: quiet, UserLogf: quiet,
		},
	}
}

// Start brings the node up and watches its state in the background.
func (n *Node) Start(ctx context.Context) error {
	n.emit("starting", "")
	if err := n.srv.Start(); err != nil {
		return err
	}
	lc, err := n.srv.LocalClient()
	if err != nil {
		return err
	}
	w, err := lc.WatchIPNBus(ctx, ipn.NotifyInitialState|ipn.NotifyNoPrivateKeys)
	if err != nil {
		return err
	}
	go func() {
		defer w.Close()
		for {
			nt, err := w.Next()
			if err != nil {
				return
			}
			if nt.BrowseToURL != nil {
				n.emit("login", *nt.BrowseToURL)
			}
			if nt.State != nil {
				switch *nt.State {
				case ipn.Running:
					if ip4, _ := n.srv.TailscaleIPs(); ip4.IsValid() {
						n.mu.Lock()
						n.ip = ip4.String()
						n.mu.Unlock()
						n.emit("running", ip4.String())
						n.emit("account", n.Account())
					}
				case ipn.NeedsLogin, ipn.NeedsMachineAuth:
					n.emit("starting", "needs login")
				}
			}
		}
	}()
	return nil
}

// Account returns "login|hostname|ip" for the signed-in user, or "" if unknown.
func (n *Node) Account() string {
	lc, err := n.srv.LocalClient()
	if err != nil {
		return ""
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	st, err := lc.StatusWithoutPeers(ctx)
	if err != nil || st.Self == nil {
		return ""
	}
	login := ""
	if u, ok := st.User[st.Self.UserID]; ok {
		login = u.LoginName
	}
	ip := ""
	if len(st.TailscaleIPs) > 0 {
		ip = st.TailscaleIPs[0].String()
	}
	return strings.Join([]string{login, st.Self.HostName, ip}, "|")
}

// Logout signs this node out of the tailnet and starts a fresh interactive login (a new URL is emitted).
func (n *Node) Logout() error {
	lc, err := n.srv.LocalClient()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := lc.Logout(ctx); err != nil {
		return err
	}
	n.mu.Lock()
	n.ip = ""
	n.mu.Unlock()
	n.emit("starting", "signed out")
	return lc.StartLoginInteractive(ctx)
}

// Login starts an interactive login (emits a "login" URL).
func (n *Node) Login() error {
	lc, err := n.srv.LocalClient()
	if err != nil {
		return err
	}
	return lc.StartLoginInteractive(context.Background())
}

func (n *Node) IP() string { n.mu.Lock(); defer n.mu.Unlock(); return n.ip }

func (n *Node) Close() error { return n.srv.Close() }

// ServeForward accepts connections on the tailnet at :port and forwards them to the local target.
func (n *Node) ServeForward(port, target string) error {
	ln, err := n.srv.Listen("tcp", ":"+port)
	if err != nil {
		return err
	}
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				t, err := net.Dial("tcp", target)
				if err != nil {
					c.Close()
					return
				}
				pipe(c, t)
			}()
		}
	}()
	return nil
}

// LocalProxy opens a random 127.0.0.1 port and forwards each connection to remote over the tailnet.
func (n *Node) LocalProxy(remote string) (int, error) { return n.LocalProxyOn(0, remote) }

// LocalProxyOn is like LocalProxy but on a fixed local port (0 = pick one). Sessions survive network changes
// because the tailnet connection lives inside this process, not in the OS.
func (n *Node) LocalProxyOn(port int, remote string) (int, error) {
	n.mu.Lock()
	if old, ok := n.proxies[port]; ok && port != 0 {   // same port requested again (e.g. peer address changed): replace it
		old.Close()
	}
	n.mu.Unlock()
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return 0, err
	}
	n.mu.Lock()
	if n.proxies == nil {
		n.proxies = map[int]net.Listener{}
	}
	n.proxies[ln.Addr().(*net.TCPAddr).Port] = ln
	n.mu.Unlock()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
				defer cancel()
				r, err := n.srv.Dial(ctx, "tcp", remote)
				if err != nil {
					log.Printf("andromac: dial %s failed: %v", remote, err)
					c.Close()
					return
				}
				log.Printf("andromac: dial %s ok", remote)
				pipe(c, r)
			}()
		}
	}()
	return ln.Addr().(*net.TCPAddr).Port, nil
}

// pipe copies both ways and honours half-close, so a peer that finishes sending can still read the reply.
func pipe(a, b net.Conn) {
	done := make(chan struct{}, 2)
	cp := func(dst, src net.Conn) {
		io.Copy(dst, src)
		if cw, ok := dst.(interface{ CloseWrite() error }); ok {
			cw.CloseWrite()
		} else {
			dst.Close()
		}
		done <- struct{}{}
	}
	go cp(a, b)
	go cp(b, a)
	<-done
	<-done
	a.Close()
	b.Close()
}
