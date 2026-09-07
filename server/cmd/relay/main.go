// Command relay runs the Chatito blind relay server.
//
// Usage:
//
//	relay                         serve (env: RELAY_ADDR, RELAY_DATA_DIR, FCM_SERVICE_ACCOUNT_B64)
//	relay -healthcheck            GET /healthz on RELAY_ADDR; exit 0 when ok (Docker healthcheck)
//	relay admin bootstrap --name X   create the first admin user and print an invite
//	relay admin invite --user X      print an invite for user X (created as member if new)
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/felipemaion/chatito/server/internal/api"
	"github.com/felipemaion/chatito/server/internal/janitor"
	"github.com/felipemaion/chatito/server/internal/push"
	"github.com/felipemaion/chatito/server/internal/store"
	"github.com/felipemaion/chatito/server/internal/ws"
)

const (
	defaultAddr     = ":8080"
	defaultDataDir  = "./data"
	shutdownTimeout = 15 * time.Second
	healthTimeout   = 3 * time.Second
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	os.Exit(run(ctx, os.Args[1:], os.Getenv, os.Stdout, os.Stderr, nil))
}

// run is the testable entry point. ready (optional) receives the bound
// address once the server listens. Exit codes: 0 ok, 1 runtime error, 2 usage.
func run(ctx context.Context, args []string, getenv func(string) string, stdout, stderr io.Writer, ready chan<- string) int {
	fs := flag.NewFlagSet("relay", flag.ContinueOnError)
	fs.SetOutput(stderr)
	healthcheck := fs.Bool("healthcheck", false, "probe /healthz on RELAY_ADDR and exit")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *healthcheck {
		return runHealthcheck(ctx, envOr(getenv, "RELAY_ADDR", defaultAddr), stderr)
	}
	switch rest := fs.Args(); {
	case len(rest) == 0:
		return serve(ctx, getenv, stdout, stderr, ready)
	case rest[0] == "admin":
		return runAdmin(ctx, rest[1:], getenv, stdout, stderr)
	default:
		fmt.Fprintf(stderr, "unknown command %q\n", rest[0])
		return 2
	}
}

func envOr(getenv func(string) string, key, def string) string {
	if v := getenv(key); v != "" {
		return v
	}
	return def
}

// localURL turns a listen address (":8080", "0.0.0.0:8080") into a loopback URL.
func localURL(addr string) string {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return "http://" + addr
	}
	if host == "" || host == "0.0.0.0" || host == "::" {
		host = "127.0.0.1"
	}
	return "http://" + net.JoinHostPort(host, port)
}

func runHealthcheck(ctx context.Context, addr string, stderr io.Writer) int {
	ctx, cancel := context.WithTimeout(ctx, healthTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, localURL(addr)+"/healthz", nil)
	if err != nil {
		fmt.Fprintln(stderr, "healthcheck:", err)
		return 1
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		fmt.Fprintln(stderr, "healthcheck:", err)
		return 1
	}
	_ = res.Body.Close()
	if res.StatusCode != http.StatusOK {
		fmt.Fprintf(stderr, "healthcheck: status %d\n", res.StatusCode)
		return 1
	}
	return 0
}

func runAdmin(ctx context.Context, args []string, getenv func(string) string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, "usage: relay admin (bootstrap --name X | invite --user X)")
		return 2
	}
	fs := flag.NewFlagSet("relay admin "+args[0], flag.ContinueOnError)
	fs.SetOutput(stderr)
	name := fs.String("name", "", "admin user name (bootstrap)")
	user := fs.String("user", "", "user name (invite)")
	if err := fs.Parse(args[1:]); err != nil {
		return 2
	}
	var target string
	switch args[0] {
	case "bootstrap":
		target = strings.TrimSpace(*name)
	case "invite":
		target = strings.TrimSpace(*user)
	default:
		fmt.Fprintf(stderr, "unknown admin command %q\n", args[0])
		return 2
	}
	if target == "" {
		fmt.Fprintln(stderr, "usage: relay admin", args[0], map[string]string{"bootstrap": "--name X", "invite": "--user X"}[args[0]])
		return 2
	}
	st, err := store.Open(envOr(getenv, "RELAY_DATA_DIR", defaultDataDir))
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	defer func() { _ = st.Close() }()
	srv := api.New(api.Options{Store: st, Logger: slog.New(slog.NewJSONHandler(io.Discard, nil))})

	var inv store.Invite
	if args[0] == "bootstrap" {
		users, err := st.ListUsers(ctx)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if len(users) > 0 {
			fmt.Fprintln(stderr, "bootstrap: server already has users; use `relay admin invite --user X`")
			return 1
		}
		u, err := st.CreateUser(ctx, target, store.RoleAdmin)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		inv, err = srv.IssueInvite(ctx, "", u.ID)
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
	} else {
		inv, err = srv.IssueInvite(ctx, target, "")
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
	}
	fmt.Fprintf(stdout, "invite for %s (%s): %s  (expires %s)\n", target, inv.UserID, inv.Code, inv.ExpiresAt.Format(time.RFC3339))
	return 0
}

func serve(ctx context.Context, getenv func(string) string, stdout, stderr io.Writer, ready chan<- string) int {
	log := slog.New(slog.NewJSONHandler(stdout, nil))
	slog.SetDefault(log)
	addr := envOr(getenv, "RELAY_ADDR", defaultAddr)
	dataDir := envOr(getenv, "RELAY_DATA_DIR", defaultDataDir)

	st, err := store.Open(dataDir)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	defer func() { _ = st.Close() }()

	pusher, err := push.FromEnv(ctx, getenv("FCM_SERVICE_ACCOUNT_B64"), push.Options{Logger: log})
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	hub := ws.NewHub(st, ws.Options{Logger: log})
	apiSrv := api.New(api.Options{Store: st, Notifier: hub, Pusher: pusher, WS: hub, Logger: log})

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Fprintln(stderr, "listen:", err)
		return 1
	}
	httpSrv := &http.Server{
		Handler:           apiSrv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       2 * time.Minute,
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelWarn),
	}

	jctx, stopJanitor := context.WithCancel(ctx)
	defer stopJanitor()
	go janitor.New(st, janitor.Options{Logger: log}).Run(jctx)

	log.Info("relay listening", "addr", ln.Addr().String(), "data_dir", dataDir, "push", pusher != nil)
	if ready != nil {
		ready <- ln.Addr().String()
	}
	errc := make(chan error, 1)
	go func() { errc <- httpSrv.Serve(ln) }()

	select {
	case err := <-errc:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			fmt.Fprintln(stderr, "serve:", err)
			return 1
		}
	case <-ctx.Done():
	}
	log.Info("shutting down")
	hub.Close()
	sctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := httpSrv.Shutdown(sctx); err != nil {
		log.Warn("shutdown", "err", err)
		_ = httpSrv.Close()
	}
	log.Info("bye")
	return 0
}
