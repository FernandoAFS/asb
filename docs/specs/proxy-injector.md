# Spec: `asb-proxy` — host-side credential injection for asb

Feature: `asb-proxy`  
Date: 2026-11-15

## Problem Statement

A sandboxed agent needs credentials — an LLM provider key, remote MCP tokens —
to do its work. Today those secrets are mounted read-only into the Sandbox
(`$XDG_CONFIG_HOME/.kit`, the pig configuration overlay), which stops the agent
*writing* them but does nothing to stop it *reading* them. A prompt injection or
a mistake can read every token and post it anywhere reachable.

`asb` should let an agent authenticate without ever holding the token: the
credential stays on the host, and a host-side proxy injects it on the way out.

For v1 the goal is narrow: **hide the credentials**, and prove the proxy can
forward requests and inject them. Egress filtering is not part of v1 (see
Decisions and Non-goals), though the wiring is designed so it can land later.

## Solution

A per-run `asb-proxy` process on the host. It reads a JSON configuration mapping
local path prefixes to external upstreams and, for each, injects credentials as
HTTP headers or query parameters. It is a **reverse proxy**: the agent's base URL
is rewritten to the proxy, the proxy adds the secret, and it opens the real TLS
connection upstream. No CA and no TLS interception are involved, because the
credential-injection hop is plaintext and local.

The credential is absent from the Sandbox; that absence — not the network — is
the security property in v1.

The proxy listens on a **unix socket** on the host. That socket is bound into the
Sandbox, so the secret-holding process is outside the Sandbox and only a socket
file crosses the boundary. A `bridge` subcommand, run inside the Sandbox,
forwards a loopback TCP port to the unix socket so clients that only speak TCP
(PiG, kit) can reach it. `asb` owns the whole bwrap argv; `asb-proxy serve` owns
the listener and, in supervisor mode, the sandbox child's lifetime.

## Command surface

```
asb-proxy serve [--config <file>] [--socket <path>] [-- <child argv...>]
asb-proxy bridge --socket <path> --listen <host:port> [-- <child argv...>]
```

- **`serve`** binds the unix socket, starts the reverse proxy, and runs until
  killed. With `-- <child argv...>` it also forks the child (the `bwrap`
  invocation) and exits when the child exits, cleaning up the socket. This is the
  supervisor `asb` execs. Without a child it is a plain foreground server, which
  is the unit-test entry point. The configuration path resolves as Open Question
  D3 describes.
- **`bridge`** listens on a loopback TCP address and forwards every connection to
  the unix socket. With `-- <child argv...>` it also runs the agent and exits
  when the agent exits, so it can be the Sandbox payload wrapper; without it, it
  forwards until killed. TCP is only a shim for clients that cannot dial a unix
  socket.

## Language

Additions to `CONTEXT.md`'s vocabulary, used consistently in this spec.

**Proxy**:
The host-side `asb-proxy serve` process for one asb run. It holds the credentials
and is never inside the Sandbox.
_Avoid_: relay, gateway, sidecar.

**Upstream**:
An external origin the Proxy forwards to, such as `https://api.openai.com` or a
remote MCP server. The Proxy is its client.
_Avoid_: backend, target server.

**Route**:
A configured mapping from a local path prefix (e.g. `/openai`) to one Upstream,
with the credentials to inject. Longest prefix wins.
_Avoid_: endpoint, path rule.

**Injection**:
One credential a Route adds to a forwarded request, as a header or a query
parameter. The value is a template expanded from the host environment.
_Avoid_: token, secret (the *value* is a secret; the act is injection).

**Bridge**:
The `asb-proxy bridge` helper inside the Sandbox that forwards a loopback TCP
port to the Proxy's unix socket.

## Configuration

One JSON file, read by `serve` on the host and **never mounted into the
Sandbox**. JSON because the binary is Go: `encoding/json` is stdlib and a
small tool should not take a YAML or TOML dependency. Comments are not
supported; that is accepted.

