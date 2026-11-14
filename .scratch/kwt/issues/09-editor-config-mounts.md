# 09: Mount the developer's vim/nvim setup

**What to build:** When `$EDITOR` is vim or nvim, `kwt` mounts that editor's configuration and runtime directories inside the sandbox, so a sandboxed session can edit files with the developer's setup and plugins. For `nvim` this covers the `nvim` directories under the XDG config, data, state, and cache bases; config, data, and cache are read-only, while state is mounted writable because nvim writes its log, shada, and undo files there at startup. For `vim` (or `vi`) it covers `$XDG_CONFIG_HOME/vim`, `~/.vim`, and `~/.vimrc`, read-only. Directories that do not exist add no mounts, and an editor other than vim/nvim adds nothing.

**Blocked by:** 05 — Run the kit launch inside the bwrap sandbox

**Status:** ready-for-agent

- [ ] `nvim` config, data, and cache directories are mounted read-only.
- [ ] `nvim`'s state directory is mounted writable so its log/shada/undo writes succeed.
- [ ] The `nvim` mounts follow `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, and `XDG_CACHE_HOME`, with the usual defaults.
- [ ] `vim`/`vi` mounts `$XDG_CONFIG_HOME/vim`, `~/.vim`, and `~/.vimrc` read-only.
- [ ] `$EDITOR` may be a path or carry arguments; only the program name is inspected.
- [ ] A non-vim editor, or absent directories, produce no mounts.
- [ ] The mounts appear in the dry-run Plan.

## Comments

Implemented in `bind_editor_config` and covered by `test/05_sandbox_test.sh`.
