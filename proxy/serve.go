package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
)

// runServe implements `asb-proxy serve`.
func runServe(args []string, logger *log.Logger) int {
	flags, child := splitChild(args)

	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	configFlag := fs.String("config", "", "path to the proxy configuration file")
	socketPath := fs.String("socket", "", "unix socket to listen on (required)")
	if err := fs.Parse(flags); err != nil {
		return 2
	}
	if *socketPath == "" {
		logf(logger, "serve: --socket is required")
		return 2
	}

	cfg, err := LoadConfig(ResolveConfigPath(*configFlag))
	if err != nil {
		logf(logger, "serve: %v", err)
		return 1
	}
	handler, err := newProxyHandler(cfg, logger)
	if err != nil {
		logf(logger, "serve: %v", err)
		return 1
	}

	if len(child) == 0 {
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer stop()
		if err := serve(ctx, *socketPath, handler, logger); err != nil {
			logf(logger, "serve: %v", err)
			return 1
		}
		return 0
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cmd := exec.Command(child[0], child[1:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		logf(logger, "serve: start child: %v", err)
		return 1
	}

	serveErr := make(chan error, 1)
	go func() { serveErr <- serve(ctx, *socketPath, handler, logger) }()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(sig)

	return superviseChild(cancel, cmd, serveErr, sig)
}

// superviseChild waits for the started child to exit or for a signal to arrive.
// A signal is forwarded to the child unchanged; either way it then cancels the
// server and waits for it to stop before returning the child's exit code. Taking
// the signal channel as an argument keeps the policy testable without sending
// real signals to the process.
func superviseChild(cancel context.CancelFunc, child *exec.Cmd, serveErr <-chan error, signals <-chan os.Signal) int {
	childErr := make(chan error, 1)
	go func() { childErr <- child.Wait() }()

	select {
	case err := <-childErr:
		cancel()
		<-serveErr
		return exitCode(err)
	case s := <-signals:
		_ = child.Process.Signal(s)
		err := <-childErr
		cancel()
		<-serveErr
		return exitCode(err)
	}
}

// serve binds the unix socket and serves until ctx is cancelled, removing the
// socket on the way out. It is the lifecycle seam unit tests drive directly.
func serve(ctx context.Context, socketPath string, handler http.Handler, logger *log.Logger) error {
	// Remove a stale socket so a crashed run does not block the next one.
	_ = os.Remove(socketPath)

	l, err := net.Listen("unix", socketPath)
	if err != nil {
		return err
	}
	if err := os.Chmod(socketPath, 0o600); err != nil {
		_ = l.Close()
		_ = os.Remove(socketPath)
		return err
	}

	srv := &http.Server{Handler: handler}
	go func() {
		<-ctx.Done()
		_ = srv.Close()
	}()

	err = srv.Serve(l)
	_ = os.Remove(socketPath)
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

// splitChild splits args at the first `--`: flags before, child argv after.
func splitChild(args []string) (flags, child []string) {
	for i, a := range args {
		if a == "--" {
			return args[:i], args[i+1:]
		}
	}
	return args, nil
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return ee.ExitCode()
	}
	return 1
}

func logf(logger *log.Logger, format string, args ...any) {
	if logger != nil {
		logger.Printf(format, args...)
	}
}