The path resolves, in order: `--config <file>`; then
`$XDG_CONFIG_HOME/asb/proxy.json`; then `~/.config/asb/proxy.json`. The file is
required: a missing or unreadable configuration is a startup error. JSON only,
no per-project overlay in v1.

```json
{
  "routes": [
    {
      "name": "openai",
      "prefix": "/openai",
      "upstream": "https://api.openai.com",
      "strip_prefix": true,
      "inject": [
        { "in": "header", "name": "Authorization", "value": "Bearer ${OPENAI_API_KEY}" }
      ]
    },
    {
      "name": "github",
      "prefix": "/github",
      "upstream": "https://api.github.com",
      "inject": [
        { "in": "header", "name": "Authorization", "value": "Bearer ${GITHUB_TOKEN}" }
      ]
    },
    {
      "name": "search-mcp",
      "prefix": "/search",
      "upstream": "https://mcp.example.com",
      "inject": [
        { "in": "query", "name": "api_key", "value": "${SEARCH_TOKEN}" }
      ]
    }
  ]
}
```

- `inject[].in` is `header` or `query`. A Route may carry several injections.
- `value` is expanded at load from the **host** environment with `${VAR}`.
  An unset variable is an error at startup, not an empty secret. (`!command`
  expansion, as PiG's `mcp.json` supports, is deliberately deferred.)
  Only the braced `${VAR}` form is expanded; a bare `$` is left alone.
- `strip_prefix` decides whether the local prefix is removed before forwarding.

## Proxy behaviour

- **Routing.** Match by longest `prefix`; a route matches when the path equals
  the prefix or begins with `prefix + "/"`. Unmatched paths get `404`.
- **Rewrite.** Strip the prefix when configured, then join with the upstream
  path. The query string is forwarded; an injected query parameter replaces one
  of the same name.
- **Request.** Forward method, body, and headers. An injected header replaces an
  inbound header of the same name (the Sandbox cannot shadow or observe it);
  `Host` and hop-by-hop headers are not forwarded. No request-body rewriting.
- **Response.** Streamed without buffering. SSE and chunked responses must pass
  through unmodified — OpenAI-style APIs and streamable-HTTP MCP both stream.
  No response-body transformation.
- **TLS.** The Proxy verifies the upstream certificate normally. No interception
  and no proxy CA.
- **Failures.** `502` for an upstream error, `504` for a dial timeout. The real
  credential never appears in an error body or log line.

## Sandbox integration

Only when a proxy configuration is supplied; the proxy is an optional complement
to asb. Without it, `asb` behaves exactly as today.

- A new option, `--proxy-config <file>`, enables it and overrides the XDG
  default resolved by `serve`. (`asb-proxy` must be on `PATH`; `asb` resolves and
  mounts it the way it resolves the agent binary.)
- `asb` allocates a private host directory under `/tmp` for the run's socket, and
  passes the configuration to `asb-proxy serve` as its child supervisor.
- The bwrap argv gains:
  - a read-only bind of the socket file to a fixed in-Sandbox path,
  - `ASB_PROXY_SOCKET` (that path) and `ASB_PROXY_PORT`,
  - the payload wrapped as `asb-proxy bridge --socket … --listen 127.0.0.1:… --
    <agent argv>` instead of the agent directly.
- **`--unshare-net` is not added in v1** (Decision D1). The Sandbox keeps the
  host network namespace, so the Proxy is not an egress boundary; it exists to
  keep the credentials out of the Sandbox. The socket and Bridge are
  netns-agnostic and stay so that an opt-in `--unshare-net` is additive.
- `--dry-run` prints all of this — including a `proxy <config> <socket>` plan
  record — and starts nothing. This remains the primary test seam.

## Non-goals

- **Egress filtering.** Default-deny egress and a forward-proxy `CONNECT`
  allowlist are a separate, later step (issue 06). No `--unshare-net` in v1.
- **TLS interception.** No proxy CA is generated or distributed; credentials are
  injected only on Routes whose local hop is plaintext.
- **STDIO MCP servers.** No stdin/stdout interception.
- **Secret management.** Reading host environment variables is in scope;
  creating, rotating, storing, or prompting for secrets is not.
- **Deriving configuration from agent config.** Translating an agent's own
  provider/MCP configuration into proxy routes and agent base URLs is a later
  feature (issue 07). v1 is configured by hand.
- **OAuth token refresh.** Static injected credentials only in v1.

## Invariants

- The Proxy runs outside the Sandbox; no credential is present in the Sandbox,
  in its environment, or in any file it can read.
- The configuration file is host-side only and is never mounted.
- An injected header or parameter replaces any inbound value of the same name.
- An unset `${VAR}` fails at startup rather than injecting an empty secret.
- A proxy configuration is optional; without one the asb plan is unchanged.
- Network egress is unchanged from today: the Proxy is not an egress boundary.
- `--dry-run` performs no proxy side effects.

## Decisions

**D1 — Network namespace: not unshared in v1.** The point of v1 is to unshare the
*credentials*, not the network. The Sandbox keeps the host network namespace and
can reach the Proxy's loopback listener as it reaches anything else. A proxy
cannot be an egress boundary without `--unshare-net`, so egress filtering is
deferred to issue 06, and `--unshare-net` becomes an opt-in only when that
lands. The socket + Bridge are kept because they are netns-agnostic and make the
future move additive. Supersedes the earlier leaning toward unsharing in v1.

**D2 — Supervisor direction: asb owns the bwrap argv.** `asb` builds the
complete bwrap invocation, so sandbox policy stays in one place and `--dry-run`
stays honest. `asb-proxy serve` only binds the socket and owns the child's
lifetime; it never edits the argv or injects mounts. `serve` is exec'd as
`asb-proxy serve --config <file> --socket <path> -- <bwrap argv>`.

**D3 — Configuration location: XDG, flag overrides.** Default
`$XDG_CONFIG_HOME/asb/proxy.json`, falling back to `~/.config/asb/proxy.json`,
overridden by `--config <file>`. No per-Target file in v1; a `.asb/proxy.json`
default can come with the adapter (issue 07).

**D4 — Socket path: a private per-run directory under `/tmp`.** Resolved at run
time (e.g. `/tmp/asb-proxy.XXXX/proxy.sock`), bound into the Sandbox at a fixed
path, and removed by the supervisor on exit. A filesystem path is required; an
abstract socket cannot cross a mount namespace. The unit-test entry point
(`serve` with no child) can bind any path the caller names.

**D5 — Forward-proxy `CONNECT`: deferred.** Tracked by issue 06.

## Milestones

- **M1 — the proxy forwards and injects. DONE.** Issues 01–03: config loader,
  reverse proxy core, `serve` over the unix socket. Implemented in `proxy/` (Go
  module `asb-proxy`, binary `asb-proxy`) with `go test`. This is the whole of
  the v1 goal and is testable without a sandbox.
- **M2 — wire it into asb.** Issues 04–05: the `bridge` subcommand and the
  `--proxy-config` integration. The `bridge` subcommand is implemented; the asb
  `--proxy-config` wiring is not.
- **M3 — later.** Issues 06 (egress) and 07 (derive config from agent config).

## Testing Decisions

- The Proxy is a standalone Go binary, unit-tested against a `httptest` upstream
  and a unix-socket client: routing/rewrite, header and query injection,
  replacement of inbound values, streaming passthrough, `502`/`504`, and the
  unset-variable startup failure.
- `asb` remains black-box tested through `--dry-run`: adding `--proxy-config`
  must show the socket bind, the environment, the wrapped payload, and the
  `proxy` plan record — and start nothing.
- Integration testing stays light. There is no need to exercise a live PiG or kit
  session through the Proxy for v1.
