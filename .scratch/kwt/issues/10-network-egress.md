# 10: Network egress policy and remote-MCP credential injection

**What to build:** Give the Sandbox a network policy — default-deny egress against an allowlist — and put a host-side reverse proxy in front of the remote MCP servers a kit session talks to, so the real credentials never enter the Sandbox. This first version covers **remote MCP credentials only**: no TLS interception, no phantom tokens for local MCP servers, and no attempt to hide the LLM provider key.

**Blocked by:** 05 — Run the kit launch inside the bwrap sandbox

**Status:** needs-info — the approach is not chosen yet (see Decisions)

## Problem

Today the Sandbox has no network policy: `--unshare-net` is absent, so egress is unrestricted, and `$XDG_CONFIG_HOME/.kit` is bind-mounted read-only *into* the Sandbox because kit keeps provider credentials and MCP tokens there. Read-only stops the session writing secrets; it does nothing to stop the session reading them. A prompt injection, or a mistake, can read every MCP token and post it anywhere reachable.

Two independent problems are tangled here:

- **Egress** — which destinations a sandboxed process may reach at all.
- **Credential exposure** — whether the session can read the secrets it authenticates with.

They can be solved separately, and the second is the cheaper one.

## Scope (first version)

- Default-deny egress: only hosts on an allowlist are reachable.
- Remote-MCP credential injection: a kit session reaches a local reverse proxy, which adds the real `Authorization` header and forwards upstream. The session's MCP config holds no token.
- No TLS interception and therefore no proxy CA to distribute.
- No provider-key hiding and no local-MCP phantom tokens (see Open Questions).

## Non-goals

