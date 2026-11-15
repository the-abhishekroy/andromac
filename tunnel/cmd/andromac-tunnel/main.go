// andromac-tunnel: the Mac background service. Joins the user's tailnet and forwards
// tailnet:8765 to the Andromac app on 127.0.0.1:8765 and tailnet:22 to ssh.
//
// Two modes:
//   child mode (default): started by the app; talks over stdin/stdout, exits when the app is gone.
//   -standalone: a launchd agent that keeps running when the app is closed. Clients (the app) attach to a unix
//   socket (-socket) to read events and send commands; the node itself never depends on them.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"time"
	"strconv"
	"strings"
	"sync"
	"syscall"

	"andromac/tunnel/core"
)

type hub struct {
	mu      sync.Mutex
	clients map[net.Conn]bool
	last    map[string]string // newest event per kind, replayed to every new client
	order   []string
}

func (h *hub) emit(state, detail string) {
	b, _ := json.Marshal(map[string]string{"state": state, "detail": detail})
	line := string(b) + "\n"
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.last[state]; !ok {
		h.order = append(h.order, state)
	}
	h.last[state] = line
	for c := range h.clients {
		io.WriteString(c, line)
	}
}

func (h *hub) attach(c net.Conn) {
	h.mu.Lock()
	h.clients[c] = true
	for _, k := range h.order {
		io.WriteString(c, h.last[k])
	}
	h.mu.Unlock()
}

func (h *hub) detach(c net.Conn) { h.mu.Lock(); delete(h.clients, c); h.mu.Unlock(); c.Close() }

func main() {
	dir := flag.String("dir", "", "state directory")
	host := flag.String("host", "andromac-mac", "tailnet hostname")
	port := flag.String("port", "8765", "port to expose on the tailnet")
	target := flag.String("target", "127.0.0.1:8765", "local address to forward to")
	extra := flag.String("forward", "", "extra tailnet ports to expose, comma separated: 22=127.0.0.1:22,...")
	standalone := flag.Bool("standalone", false, "run as a background service that outlives the app")
	sock := flag.String("socket", "", "unix socket for the app to attach to (standalone mode)")
	flag.Parse()
	// keep the background service small: collect garbage early, cap the heap, return freed memory to macOS
	runtime.GOMAXPROCS(2)
	debug.SetGCPercent(30)
	debug.SetMemoryLimit(24 << 20)
	go func() { for range time.Tick(45 * time.Second) { debug.FreeOSMemory() } }()
	if *dir == "" {
		fmt.Fprintln(os.Stderr, "need -dir")
		os.Exit(2)
	}
	os.MkdirAll(*dir, 0o700)
	os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true") // keep logs local

	h := &hub{clients: map[net.Conn]bool{}, last: map[string]string{}}
	if !*standalone {
		h.clients[stdoutConn{}] = true
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	n := core.NewNode(*dir, *host, os.Getenv("ANDROMAC_TS_AUTHKEY"), h.emit)
	if err := n.Start(ctx); err != nil {
		h.emit("error", err.Error())
		os.Exit(1)
	}
	if err := n.ServeForward(*port, *target); err != nil {
		h.emit("error", err.Error())
		os.Exit(1)
	}
	for _, f := range strings.Split(*extra, ",") {
		kv := strings.SplitN(f, "=", 2)
		if len(kv) == 2 {
			if err := n.ServeForward(kv[0], kv[1]); err != nil {
				h.emit("error", "forward "+kv[0]+": "+err.Error())
			}
		}
	}

	command := func(line string) bool { // returns false to stop the service
		switch strings.TrimSpace(line) {
		case "logout":
			if err := n.Logout(); err != nil {
				h.emit("error", err.Error())
			}
		case "login":
			n.Login()
		case "account":
			h.emit("account", n.Account())
		case "shutdown":
			return false
		default:
			var p int
			var remote string
			if c, _ := fmt.Sscanf(line, "proxy %d %s", &p, &remote); c == 2 { // 127.0.0.1:p -> a tailnet peer (the phone's ssh or files)
				if _, err := n.LocalProxyOn(p, remote); err != nil {
					h.emit("error", "proxy "+strconv.Itoa(p)+": "+err.Error())
				}
			}
		}
		return true
	}
	stop := make(chan struct{})
	var once sync.Once
	quit := func() { once.Do(func() { close(stop) }) }

	if *standalone {
		if *sock == "" {
			fmt.Fprintln(os.Stderr, "need -socket in standalone mode")
			os.Exit(2)
		}
		os.Remove(*sock)
		ln, err := net.Listen("unix", *sock)
		if err != nil {
			fmt.Fprintln(os.Stderr, "socket:", err)
			os.Exit(1)
		}
		os.Chmod(*sock, 0o600)
		go func() {
			for {
				c, err := ln.Accept()
				if err != nil {
					return
				}
				h.attach(c)
				go func() {
					sc := bufio.NewScanner(c)
					for sc.Scan() {
						if !command(sc.Text()) {
							quit()
							return
						}
					}
					h.detach(c)
				}()
			}
		}()
	} else {
		go func() {
			sc := bufio.NewScanner(os.Stdin)
			for sc.Scan() {
				if !command(sc.Text()) {
					break
				}
			}
			quit() // stdin closed or shutdown: the app that started us is gone
		}()
	}

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	select {
	case <-sig:
	case <-stop:
	}
	n.Close()
	if *standalone {
		os.Remove(*sock)
	}
}

type stdoutConn struct{ net.Conn }

func (stdoutConn) Write(b []byte) (int, error) { return os.Stdout.Write(b) }
func (stdoutConn) Close() error                { return nil }
