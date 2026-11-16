# 05: asb integration — `--proxy-config`, plan record, socket bind, payload wrap

**What to build:** The optional `--proxy-config <file>` option in `asb`, which
turns a run into a proxied run: resolve and mount `asb-proxy`, allocate a private
socket directory, bind the socket into the Sandbox, set the proxy environment,
wrap the payload with `bridge`, and show all of it in `--dry-run`.

**Blocked by:** 01, 02, 03, 04

**Status:** ready-for-agent

## Scope

- Resolve `asb-proxy` the way the agent binary is resolved; mount its directory
  read-only (PATH binding may already cover it).
- Allocate a per-run host directory for the socket; pass it to
  `asb-proxy serve` as the supervisor, with the bwrap argv as its child.
- Append to the bwrap argv: a read-only bind of the socket, `ASB_PROXY_SOCKET`,
  `ASB_PROXY_PORT`, and the `bridge` payload wrapper. It must work for both an
  agent launch and `--shell`.
- Do **not** add `--unshare-net` (Decision D1): egress is unchanged in v1.
- A new `proxy <config> <socket>` line in the Plan.
- Without `--proxy-config`, the plan is byte-for-byte what it is today.

## Acceptance criteria

- [ ] `asb --proxy-config cfg.json <agent> <dir> --dry-run` prints the `proxy`
      record, the socket bind, and the wrapped payload.
- [ ] Omitting `--proxy-config` leaves the plan unchanged (regression-tested).
- [ ] `--shell` with `--proxy-config` gets the same wiring.
- [ ] `--dry-run` starts no proxy and creates no socket.
- [ ] A missing `asb-proxy` fails with a clear message before any side effect.

## Notes

- D2 is settled: `asb` assembles the full bwrap argv and execs `asb-proxy serve
  --config <file> --socket <path> -- <bwrap argv>` for socket + child lifetime.
- D3 is settled: `--proxy-config` overrides the XDG default resolved by `serve`.
