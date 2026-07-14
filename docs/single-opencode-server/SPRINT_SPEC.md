# Single Persistent OpenCode Server Sprint Specification

## Document Status

| Field | Value |
| --- | --- |
| Status | Implemented locally; runtime/container/browser evidence remains gated below |
| Scope | `msk_containers`, MkChad configuration, and `krafczyk/opencode.nvim` |
| Primary platform | SingularityCE and Apptainer with host network and PID visibility |
| OpenCode baseline | `opencode-ai@1.17.20` on x86_64 and aarch64 |
| Public endpoint | HTTPS with CA-pinned server identity on host-specific `127.0.0.1:<public-port>` |
| Internal endpoint | Automatic high-port HTTP on `127.0.0.1`; managed clients use the proved relay, but local users can discover and connect directly |
| State root | `${XDG_STATE_HOME:-$HOME/.local/state}/mkchad/opencode/<hostname>` |
| State schema | `2` |

## Summary

MkChad lazily manages one detached OpenCode backend and one detached Java 21 TLS
proxy per user and host. The public URL is stable and uses a stable host-specific
CA. OpenCode Basic Auth credentials, request bodies, prompts, and SSE data are
sent only through a CA-authenticated TLS connection.

**Multi-user warning:** TLS authenticates server identity, not clients, and CA
possession does not control client access. Unless the user supplies
`OPENCODE_SERVER_PASSWORD`, both the public proxy and discoverable internal
loopback backend are unauthenticated to other local users. Set a strong existing
environment password before first use; if already running, set it, stop the
shared pair, and restart. This is the explicit `SPOS-AUD-P1-004` exception in
`docs/audit_policy.md`.

The proxy does not trust a process name, listener, health response, or PID by
itself. For every client TLS connection it opens exactly one connection to the
recorded backend, sends only a fixed unauthenticated keep-alive
`GET /global/health`, consumes a bounded `200` or `401`, and proves that exact
established connection belongs to the expected backend before reading or
forwarding decrypted client HTTP bytes. It never reconnects a client stream.

Ordinary MkChad startup, plugin loading, statusline rendering,
`:checkhealth opencode`, `:OpenCodeInfo`, and inactive `:OpenCodeReload` remain
lazy. The first OpenCode operation starts the pair and a directory-scoped local
`opencode attach` TUI. Selective proxy or backend death replaces both processes
on the next operation. Neovim exit does not stop the pair.

## Goals

- Resolve `SPOS-AUD-P0-003`: no credential-bearing direct loopback HTTP.
- Expose only a host-CA-authenticated HTTPS public URL.
- Prove backend ownership on the same established socket used for client bytes.
- Keep the public port and certificate stable across ordinary recovery.
- Keep one generation containing at most one proxy/backend pair.
- Preserve lazy startup, detached persistence, renewable locking, directory
  routing, scoped reload, status clearing, terminal behavior, and Basic Auth.
- Preserve the lock-lease repair at MkChad `cdf5499` and the initial SSE bound at
  opencode.nvim `e04b7a7`.
- Migrate deployed schema-1 state without sending credentials to its HTTP URL.

## Non-Goals

- Defending against root, a compromised kernel, or a root-modified CA store.
- Exposing either endpoint on non-loopback interfaces.
- Automatically installing browser trust.
- Running a continuous watchdog, systemd service, or container instance.
- Generating OpenCode Basic Auth credentials.
- Solving OpenCode's same-directory multi-TUI or TUI-readiness limitations.
- Changing ppc64le or unrelated P2 findings.

## Topology

```text
browser (manual CA trust) ----\
opencode.nvim (curl cacert) ---+--> TLS 127.0.0.1:<public port>
opencode attach (NODE CA) ----/              |
                                                Java 21 proxy
                                                fixed preflight
                                                tuple + inode proof
                                                       |
                                          HTTP 127.0.0.1:<internal high port>
                                                       |
                                                opencode serve
```

The proxy and backend inherit the creating MkChad container's mount, network,
PID, configuration, executable, and environment context. Both bind loopback.
The internal port is never the persisted/public `OPENCODE_PORT` policy port.

## Certificate Material

Under the host state root, `tls/` contains:

| File | Purpose | Mode |
| --- | --- | --- |
| `ca.p12` | Stable host CA private key and certificate | `0600` |
| `ca.pem` | CA certificate supplied explicitly to clients | `0600` |
| `server.p12` | `127.0.0.1` leaf key and CA chain loaded by Java | `0600` |
| `server.pem` | Generated leaf certificate evidence | `0600` |
| `store.password` | Random keytool/PKCS12 password | `0600` |

