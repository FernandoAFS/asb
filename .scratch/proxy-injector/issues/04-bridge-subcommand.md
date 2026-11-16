# 04: `asb-proxy bridge` — forward a loopback port to the unix socket

**What to build:** `asb-proxy bridge`, a tiny in-Sandbox helper that listens on a
loopback TCP address and forwards every connection to the Proxy's unix socket,
so clients that cannot dial a unix socket (PiG, kit) can reach the Proxy. It
replaces the external `socat` dependency.

**Blocked by:** none

**Status:** ready-for-agent
**Implementation:** done — `proxy/bridge.go`, `proxy/bridge_test.go`

## Scope

- `bridge --socket <path> --listen <host:port> [-- <child argv...>]`.
- Accept TCP, dial the unix socket, copy bytes both ways.
- With a child: run it and exit when it exits (the Bridge is the Sandbox payload
  wrapper). Without: forward until killed. Forward termination signals.
- No HTTP awareness: it must be transparent to `CONNECT` tunnels later, so it
  only moves bytes.

## Acceptance criteria

- [ ] A TCP client reaches an upstream through `bridge` → unix socket → Proxy.
- [ ] With a child, `bridge` outlives the child's listener needs and exits with
      the child's status.
- [ ] Bidirectional copy handles a connection opened before the socket is ready
      (retry/connect-after-listen ordering).

## Notes

- Verified: `bwrap --unshare-net` leaves `lo` `UP` with `127.0.0.1/8`, so a
  loopback listener works without extra setup.
- The Bridge is a transport shim, not a security boundary: it is needed because
  the Sandbox uses a unix socket and clients like PiG/kit only dial TCP. It is
  netns-agnostic, so the future `--unshare-net` opt-in (issue 06) is additive.
- Alternatives considered: depend on `socat` (rejected — an extra host
  dependency and not installed here), or a host loopback TCP listener with no
  socket (rejected — occupies a host port and gives up the socket design).
