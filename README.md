<div align="center">

<img src="assets/logo.png" alt="asb — a brake rotor badge" width="150" />

# asb

### Pull the brakes on your agents.

**A single shell script that runs an AI coding agent inside a default-deny Linux
sandbox. No container. No VM. No daemon. No image to pull.**

[![Platform](https://img.shields.io/badge/platform-linux-2b6cb0?style=flat-square)](#install)
[![Dependencies](https://img.shields.io/badge/deps-bash%20%2B%20bwrap-4a5568?style=flat-square)](#install)
[![Launcher](https://img.shields.io/badge/launcher-~590%20lines%20of%20bash-89e051?style=flat-square)](asb)
[![License](https://img.shields.io/badge/license-MIT-3ba55d?style=flat-square)](LICENSE)

</div>

---

## The 30-second pitch

Giving an autonomous agent a shell is giving it your whole machine. A prompt
injection, a bad refactor, a runaway `rm` — the agent's tools run with *your*
permissions, everywhere you can write.

The usual answer is a heavier box: a Docker image, a dev container, a microVM, a
remote sandbox service. Each one brings a daemon, a runtime, an image to pull,
a kernel to boot, or a network hop before the model can touch a file.

**asb takes the opposite bet.** The boundary is one `bwrap` invocation and one
writable directory. The launcher is a bash script you can read over coffee. There
is nothing to boot, nothing to pull, and nothing running in the background — so
the "cost" of isolation is a `fork`, not a deployment.

```sh
# one command, one `bwrap` exec, one writable directory
asb kit ~/code/my-app
```

The launcher resolves the policy and `exec`s `bwrap` directly — there is no
second process to boot and nothing left running after the agent exits.

## Why it's different

| | Container sandbox | VM sandbox | Remote sandbox | **asb** |
|---|:---:|:---:|:---:|:---:|
| **Install** | image + runtime | hypervisor | vendor account | `make install` |
| **Startup** | seconds | seconds | network RTT | *milliseconds* |
| **Moving parts** | daemon, image | kernel, guest | hosted service | `bash` + `bwrap` |
| **Boundary** | container runtime | hypervisor | someone else's | Linux namespaces |
| **Runs as** | rootful/rootless | root | vendor | **you** |
| **Auditable in one sitting** | ✗ | ✗ | ✗ | **✓** |

asb is not trying to replace a hardened multi-tenant product. It's trying to be
the smallest thing that keeps an agent's blast radius inside the project you
pointed it at.

## What the sandbox actually does

`asb` builds one `bwrap` command line and `exec`s it. The policy is
**default-deny**: a process sees only what asb explicitly mounts.

- **One writable directory.** The *Target directory* (the repo you point asb at)
  is the only place a run can write. Everything else is read-only or absent.
- **Read-only git.** A project's `.git` is mounted read-only unless you opt in
  with `--allow-git-write`.
- **Private `/tmp` and `/dev`.** A fresh tmpfs per run, so host sockets in `/tmp`
  are unreachable.
- **A trimmed `/etc`.** Only the entries a runtime needs (linker, DNS, TLS trust,
  locale, shells) — not SSH host keys, `shadow`, or `machine-id`.
- **No `/run`.** The host's socket rendezvous (D-Bus, keyring, PipeWire) is not
  mounted at all.
- **Private PID, IPC, and UTS namespaces.** A run sees its own processes and IPC,
  and cannot rename the host.
- **No nested user namespaces.** A sandboxed process cannot remount the
  filesystem or spin up rootless containers to escape.
- **Read-only tooling and config.** Every directory on `PATH`, the agent's
  configuration, and your `$EDITOR` setup are mounted read-only — an agent can't
  rewrite the instructions it runs under.

Want to see the exact boundary before you trust it? Print the plan and run
nothing:

```sh
asb --dry-run kit ~/code/my-app
```

```
dir /home/you/code/my-app
sandbox bwrap --die-with-parent --unshare-user --disable-userns \
  --unshare-pid --unshare-ipc --unshare-uts --ro-bind /usr /usr …
```

The full policy and the reasoning behind it live in [`docs/adr/`](docs/adr/).

## Install

**Requirements:** Linux with [`bwrap`](https://github.com/containers/bubblewrap)
and `bash`. That's it for the launcher — no Go required unless you also want the
credential-injection proxy.

```sh
git clone https://github.com/<you>/asb.git
cd asb
make install          # asb + the headless kit extension + the proxy
```

`make install` drops the launcher in `~/.local/bin` and the extension in
`~/.config/kit/extensions`. Override anything you like:

```sh
make install PREFIX=/usr/local
make install EXT_DIR="$HOME/.config/kit/extensions"
make install-script   # launcher only
```

## Usage

```
asb [<options>] <agent> [<dir>] [-- <args>...]
```

```sh
asb kit                         # sandbox kit in the current directory
asb pig ~/code/my-app           # sandbox pig against another project
asb kit ~/code/my-app -- --continue   # args after `--` go to the agent
asb --shell kit ~/code/my-app   # drop into the same sandbox for debugging
```

| Option | What it does |
|---|---|
| `--allow-git-write` | Make the project's git state writable inside the sandbox |
| `--dry-run` | Print the resolved plan; perform no side effects |
| `--shell` | Run a shell under the same policy, for debugging |
| `-h`, `--help` | Show help |

`<dir>` defaults to the current directory and becomes the sandbox's working
directory and its one writable root.

### Supported agents

| Agent | Profile | Sessions |
|---|---|---|
| **kit** | config mounted read-only, headless extension enabled | ephemeral |
| **pig** | config copy-on-write, session store owned by the Target | durable (`--continue` / `--resume`) |

An agent is always explicit — there is no agent-less sandbox, because the
profile decides the payload. Adding one is a profile plus a `case` in
[`asb`](asb).

## Keeping secrets out of the box

Isolation limits *where* an agent writes; it doesn't stop an agent from *reading*
a token you mounted for it. [`asb-proxy`](proxy/README.md) is the companion
tool for that: a small host-side reverse proxy that holds your credentials and
injects them into outgoing requests, so the agent authenticates **without ever
holding the token**. It runs on the host, on a plaintext local hop — no TLS
interception and no proxy CA.

```
agent ──HTTP──▶ bridge ──unix socket──▶ asb-proxy serve ──HTTPS──▶ upstream
      (in sandbox)                       (on host, holds the secret)
```

```sh
make proxy        # build proxy/asb-proxy
```

The proxy is standalone today: the launcher does not invoke it yet, and egress
filtering is deliberately out of scope for now. See
[`proxy/README.md`](proxy/README.md) for the configuration reference and
[`docs/specs/proxy-injector.md`](docs/specs/proxy-injector.md) for the design
and milestones.

## Documentation

| Document | Contents |
|---|---|
| [`CONTEXT.md`](CONTEXT.md) | The vocabulary the project uses — Target directory, Sandbox, agent session, Project |
| [`docs/adr/`](docs/adr/) | Architecture decision records for the sandbox policy |
| [`docs/specs/`](docs/specs/) | Feature specifications |
| [`proxy/README.md`](proxy/README.md) | The credential-injecting proxy |

## Development

```sh
make test     # the shell suite plus `go test ./...`
```

The shell tests drive the launcher through `--dry-run`, so they assert on the
exact `bwrap` plan without needing real namespaces. Integration tests exercise
the real sandbox when `bwrap` is available.

## License

[MIT](LICENSE).