The state root and `tls/` are `0700`. Generation uses Java `keytool`, EC keys,
PKCS12 stores, and `-storepass:file`. The random password value never appears in
argv, lifecycle state, logs, notifications, or repository files. No OpenSSL
runtime dependency is required.

Certificate material is validated and reused under the lifecycle lock. It is
regenerated only when absent or invalid. Regeneration atomically isolates old
material before publishing a complete replacement. Ordinary backend/proxy
recovery does not rotate the CA or leaf. State records the stable CA path and a
certificate identity, not keystore password content.

Browsers must manually import/trust:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/mkchad/opencode/<host>/tls/ca.pem
```

Browser trust is intentionally not automated. The URL remains the exact HTTPS
URL reported by `:OpenCodeInfo`.

## TLS Proxy Contract

The source is `java/MkChadTlsProxy.java` in MkChad and requires Java 21 or
newer. It directly loads `server.p12` into an `SSLContext`, binds an
`SSLServerSocket` to `127.0.0.1`, permits TLS 1.2/1.3, advertises no ALPN
protocol, and bounds accepted work with a semaphore and virtual threads.

For each accepted connection:

1. Complete TLS before backend work.
2. Revalidate boot ID, backend PID, and `/proc/<pid>/stat` start time.
3. Connect once to the immutable recorded internal port.
4. Send exactly the non-secret fixed preflight request.
5. Bound headers, body, and timeout; require status `200` or `401`, explicit
   bounded `Content-Length`, and keep-alive semantics.
6. Reject malformed, oversized, chunked, transfer-encoded, close-delimited, or
   timed-out responses.
7. Stream both `/proc/net/tcp` and `tcp6` with fixed line, entry, aggregate-byte,
   time, and concurrent-scan bounds. Require each table to begin with exactly
   one complete family-specific Linux proc header and reject empty, headerless,
   repeated-header, malformed, or otherwise incomplete scans. Validate every
   row field, including the family-specific address widths, ports, state,
   queue/timer pairs, retransmit count, UID, timeout/probe count, inode,
   reference count, pointer, and state-dependent trailing fields. Require the
   current 17-column socket form or the 12-column `SYN_RECV`/`TIME_WAIT` form
   exactly. Map the exact reverse ESTABLISHED 4-tuple only after both tables
   complete.
8. Require exactly one tuple and require its socket inode under
   `/proc/<expected-backend-pid>/fd`.
9. Revalidate PID start and boot identity.
10. Only then start raw bidirectional pumping on that same backend socket.
11. While pumping, revalidate process identity and inode ownership; close both
    directions on EOF, process death, ownership loss, or error.

No client Authorization header, body, request path, prompt, or SSE byte is read
and forwarded before proof. A listener replacement may receive at most the
fixed preflight before a proof failure. If the expected backend is already dead,
the proxy fails before connecting, so a replacement receives no bytes. The
proxy never reconnects a client stream after proof or failure.

Unsupported procfs evidence fails closed. Root can forge procfs or take over the
user's files and remains outside the enforceable boundary.

The proc proof scanner permits at most 4,096 bytes per line, 200,000 entries and
16 MiB total across both tables, and five seconds per acquired scan. At most
eight scans run concurrently; permit acquisition is bounded to three seconds.
Exceeding any bound, malformed input, a truncated final line, or an unreadable
table invalidates the complete proof rather than accepting a partial result. A
match in one table cannot be accepted if the other table is structurally
incomplete.

MkChad listener ownership uses a separate Lua streaming scanner with the same
4,096-byte line, 200,000-entry, 16 MiB aggregate, five-second, exact-header,
row-grammar, complete-two-table, and exact-cross-table-uniqueness contract. It
does not use the generic 8 KiB proc pseudo-file read. Only after one loopback
LISTEN row is proved does MkChad require that inode under `/proc/<pid>/fd`.
Every bound, read, parse, truncation, ambiguity, or incomplete-table failure is
unverifiable and fails closed.

## State Schema 2

`state.json` is atomically written only after both listeners, process identities,
and pinned authenticated HTTPS health are ready. It contains one generation:

```json
{
  "schema": 2,
  "hostname": "host",
  "generation": "unique-token",
  "host": "127.0.0.1",
  "port": 4096,
  "url": "https://127.0.0.1:4096",
  "port_source": "preferred 4096",
  "started_at": "2026-07-14T12:34:56Z",
  "cwd": "/home/user",
  "boot_id": "kernel-boot-id",
  "ca_path": "/home/user/.local/state/mkchad/opencode/host/tls/ca.pem",
  "certificate_identity": "sha256-identity",
  "proxy": {
    "pid": 1234,
    "port": 4096,
    "argv": ["java", "--source", "21", "..."],
    "process_executable": "/usr/bin/java",
    "executable": "/usr/bin/java",
    "start_time": "proc-start-ticks",
    "process_executable_dev": "8",
    "process_executable_ino": "12345",
    "executable_dev": "8",
    "executable_ino": "12345",
    "source": "/home/user/.config/mkchad/java/MkChadTlsProxy.java",
    "source_dev": "8",
    "source_ino": "12346",
    "log": ".../proxy.log"
  },
  "backend": {
    "pid": 1235,
    "port": 55001,
    "argv": ["opencode", "serve", "--hostname", "127.0.0.1", "--port", "55001"],
    "process_executable": "/resolved/runtime",
    "executable": "/resolved/opencode",
    "start_time": "proc-start-ticks",
    "process_executable_dev": "8",
    "process_executable_ino": "22345",
    "executable_dev": "8",
    "executable_ino": "22346",
    "local_version": "1.17.20",
    "server_version": "1.17.20",
    "log": ".../server.log"
  }
}
```

No Basic Auth password, keystore password, provider credential, session data, or
certificate/key content is stored. The proxy argv necessarily records
non-secret protected-file paths so exact process identity can be checked.

`pending.json` is mode `0600` transient crash-recovery metadata. It records only
the exact identities of a generation launched before final state publication.
A later lock owner stops only verified pending processes, proxy first, before
starting another pair.

Missing state is inactive. Malformed state is never executed or probed and may
be replaced only under lock. Future schemas are not overwritten. Diagnostics
label schema 1 as legacy and never probe its HTTP URL.

Runtime process ownership uses the immutable device/inode of
`/proc/<pid>/exe`; readlink text is diagnostic and may end in ` (deleted)` after
an atomic replacement. Exact argv, PID start, boot, role, and listener checks
still apply. Unsigned device/inode integers are encoded as canonical decimal
strings so JSON does not round values above signed or IEEE-754 ranges. Launch
executable identity is recorded separately. For an
interpreted `opencode` script, it identifies the launch source while procfs
identifies the interpreter runtime; for Java source launch, Java runtime and
`MkChadTlsProxy.java` identities are both recorded. Whenever launch and runtime
identities differ, the current launch path must still match its recorded
device/inode; the Java source path must independently match its recorded
device/inode. Replacement makes the running interpreted/source-launched process
unverifiable, so reuse, requests, readiness, pending cleanup, and signaling are
refused. Native `/proc/<pid>/exe` identity remains authoritative even when its
path is marked ` (deleted)`. Old schema-2 or pending metadata without these
fields is malformed and is never signaled. Recovery may start a pair on free
ports or fail boundedly; old processes require trusted manual accounting before
pending metadata is removed.

## Startup And Port Policy

The renewable lock from `cdf5499` remains authoritative. Acquisition,
monotonic boot-scoped leases, renewal, stale reclaim, inode-bound ownership, and
release are bounded.

The lock winner:

1. Re-reads state and validates a healthy schema-2 pair by exact process
   executable, argv, PID start, boot ID, both listener inodes, certificate
   identity, and pinned HTTPS health.
2. Returns a healthy matching pair without rotation.
3. Stops a failed pair proxy first, then the verified backend.
4. Stops only a verified schema-1 process without HTTP probing, removes matching
   legacy state, and continues migration.
5. Cleans verified interrupted `pending.json` processes.
6. Ensures stable certificate material.
7. Selects the public port: exact `OPENCODE_PORT`, persisted automatic port,
   preferred `4096`, or bounded high fallback.
8. Selects a distinct bounded automatic high internal port.
9. Launches detached `opencode serve` and proves exact identity/listener.
10. Launches the Java proxy with immutable backend PID/start/boot/port and proves
    exact identity/listener.
11. Requires pinned authenticated HTTPS `/global/health` through the proxy.
12. Atomically publishes complete schema-2 state and removes pending metadata.

Every failure cleanup is generation and process-identity specific. Retries are
bounded. Automatic mode may retry a bind race with excluded failed candidates;
an explicit public-port conflict never falls back. Waiting contenders poll for
the winner and never launch another pair while its renewable lease is valid.

## Stop And Recovery

Explicit stop acquires the lifecycle lock, re-reads state, and signals only
exact verified identities. It stops the proxy first, then the backend, bounds
SIGTERM/SIGKILL waits, removes only matching generation state, and closes the
invoking Neovim's TUI. It never probes legacy HTTP state.

If either process dies, identity/listener/certificate validation or pinned
health fails, the next OpenCode operation replaces both under lock. The public
port and valid certificate material are reused. A local TUI is recycled when
its process, directory, URL, generation, or certificate identity changes.
There is no `ExitPre` stop and no background restart loop.

## Client Integration

MkChad health and reload curl jobs pass `cacert`, Basic Auth, directory headers,
and bodies through mode-protected stdin curl configuration. Secrets and bodies
do not appear in argv. Requests force HTTP/1.1.

opencode.nvim adds optional `server.ca_cert`, as a path or request-time resolver.
Every REST and SSE curl resolves it and supplies `cacert` through protected stdin
configuration. Existing username/password, body, current-directory routing,
timeouts, and SSE behavior remain intact.

The local command remains:

```text
opencode attach https://127.0.0.1:<public-port> --dir <absolute-cwd>
```

Its child environment receives `NODE_EXTRA_CA_CERTS=<state ca.pem>`. Existing
OpenCode auth environment and terminal behavior remain inherited.

## Scoped Reload And Diagnostics

Reload uses only the validated schema-2 state and pinned CA. It checks current
directory session status, permissions, and questions; refuses active work;
disposes and recreates only that directory; validates `/path`; reconnects the
plugin; and recreates only the local TUI. Proxy PID, backend PID, generation,
public URL/port, internal port, and certificate identity must remain unchanged.

`:OpenCodeInfo` is observational. It reports state/schema, HTTPS URL, CA path,
certificate identity, both PIDs/ports/logs, generation, versions, SSE, cwd, TUI,
and fresh pinned health only after exact schema-2 ownership/listener validation.
It sends no request to missing, malformed, future, legacy, or ownership-invalid
state and starts no process.

## Acceptance Criteria

- Curl fails without the host CA and succeeds with it.
- Authenticated HTTP and long-lived SSE pass through the Java relay.
- A replacement listener receives no credential-bearing/client bytes before
  proof or after expected backend death.
- Tuple ambiguity, tuple mismatch, inode/PID ownership mismatch, PID-start
  mismatch, boot mismatch, malformed/chunked/close/oversized preflight, timeout,
  and process death fail closed.
- Concurrent connections are bounded and concurrent startup converges on one
  generation and one pair.
- Proxy-only or backend-only death replaces both; CA identity remains stable.
- Origin Neovim exit and local TUI death preserve documented behavior.
- Automatic/explicit public conflicts, internal races, legacy migration/stop,
  malformed/future state, auth `401`, reload, laziness, and renewable lease
  paths are bounded and tested.
- Installed `opencode attach` honors `NODE_EXTRA_CA_CERTS`; local 1.17.18
  evidence is acceptable while the 1.17.20 runtime check remains recorded.
- Existing opencode.nvim curl/SSE and MkChad focused tests pass.

## Limitations And Runtime Gates

- Root can read or replace CA keys, forge procfs, inject file descriptors, or
  intercept loopback traffic. This is residual root risk, not a claimed control.
- The CA signing key is protected by user filesystem permissions, not hardware.
- Internal HTTP exists on loopback. The relay prevents managed clients from
  sending credentials before proof; it does not make loopback invisible.
- Without `OPENCODE_SERVER_PASSWORD`, local users can use both endpoints. TLS
  authenticates only server identity. See the explicit P1 exception in
  `docs/audit_policy.md`.
- Detached persistence still depends on SingularityCE/Apptainer/site policy.
- Browser import, real browser web UI, SingularityCE, Apptainer, container
  baseline builds, and OpenCode 1.17.20 attach remain runtime evidence gates and
  must not be marked passed without execution.
- Recovery is next-use, not continuous; in-memory work can be lost.
- OpenCode has no attached-TUI readiness API.

## Rollback

1. Use `:OpenCodeStop` to stop only a verified schema-2 pair, proxy first.
2. Preserve logs and protected TLS material for diagnosis; do not expose the CA
   private store or password.
3. Revert MkChad lifecycle, opencode.nvim CA support, and fork pin together.
4. If reverting to schema 1, treat remaining schema-2 state as unsupported and
   stop verified processes before downgrade; never reuse its internal port as a
   public endpoint.
5. Restore per-Neovim lifecycle/`ExitPre` only as an explicit architectural
   rollback, not as partial mixed state.
6. Container baseline updates are independent unless their normal builds fail.
