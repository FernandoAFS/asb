# The sandbox gets a private `/tmp`, an `/etc` allowlist, PID/IPC/UTS namespaces, no nested user namespaces, and no tmux or D-Bus rendezvous

## Status

Accepted. Amends ADR-0001's writable `/tmp`, wholesale `/etc` and `/run`
mounts, and shared process, IPC, UTS, and user-namespace view.

## Context

ADR-0001 shared the host's `/tmp` with the Sandbox and mounted all of `/etc`
read-only. Both are broader than the policy needs.

The host `/tmp` is a rendezvous point, not just scratch space. It holds tmux
sockets, X11 and Wayland sockets, agent sockets, and other temporary state. A
socket is reachable through a read-only mount: read-only prevents creating or
unlinking a socket, not connecting to one that already exists. The same is true
of the host's `/run`, where user services expose more sockets. `TMUX` and
`TMUX_TMPDIR` additionally tell a sandboxed tmux exactly which socket to use, so
an agent could attach to the developer's tmux server and run commands outside the
Sandbox.

Mounting `/etc` wholesale exposes more than a runtime needs: SSH host keys,
`shadow` and `gshadow`, `machine-id`, package-manager configuration, network
credentials, and a long tail of service configuration. Most of it is unreadable
to the sandbox user or simply irrelevant, but the mount gives the Sandbox a
readable path to every world-readable file under `/etc`.

Finally, without a PID namespace, `/proc` in the Sandbox is the host's process
table. `ps` and `/proc/<pid>/cmdline` expose the developer's other commands and
process arguments.

Without an IPC namespace, the Sandbox shares the host's System V IPC objects and
POSIX message queues. Without a UTS namespace, the Sandbox shares the host's
hostname and domainname and can call `sethostname` on the host's namespace.

## Decision

- **`/tmp` is a private tmpfs.** Mount `--tmpfs /tmp` instead of binding the
  host's `/tmp`. Each execution gets an empty, writable `/tmp` that disappears
  when the Sandbox exits. Nothing in the host `/tmp` is readable or connectable
  from inside, including the default tmux socket location.
- **Drop the tmux rendezvous variables.** Pass `--unsetenv TMUX` and
  `--unsetenv TMUX_TMPDIR`. A sandboxed tmux then starts its own server under
  the private `/tmp` rather than looking for the host's. Unsetting
  `TMUX_TMPDIR` alone is enough when the host uses the default socket path, but
  both variables are cheap to remove and `TMUX` carries the socket path
  directly.
- **`/etc` is an allowlist.** Do not mount `/etc` wholesale. Mount only the
  read-only entries needed for dynamic linking (`ld.so.cache`, `ld.so.conf`,
  `ld.so.conf.d`), account lookup (`passwd`, `group`, `nsswitch.conf`), DNS
  (`resolv.conf`, `hosts`, `gai.conf`, `host.conf`), TLS trust (`ssl/certs`,
  `ssl/cert.pem`, `ssl/openssl.cnf`, `ca-certificates`, and distribution
  equivalents under `pki`), time and locale (`localtime`, `timezone`), shell
  startup (`inputrc`, `bash.bashrc`, `profile`, `profile.d`, `shells`), and a
  few small data files (`services`, `protocols`, `mime.types`, `fonts`,
  `terminfo`, `os-release`). Entries are mounted only when they exist.
  Everything else, including `shadow`, `ssh`, and `machine-id`, stays absent.
- **Private PID, IPC, and UTS namespaces.** Add `--unshare-pid`, keeping
  `--proc /proc`, plus `--unshare-ipc` and `--unshare-uts`. The Sandbox sees
  only its own processes and IPC objects, and its hostname changes do not reach
  the host. The host process table is not reachable through `/proc`.
- **No nested user namespaces.** Add `--unshare-user --disable-userns`. bwrap
  caps `user.max_user_namespaces` inside the Sandbox's user namespace and enters
  a nested user namespace that cannot raise the limit, so a sandboxed process
  cannot create another user namespace to remount the filesystem or reach
  namespace-based escape primitives. `--unshare-user` is required by
  `--disable-userns` and does not change the Sandbox's uid or gid.
- **`/run` is not mounted, and the D-Bus rendezvous is dropped.** Do not bind
  the host's `/run`. It is a second socket rendezvous alongside `/tmp`: session
  and system D-Bus, the keyring and gpg-agent, PipeWire and PulseAudio, and
  other user services. DNS does not need it — bwrap resolves the
  `/etc/resolv.conf` symlink into `/run/systemd/resolve/resolv.conf` and binds
  the target's contents — so dropping `/run` costs nothing the Sandbox should
  have. Pass `--unsetenv DBUS_SESSION_BUS_ADDRESS` and
  `--unsetenv XDG_RUNTIME_DIR` as well, so a sandboxed process does not try the
  host bus or runtime tree even by path.

