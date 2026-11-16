# 03: `asb-proxy serve` — unix-socket listener and child supervision

**What to build:** `asb-proxy serve`, which binds the unix socket, runs the
reverse proxy, and optionally supervises a child (the bwrap invocation) so its
lifetime matches the sandbox's.

**Blocked by:** none

**Status:** ready-for-agent
**Implementation:** done — `proxy/serve.go`, `proxy/serve_test.go`

## Scope

- `serve --config <file> [--socket <path>] [-- <child argv...>]`.
- Bind the unix socket at the resolved path (`--socket`, or a value from the
  config), with mode `0600`, removing a stale file first.
- With a child: fork/exec it, forward termination signals, wait, then remove the
  socket and exit with the child's status. Without a child: run until killed.
  Either way the listener must come up before the child starts, and be gone
  after it exits.
- On Linux, an abstract socket cannot cross a mount namespace, so the socket is
  always a filesystem path.

## Acceptance criteria

- [ ] `serve` with a config answers a request over the unix socket.
- [ ] With a child, the socket exists before the child is started and is removed
      after the child exits.
- [ ] The process exits with the child's exit status; a termination signal kills
      the child.
- [ ] Socket permissions are `0600`.

## Notes

- D2 is settled: `asb` builds the complete bwrap argv, and `serve` only owns the
  socket and the child's lifetime (invoked as `asb-proxy serve --config <file>
  --socket <path> -- <bwrap argv>`). See spec.md.
- This is the M1 entry point: it must forward and inject with no sandbox at all,
  which is the whole v1 goal.