- TLS-intercepting any traffic (that is what hiding the provider key or a local MCP server's key would require).
- DNS-level filtering; the allowlist matches hostnames the client sends to the proxy.
- Per-host path or method policy (a natural follow-on, not this ticket).

## Decisions

These are the ADR-level choices. Each is open; D1 is the one blocking this ticket.

**D1 — How the proxy is provided.**
- *Build in kwt*: a second artifact (`kwt-proxy`, Go) or a dependency on `mitmproxy` plus an addon. Keeps kwt self-contained; adds a binary or a Python dependency to a project that is currently one bash script plus one Go kit extension.
- *Adopt [nono](https://nono.sh)*: it already does kernel-enforced sandboxing, allowlisted egress, and credential injection, and it is the closest existing product to kwt. But it subsumes kwt entirely, so this is a "replace kwt", not "extend kwt", decision.
- *Hybrid*: kwt stays the bwrap builder and delegates egress and injection to an external proxy it launches and bridges (nono's `nono proxy`, [chaperone](https://github.com/cloudblue/chaperone), or mitmproxy). Smallest change to kwt; ties kwt to a third-party runtime dependency.

**D2 — Default posture.** Whether network becomes deny-by-default (matching the filesystem's default-deny) or stays allowed unless an allowlist is given. Deny-by-default is the honest no-trust posture but is a breaking change for existing use.

**D3 — Where policy lives.** Flags only, or a per-project file (`.kwt.yml`). Network policy is naturally per-project — this Project needs `api.github.com`, another needs something else — which pushes toward a file. Note the current spec lists "a per-repository configuration file" as out of scope.

**D4 — `kwt shell`.** Whether it gets the same policy (a shell is a stronger exfiltration tool than a kit session) or a stricter one, e.g. no network at all.

## Mechanism, if D1 lands on build or hybrid

The only way for the proxy to be a boundary rather than a suggestion is for the Sandbox to be unable to route around it:

1. `bwrap --unshare-net` removes all egress. Unix domain sockets survive (they are filesystem objects), TCP does not.
2. The proxy listens on a Unix domain socket on the host; `--bind` mounts that socket into the Sandbox.
3. `socat TCP-LISTEN:3128,fork UNIX-CONNECT:<socket>` inside the Sandbox bridges `localhost:3128` to the host proxy. `socat` is on `PATH`, so `bind_path_tools` already mounts it read-only.
4. `HTTP_PROXY` / `HTTPS_PROXY` point at the bridge; the Sandbox never resolves DNS itself.

This is the design used by [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime) (the `srt` engine behind Claude Code sandboxing) — see its Linux network bridge — and it is the part worth copying rather than inventing.

With this in place:

- **Egress** is enforced by the proxy's allowlist on the destination of each `CONNECT` and `HTTP` request. Loopback, private, link-local, and `169.254.169.254` are refused at dial time regardless of the list.
- **Remote-MCP credentials** are injected by a local reverse proxy: kit's MCP config points at `http://localhost:<port>/<name>` with no token, and the proxy adds `Authorization` (or any configured header) before forwarding upstream over TLS. The plaintext hop is local, which is why no CA is involved. This is the [agentvisor](https://pypi.org/project/agentvisor/) shape, and [Moat](https://majorcontext.com/moat/concepts/proxy/) calls the same function "MCP relay".

Because `kwt` already emits one bwrap argv and mounts `PATH` directories, steps 1–3 are a small addition to `build_sandbox`; the new weight is the proxy process and its configuration.

## Conflicts to resolve

- **ADR-0001** records "Network is allowed" as part of the accepted policy. This ticket changes that decision; the ADR needs an amendment or a superseding ADR once D2 is settled.
- **`spec.md`** lists "Network proxying or egress filtering" and "a per-repository configuration file" as out of scope. Both reopen here, and its "Further Notes" already anticipates the proxy as the natural next feature.
- **`spec.md`** also lists "Secret management of any kind" as out of scope. Injecting credentials is arguably secret *routing*, not management — but the boundary should be stated explicitly, because it is the same `.kit` mount this ticket is trying to stop depending on.

## Acceptance criteria (draft, pending D1–D4)

- [ ] A sandboxed process cannot reach a host that is not on the allowlist.
- [ ] A sandboxed process cannot bypass the policy by ignoring `HTTP_PROXY`/`HTTPS_PROXY` (verified with `--noproxy '*'` and a raw socket).
- [ ] Loopback, private, link-local, and cloud-metadata addresses are refused even when allowlisted.
- [ ] A kit session talks to a remote MCP server through the proxy using an MCP config that contains no token.
- [ ] The real token is absent from the Sandbox: not in the MCP config, not in the environment, not readable from any mounted file.
- [ ] The policy appears in the dry-run Plan.
- [ ] `--dry-run` performs no proxy side effects.

## Open Questions

- **Provider key.** kit inside the Sandbox still needs an LLM provider key, and it lives in the same `.kit` mount. Hiding it with the current approach needs either kit to accept a base-URL override (then a reverse proxy, no CA) or TLS interception. Which of those is acceptable — and is hiding it in scope at all for v1?
- **Approval flow.** `kwt` sets `KIT_OPT_HEADLESS=true`, so "ask the user to approve a new host" cannot use the terminal. Is a static allowlist enough, or is a webhook approval backend wanted? (nono hits the same constraint and offers terminal/webhook/chain backends.)
- **Env-var allowlist.** Should the Sandbox also restrict which host environment variables reach the kit session? It is cheap and closes the same leak by another route, but it is a separate mechanism.
- **Audit.** Should every egress decision be logged, and if so where?

## Prior art worth reading

- [anthropic-experimental/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime) — bwrap/seatbelt sandbox with a Unix-socket network bridge and a domain-allowlist proxy. The closest match to kwt's sandbox layer.
- [nono](https://nono.sh) — the full product version of this ticket: allowlisted egress, proxy credential injection, keystore-backed secrets, env filtering, audit. The build-or-adopt benchmark.
- [Docker MCP Gateway](https://github.com/docker/mcp-gateway) — per-server scoped secrets and `--block-network`/`allowHosts`; container-based.
- [LangChain sandbox auth proxy](https://docs.langchain.com/langsmith/sandbox-auth-proxy) — a precise written spec for allow/deny semantics and SSRF guards, hosted.
- [cloudblue/chaperone](https://github.com/cloudblue/chaperone) — a single-binary Go egress proxy with allowlist and credential injection; a candidate for the proxy in a hybrid design.

## Comments

- **2026-11-15 — split.** Credential injection now has its own effort:
  `.scratch/proxy-injector/spec.md` (`asb-proxy`), covering the host-side
  reverse proxy and the unix-socket + `bridge` wiring. This ticket is reduced to
  its egress half: default-deny egress, a forward-proxy `CONNECT` allowlist, and
  the sandbox's `--unshare-net`. See `proxy-injector/issues/06`. D2 (default
  posture) and D4 (`--shell`) remain open here; D1 lands as "build in asb" and
  D3 is answered by the proxy configuration file.
