package main

import (
	"context"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func unixClient(socketPath string) *http.Client {
	return &http.Client{
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				return (&net.Dialer{}).DialContext(ctx, "unix", socketPath)
			},
		},
	}
}

func TestServeOverUnixSocket(t *testing.T) {
	h, err := newProxyHandler(&Config{Routes: []Route{
		{Name: "a", Prefix: "/a", Upstream: "https://x.example.com"},
	}}, nil)
	if err != nil {
		t.Fatal(err)
	}
	socketPath := filepath.Join(t.TempDir(), "proxy.sock")

	ctx, cancel := context.WithCancel(context.Background())
	errCh := make(chan error, 1)
	go func() { errCh <- serve(ctx, socketPath, h, nil) }()

	waitFor(t, "socket", func() bool { _, err := os.Stat(socketPath); return err == nil })

	// An unmatched path proves the unix socket reaches the handler without
	// needing a reachable upstream.
	resp, err := unixClient(socketPath).Get("http://unix/nope")
	if err != nil {
		t.Fatalf("request over unix socket: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}

	fi, err := os.Stat(socketPath)
	if err != nil {
		t.Fatal(err)
	}
	if fi.Mode().Perm() != 0o600 {
		t.Fatalf("socket mode = %v, want 0600", fi.Mode().Perm())
	}

	cancel()
	if err := <-errCh; err != nil {
		t.Fatalf("serve returned %v", err)
	}
	if _, err := os.Stat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("socket was not removed: %v", err)
	}
}

func TestRunServeReturnsChildExitCode(t *testing.T) {
	cfgPath := writeConfig(t, `{"routes":[{"name":"a","prefix":"/a","upstream":"https://x.example.com"}]}`)
	socketPath := filepath.Join(t.TempDir(), "proxy.sock")

	code := runServe([]string{"--config", cfgPath, "--socket", socketPath, "--", "sh", "-c", "exit 3"}, nil)
	if code != 3 {
		t.Fatalf("exit code = %d, want 3", code)
	}
	if _, err := os.Stat(socketPath); !os.IsNotExist(err) {
		t.Fatalf("socket was not removed: %v", err)
	}
}

func TestRunServeRequiresSocket(t *testing.T) {
	cfgPath := writeConfig(t, `{"routes":[]}`)
	if code := runServe([]string{"--config", cfgPath}, nil); code != 2 {
		t.Fatalf("exit code = %d, want 2", code)
	}
}

// superviseChild is driven with a plain signal channel: no signal is sent to
// the test process.
func TestSuperviseChildReturnsChildExitCode(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	serveErr := make(chan error, 1)
	go func() { <-ctx.Done(); serveErr <- nil }()

	child := exec.Command("sh", "-c", "exit 5")
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}

	if code := superviseChild(cancel, child, serveErr, make(chan os.Signal)); code != 5 {
		t.Fatalf("exit code = %d, want 5", code)
	}
}

func TestSuperviseChildForwardsSignal(t *testing.T) {
	dir := t.TempDir()
	ready := filepath.Join(dir, "ready")
	sigFile := filepath.Join(dir, "signal")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	serveErr := make(chan error, 1)
	go func() { <-ctx.Done(); serveErr <- nil }()

	// Trap SIGTERM, record which signal arrived, and exit with a distinct code.
	child := exec.Command("sh", "-c",
		`trap 'echo TERM > "$SIGFILE"; exit 9' TERM; echo ready > "$READY"; while :; do sleep 0.02; done`)
	child.Env = append(os.Environ(), "READY="+ready, "SIGFILE="+sigFile)
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = child.Process.Kill() })

	waitFor(t, "child ready", func() bool { _, err := os.Stat(ready); return err == nil })

	signals := make(chan os.Signal, 1)
	result := make(chan int, 1)
	go func() { result <- superviseChild(cancel, child, serveErr, signals) }()
	signals <- syscall.SIGTERM

	select {
	case code := <-result:
		if code != 9 {
			t.Fatalf("exit code = %d, want 9", code)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("superviseChild did not return after the signal")
	}

	recorded, err := os.ReadFile(sigFile)
	if err != nil {
		t.Fatalf("child did not record a signal: %v", err)
	}
	if got := strings.TrimSpace(string(recorded)); got != "TERM" {
		t.Fatalf("child recorded %q, want TERM", got)
	}
}