## Consequences

- A sandboxed process cannot read the host's temporary files or connect to host
  sockets that live in `/tmp`. Temporary files are always lost on exit, which
  matches the ephemeral-session policy of ADR-0002.
- A sandboxed tmux works, but it is a new server with no sessions from the
  host. Attaching from the host to a sandboxed tmux is not possible either.
- Tools that expect the host's files in `/etc` may lose functionality. DNS,
  TLS, passwd lookups, and common shell setup keep working; host-specific
  service configuration does not. If a tool needs another `/etc` file, the
  allowlist is the place to add it deliberately.
- `/etc` cannot be removed entirely. The dynamic linker and libc read it for
  library paths, identity, DNS, and timezone; TLS clients read the CA store.
  Removing all of it breaks ordinary network and tool use.
- `ps` inside the Sandbox shows only sandboxed processes. This hides the host's
  process metadata from the agent, but it does not hide the Sandbox from the
  host: a same-user process outside the Sandbox can still inspect it, and the
  host remains the isolation boundary. Hiding sandbox processes from the host
  would require a stronger isolation model, not a bwrap flag.
- Host IPC objects and POSIX message queues are not reachable. Processes inside
  one Sandbox still share that Sandbox's IPC namespace, so ordinary IPC works.
- The Sandbox keeps the host's hostname as its initial value but cannot rename
  the host. Tools that only read the hostname are unaffected.
- A sandboxed process cannot create a new user namespace. Nested bwrap, rootless
  containers, and tools that sandbox themselves with user namespaces (some
  browsers, for example) stop working. Ordinary tools are unaffected, and the
  failure is fail-closed: the restriction is part of the Sandbox, not a policy
  the tool can relax.
- No host D-Bus or other user-service socket is reachable: `/run` is not
  mounted and the runtime address variables are gone. Tools that expect a
  session bus, a keyring, or `$XDG_RUNTIME_DIR` lose that integration; nothing
  in the Sandbox needs it, and each Sandbox could start its own bus in the
  private `/tmp` if a tool ever did.

## Alternatives considered

- **Bind a per-execution directory from the host `/tmp`.** Gives the Sandbox a
  host-visible scratch directory and preserves nothing useful, while still
  exposing the host `/tmp` path. Rejected in favour of a mount-namespace-private
  tmpfs.
- **Keep the host `/tmp` and only unset `TMUX_TMPDIR`.** Fixes the default tmux
  case but leaves every other host temporary file and socket reachable.
- **Mount `/run` read-only and only unset the D-Bus address.** The socket path
  is well known (`/run/user/$UID/bus`, `/run/dbus/system_bus_socket`), and
  read-only does not stop connecting, so leaving `/run` mounted would leave the
  bus reachable by anything that does not consult the environment. Rejected in
  favour of not mounting `/run`.
- **Bind a per-execution directory from the host `/tmp`.** See above: a
  mount-namespace-private tmpfs is stronger and needs no host path.
  Rejected; the private tmpfs is the actual boundary.
- **Mount `/etc` read-only but filter sensitive files.** Still exposes the
  world-readable remainder and requires maintaining a denylist. Rejected in
  favour of an explicit allowlist.
- **Remove `/etc` entirely.** Simple, but breaks the dynamic linker, account
  lookup, DNS, TLS trust, and timezone handling. Rejected.
- **Add `--unshare-pid` and also hide the Sandbox from the host.** The second
  half is outside `asb`'s reach: the host kernel and same-user processes can
  inspect any child process. Rejected as a goal; the PID namespace only hides
  the host from the Sandbox.
- **Add a seccomp filter with `--seccomp`.** Deferred. bwrap's `--seccomp` takes
  a file descriptor to an already-compiled BPF program, not a policy file, so
  the launcher would have to ship or generate an architecture-specific filter.
  A denylist is weak and an allowlist is high-maintenance and likely to break
  agent toolchains. If seccomp is added later, it should be a tested profile,
  not a bare flag. Namespace isolation and `--disable-userns` address the more
  immediate escape paths.
- **Rely on the implicit user namespace bwrap creates and leave nested user
  namespaces enabled.** Simpler, and it keeps nested bwrap and rootless
  containers working, but leaves the most common unprivileged namespace escape
  primitive available. Rejected in favour of `--disable-userns`.
- **Add `--assert-userns-disabled` as well.** It verifies the restriction but
  takes no action of its own. `--disable-userns` already fails closed, so the
  assert is optional; it can be added if a future bwrap or kernel change makes
  the guarantee uncertain.