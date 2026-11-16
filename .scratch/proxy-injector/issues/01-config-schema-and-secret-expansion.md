# 01: Proxy configuration schema, JSON loader, and secret expansion

**What to build:** The JSON configuration the Proxy reads, its Go structs, a
loader with validation, and `${VAR}` expansion of injection values from the host
environment.

**Blocked by:** none

**Status:** ready-for-agent
**Implementation:** done — `proxy/config.go`, `proxy/config_test.go`

## Scope

- Resolve the configuration path: `--config <file>`, else
  `$XDG_CONFIG_HOME/asb/proxy.json`, else `~/.config/asb/proxy.json` (Decision
  D3).
- Parse the schema in `spec.md` (`routes[]` with `name`, `prefix`, `upstream`,
  `strip_prefix`, `inject[]`; injection `in`/`name`/`value`).
- Validate: unique non-empty `name`, non-empty `prefix` starting with `/`,
  `upstream` an absolute `http`/`https` URL, `in` one of `header`/`query`, a
  known `strip_prefix`.
- Expand `${VAR}` in `value` from the process environment. An unset variable is
  a startup error naming the variable — never an empty secret.
- JSON only. No comments, no environment-specific overlays.

## Acceptance criteria

- [ ] A valid config loads and round-trips its routes.
- [ ] An unset `${VAR}` fails startup with the variable named.
- [ ] Each validation error is specific and non-fatal to the rest of the checks
      where practical.
- [ ] Unit tests cover each validation rule and the expansion.

## Notes

- `encoding/json` only; no third-party dependency.
- `!command` expansion (as in PiG's `mcp.json`) is deliberately deferred.
