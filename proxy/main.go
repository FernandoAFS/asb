// asb-proxy — a host-side reverse proxy that injects credentials for a
// sandboxed agent run.
//
// The credential stays on the host. A per-run Proxy listens on a unix socket
// that is bound into the Sandbox, forwards configured path prefixes to external
// upstreams, and adds headers or query parameters the agent never sees. The
// `bridge` subcommand is the in-Sandbox shim that forwards a loopback TCP port
// to that socket, for clients that can only dial TCP.
package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	logger := log.New(os.Stderr, "asb-proxy: ", 0)

	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	switch os.Args[1] {
	case "serve":
		os.Exit(runServe(os.Args[2:], logger))
	case "bridge":
		os.Exit(runBridge(os.Args[2:], logger))
	case "-h", "--help", "help":
		usage()
		os.Exit(0)
	default:
		fmt.Fprintf(os.Stderr, "asb-proxy: unknown command %q\n", os.Args[1])
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `usage:
  asb-proxy serve  [--config <file>] --socket <path> [-- <child argv...>]
  asb-proxy bridge --socket <path> --listen <host:port> [-- <child argv...>]

serve:
  Bind a unix socket and reverse-proxy configured routes, injecting the
  credentials named in the configuration. With a child, run it and exit when it
  exits. The configuration path defaults to $XDG_CONFIG_HOME/asb/proxy.json.

bridge:
  Forward a loopback TCP address to the Proxy's unix socket. With a child, run
  it and exit when it exits. TCP is only a shim for clients that cannot dial a
  unix socket.
`)
}
