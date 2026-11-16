# 06: Forward-proxy `CONNECT` and egress allowlist (later)

**What to build:** A forward-proxy mode on the same listener so that, under
`--unshare-net`, non-injected egress can traverse the Proxy against an allowlist,
with loopback/private/link-local/metadata refused at dial time.

**Blocked by:** none (M3; not until v1 lands)

**Status:** needs-info

## Scope

- Handle `CONNECT host:port` and absolute-form HTTP requests, distinct from the
  origin-form reverse-proxy Routes.
- Allowlist hosts; refuse loopback, private, link-local, and `169.254.169.254`
  regardless of the list.
- Decide the default posture (deny-by-default vs allowed-unless-listed) and the
  `--shell` policy.
- Reuse the same unix socket and Bridge.

## Notes

- This is the other half of `.scratch/kwt/issues/10-network-egress.md`; that
  ticket should be reduced to this scope.
- Deliberately not in v1: it changes the sandbox's network posture and is more
  than credential injection.
