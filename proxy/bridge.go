package main

import (
	"context"
	"flag"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"sync"
	"syscall"
)

// runBridge implements `asb-proxy bridge`.
func runBridge(args []string, logger *log.Logger) int {
	flags, child := splitChild(args)

	fs := flag.NewFlagSet("bridge", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	socketPath := fs.String("socket", "", "unix socket to forward to (required)")
	listenAddr := fs.String("listen", "", "TCP address to listen on (required)")
	if err := fs.Parse(flags); err != nil {
		return 2
	}
	if *socketPath == "" {
		logf(logger, "bridge: --socket is required")
		return 2
	}
	if *listenAddr == "" {
		logf(logger, "bridge: --listen is required")
		return 2
	}

	if len(child) == 0 {
		ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
		defer stop()
		if err := serveBridge(ctx, *listenAddr, *socketPath); err != nil {
			logf(logger, "bridge: %v", err)
			return 1
		}
		return 0
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	l, err := net.Listen("tcp", *listenAddr)
	if err != nil {
		logf(logger, "bridge: %v", err)
		return 1
	}
	done := make(chan struct{})
	go func() {
		_ = forward(ctx, l, *socketPath)
		close(done)
	}()

	cmd := exec.Command(child[0], child[1:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err = cmd.Run()

	cancel()
	<-done
	return exitCode(err)
}

// serveBridge listens on a TCP address and forwards to the unix socket.
func serveBridge(ctx context.Context, listenAddr, socketPath string) error {
	l, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return err
	}
	return forward(ctx, l, socketPath)
}

// forward accepts TCP connections on l and pipes each to the unix socket until
// ctx is cancelled. It is transport only: it never inspects the bytes, so it
// stays transparent to a future CONNECT tunnel.
func forward(ctx context.Context, l net.Listener, socketPath string) error {
	var wg sync.WaitGroup
	defer wg.Wait()

	stop := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			_ = l.Close()
		case <-stop:
		}
	}()
	defer close(stop)

	for {
		conn, err := l.Accept()
		if err != nil {
			return nil
		}
		wg.Add(1)
		go func(c net.Conn) {
			defer wg.Done()
			bridgeConn(c, socketPath)
		}(conn)
	}
}

func bridgeConn(client net.Conn, socketPath string) {
	defer client.Close()

	upstream, err := net.Dial("unix", socketPath)
	if err != nil {
		return
	}
	defer upstream.Close()

	done := make(chan struct{}, 2)
	go func() { _, _ = io.Copy(upstream, client); done <- struct{}{} }()
	go func() { _, _ = io.Copy(client, upstream); done <- struct{}{} }()
	<-done
}
