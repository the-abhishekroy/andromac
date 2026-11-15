// andromac-tunnel: the Mac sidecar. Joins the user's tailnet and forwards
// tailnet:8765 to the Andromac app listening on 127.0.0.1:8765.
// Prints one JSON object per line on stdout for the app to read.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strconv"
	"strings"

	"andromac/tunnel/core"
)

func main() {
	dir := flag.String("dir", "", "state directory")
	host := flag.String("host", "andromac-mac", "tailnet hostname")
	port := flag.String("port", "8765", "port to expose on the tailnet")
	target := flag.String("target", "127.0.0.1:8765", "local address to forward to")
	extra := flag.String("forward", "", "extra tailnet ports to expose, comma separated: 22=127.0.0.1:22,...")
	flag.Parse()
	if *dir == "" {
		fmt.Fprintln(os.Stderr, "need -dir")
		os.Exit(2)
	}
	os.MkdirAll(*dir, 0o700)
	os.Setenv("TS_NO_LOGS_NO_SUPPORT", "true") // keep logs local
	emit := func(state, detail string) {
		b, _ := json.Marshal(map[string]string{"state": state, "detail": detail})
		fmt.Println(string(b))
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	n := core.NewNode(*dir, *host, os.Getenv("ANDROMAC_TS_AUTHKEY"), emit)
	if err := n.Start(ctx); err != nil {
		emit("error", err.Error())
		os.Exit(1)
	}
	if err := n.ServeForward(*port, *target); err != nil {
		emit("error", err.Error())
		os.Exit(1)
	}
	// control channel: the app writes "logout", "login" or "account" lines to our stdin
	go func() {
		sc := bufio.NewScanner(os.Stdin)
		for sc.Scan() {
			switch sc.Text() {
			case "logout":
				if err := n.Logout(); err != nil {
					emit("error", err.Error())
				}
			case "login":
				n.Login()
			case "account":
				emit("account", n.Account())
			default:
				// "proxy <localPort> <host:port>": make 127.0.0.1:<localPort> reach a tailnet peer (e.g. the phone's SSH)
				var port int
				var remote string
				if c, _ := fmt.Sscanf(sc.Text(), "proxy %d %s", &port, &remote); c == 2 {
					if _, err := n.LocalProxyOn(port, remote); err != nil {
						emit("error", "proxy "+strconv.Itoa(port)+": "+err.Error())
					}
				}
			}
		}
		// stdin closed: the app that started us is gone, so shut down instead of lingering
		n.Close()
		os.Exit(0)
	}()
	for _, f := range strings.Split(*extra, ",") {
		if f == "" {
			continue
		}
		kv := strings.SplitN(f, "=", 2)
		if len(kv) != 2 {
			continue
		}
		if err := n.ServeForward(kv[0], kv[1]); err != nil {
			emit("error", "forward "+kv[0]+": "+err.Error())
		}
	}
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	<-c
	n.Close()
}
