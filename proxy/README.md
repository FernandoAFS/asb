# asb-proxy

A host-side reverse proxy that injects credentials for a sandboxed agent run.

A sandboxed agent needs credentials — an LLM provider key, remote MCP tokens —
to work. Mounting them into the Sandbox read-only stops the agent *writing* them
but does nothing to stop it *reading* them. `asb-proxy` keeps the credential on
the host and adds it to the outgoing request, so the agent authenticates without
ever holding the token.

This is the credential-injection half of `asb`. Egress filtering is a separate,
later concern; the network namespace is not unshared here.

See [`docs/specs/proxy-injector.md`](../docs/specs/proxy-injector.md) for the full design.

## How it works

The agent's base URL is rewritten to the Proxy, so the request arrives as plain
HTTP on a local hop. The Proxy adds the configured credential and opens the real
TLS connection upstream. There is no TLS interception and no proxy CA: the
credential is injected only on the plaintext, local hop.

```
agent ──HTTP──▶ bridge ──unix socket──▶ asb-proxy serve ──HTTPS──▶ upstream
        (in Sandbox)                    (on host, holds the token)
```

- **`serve`** is the Proxy. It runs on the host, binds a unix socket, and
  reverse-proxies configured path prefixes to external upstreams. It is never
  inside the Sandbox.
- **`bridge`** runs inside the Sandbox and forwards a loopback TCP port to that
  socket, for clients (PiG, kit) that can only dial TCP. It is transport only —
  it never inspects the bytes.

`serve` can also run a child and exit when the child exits, so `asb` hands it the
`bwrap` invocation and the Proxy's lifetime matches the sandbox's.

## Build and test

```sh
make proxy        # build proxy/asb-proxy
make test         # the shell suite plus `go test ./...`
```

From this directory:

```sh
go build -o asb-proxy .
go test ./...
```

The module is standard-library only.

## Usage

```
asb-proxy serve  [--config <file>] --socket <path> [-- <child argv...>]
asb-proxy bridge --socket <path> --listen <host:port> [-- <child argv...>]
```

`--socket` is required for both. `serve`'s configuration path resolves as
`--config`, then `$XDG_CONFIG_HOME/asb/proxy.json`, then
`~/.config/asb/proxy.json`; a missing file is a startup error.

## Configuration

One JSON file, read by `serve` on the host and never mounted into the Sandbox.

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

- A Route matches by longest `prefix`; `strip_prefix` removes it before
  forwarding.
- `inject[].in` is `header` or `query`. An injected value **replaces** any
  inbound value of the same name, so the agent cannot shadow or observe it.
- `value` is expanded from the **host** environment with `${VAR}`. An unset
  variable is a startup error, never an empty secret.
- Responses stream without buffering, so SSE and streamable-HTTP MCP pass
  through.
- An unmatched path is `404`; an upstream failure is `502`; a dial timeout is
  `504`. A credential never appears in an error body or a log line.

## Layout

| File | Contents |
|---|---|
| `main.go` | subcommand dispatch and usage |
| `config.go` | schema, validation, XDG path resolution, `${VAR}` expansion |
| `proxy.go` | routing, rewrite, injection, streaming |
| `serve.go` | unix socket, child supervision |
| `bridge.go` | TCP-to-unix forwarding |

## Out of scope

- Egress filtering and `CONNECT` (`--unshare-net`).
- TLS interception and a proxy CA.
- STDIO MCP servers.
- Secret storage or rotation; only host environment variables are read.
- Deriving proxy configuration from an agent's own configuration — the operator
  writes it by hand for now.
