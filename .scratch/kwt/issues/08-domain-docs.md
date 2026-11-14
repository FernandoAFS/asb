# 08: Record the domain — `CONTEXT.md` and the sandbox-policy ADR

**What to build:** The repo records its domain language and its hardest decision: a root `CONTEXT.md` glossary covering Target directory, Sandbox, kit session, and Project; and an ADR capturing the sandbox policy — one writable directory, shared state read-only by default, and `--no-daemon` inside `bwrap` — together with the trade-offs that motivated it.

**Blocked by:** 05 — Run the kit launch inside the bwrap sandbox

**Status:** ready-for-agent

- [ ] `CONTEXT.md` exists at the repo root and defines the glossary terms.
- [ ] `CONTEXT.md` is a glossary only — no implementation detail.
- [ ] An ADR records the sandbox policy: one writable directory, read-only git by default, and `--no-daemon` inside `bwrap`.
- [ ] The ADR states the alternatives considered and why this policy was chosen.

## Comments

Implemented; covered by `test/08_*_test.sh` (see `test/run.sh`).
