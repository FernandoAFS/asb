# 02: Reverse-proxy core — routing, rewrite, injection, streaming

**What to build:** The request path of `serve`: longest-prefix route matching,
path rewrite, method/body/header forwarding, header and query injection with
replacement semantics, and unbuffered streaming responses.

**Blocked by:** 01

**Status:** ready-for-agent
**Implementation:** done — `proxy/proxy.go`, `proxy/proxy_test.go`

## Scope

- Longest-prefix match (`path == prefix` or `path` begins with `prefix + "/"`);
  unmatched → `404`.
- Strip `prefix` when configured, join to the upstream path, forward the query
  string; an injected query parameter replaces one of the same name.
- Forward method and body unchanged. An injected header replaces an inbound
  header of the same name; do not forward `Host` or hop-by-hop headers.
- Stream the response without buffering so SSE and chunked bodies pass through.
- No response-body transformation.
- Verify the upstream certificate normally; no interception, no proxy CA.
- `502` on upstream error, `504` on dial timeout; the credential never appears in
  an error body or a log line.

## Acceptance criteria

- [ ] Each route forwards to its upstream and returns the upstream response.
- [ ] Longest prefix wins; an unmatched path is `404`.
- [ ] A configured header arrives at the upstream; an inbound header of the same
      name does not shadow it.
- [ ] A configured query parameter arrives at the upstream.
- [ ] `strip_prefix` true and false both produce the expected upstream path.
- [ ] An SSE response streams without buffering (asserted by chunk timing or a
      streaming reader, not by a full read).
- [ ] `502`/`504` mappings are covered.

## Notes

- `net/http/httputil.ReverseProxy` is the natural base; confirm its streaming and
  flush behaviour for SSE before relying on it.
