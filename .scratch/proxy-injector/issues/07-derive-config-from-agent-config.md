# 07: Derive proxy routes and agent base URLs from agent configuration (later)

**What to build:** Given an agent's standard configuration (pig `models.json` /
`mcp.json`, kit's configuration), generate the proxy configuration *and* the
agent configuration that points at the Proxy — so the operator does not write
both by hand.

**Blocked by:** 01, 02

**Status:** needs-info

## Scope

- Turn each remote MCP server entry into a Route and rewrite its `url` / headers
  to the local proxy prefix with no token.
- Turn the LLM provider base URL into a Route and rewrite the provider's
  `baseUrl` to the local prefix.
- Produce either a per-Target file (`.asb/proxy.json` and an agent config
  overlay) or streamed configuration, TBD.
- Respect the agent's own secret-resolution grammar (`${VAR}`, `!command`) where
  it exists, without inventing a second one.

## Notes

- The Proxy configuration in issue 01 is the stable interface; this issue is an
  adapter onto it.
- Out of scope for v1: v1 is configured by hand.
