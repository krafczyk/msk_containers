# Threat Model

## Scope

This model covers the schema-2 single persistent OpenCode HTTPS service in
`docs/single-opencode-server/SPRINT_SPEC.md`:

```text
MkChad/Neovim
  -> detached Java TLS proxy on stable public loopback port
  -> detached OpenCode backend on automatic internal loopback port
  -> directory-scoped opencode attach TUI
```

The deployment is one intended user on a multi-user Linux host. Other processes
owned by that user are cooperative unless they are stale or accidentally reuse
an identity. An administrator is adversarial for availability and may
selectively kill processes.

Other unprivileged local users are not trusted. Loopback is host-wide, not
user-private. TLS authenticates the server to clients but does not authenticate
clients, and possession of the public CA certificate is not an access-control
mechanism. Without `OPENCODE_SERVER_PASSWORD`, other local users can access both
the public proxy and a discovered internal backend port.

## Security Boundary

Root is outside the enforceable boundary. Root can read/replace the CA key,
keystore password, state, process memory, procfs, fds, executable, environment,
container image, and loopback traffic; forge PID/start/boot/tuple evidence; or
deny execution. The design does not claim confidentiality, integrity, or
availability against root.

The practical boundary protects against accidental PID reuse, stale state,
ordinary unprivileged local endpoint replacement, bind races, and selective
process death while Linux procfs and user file permissions remain trustworthy.

## Assets

### Confidentiality

- OpenCode Basic Auth credentials.
- Provider credentials inherited by OpenCode.
- Prompts, request bodies, source, paths, session data, and SSE events.
- CA private key and its random PKCS12 password.

### Integrity

- Stable CA/public certificate identity and HTTPS URL.
- Exact association of public proxy, internal backend, generation, host boot,
  PID start times, executable/argv, listeners, and established socket inode.
- Current-directory routing and scoped reload isolation.
- Renewable lock ownership and generation-conditional cleanup.

### Availability

- Lazy MkChad startup independent of OpenCode.
- Bounded next-use recovery after proxy/backend/TUI/Neovim death.
- One pair and one generation under concurrent startup.
- Stable public URL and browser/client trust across ordinary recovery.

## Trust Assumptions

- Linux exposes readable `/proc/<pid>/stat`, `/proc/<pid>/fd`,
  `/proc/net/tcp{,6}`, and boot ID for the intended user's processes.
- Other unprivileged users cannot modify mode-`0700` state directories or read
  mode-`0600` state, logs, password, or keystores.
- Java 21/keytool, curl, OpenCode, and the selected executables are trusted.
- SingularityCE/Apptainer uses compatible host network/PID visibility.
- Hostname namespaces shared-home state but is not a credential.
- A CA-authenticated public TLS endpoint plus exact same-connection backend
  proof is required before managed clients send secrets.
- Client authorization requires the user-supplied OpenCode Basic Auth password;
  CA trust alone provides no client authorization.

## Required Controls

- Bind public and internal listeners only to loopback.
- Require explicit state CA for every lifecycle/plugin curl and
  `NODE_EXTRA_CA_CERTS` for attach.
- Keep CA key, password, stores, state, and logs private.
- Keep password content out of argv/state/logs/notifications/repository.
- Prominently warn and diagnose when no user-supplied Basic Auth password is
  present; do not invent or force a password.
- Validate process executable, exact argv, PID start time, boot ID, and listener
  inode before reuse or signal. For interpreted launches, also require the
  current launch-path inode; independently require the current Java proxy source
  inode.
- On every TLS connection, prove the exact reverse ESTABLISHED tuple and inode
  under the immutable expected backend PID before client reads/forwarding.
- Stop proxy first, then backend; replace both if either identity/health fails.
- Never send credentials to legacy HTTP, malformed/future state, unknown public
  listeners, or an unproved backend connection.
- Bound all locks, TLS handshakes, preflights, parsing, retries, connection
  handlers, pumps, process stops, and recovery attempts.

## Threats And Controls

### T1: Public Proxy Replacement

Threat: an unrelated listener binds the persisted public port after proxy death
or during startup and attempts to collect Basic Auth or request bodies.

Controls:

- Clients trust only the protected host CA and verify the `127.0.0.1` leaf.
- MkChad validates exact proxy PID/start/executable/argv and listening inode
  before an authenticated health request.
- Unknown explicit conflicts fail; automatic conflicts choose a bounded
  fallback and are never adopted.
- The CA private key remains in a mode-`0600` store with random mode-`0600`
  password.

Residual risk: root or another process with access to the CA private key can
mint/serve a trusted replacement.

### T1A: Unauthenticated Local-User Access

Threat: when `OPENCODE_SERVER_PASSWORD` is absent, another user on the same host
connects to the public TLS proxy or discovers and directly connects to the
internal loopback backend. TLS server authentication and relay tuple proof do
not deny that client.

Controls: MkChad preserves OpenCode's user-supplied Basic Auth on both endpoints,
warns at first use and in diagnostics, and documents the strong-password
stop/restart workaround. It does not generate a credential.

Residual risk: unauthenticated local access remains a P1 under explicit
exception `SPOS-AUD-P1-004`; owner, workaround, follow-up, and reevaluation
trigger are recorded in `docs/audit_policy.md`.

### T2: Internal-Port Takeover Before Proof

Threat: the backend dies or loses its listener and another process binds the
recorded internal port between validation and connection.

Controls:

- The proxy pins backend PID, start time, boot ID, and internal port at launch.
- It revalidates process identity before connecting.
- It sends only the fixed non-secret preflight before proof.
- It maps the exact reverse established 4-tuple and requires that socket inode
  under the expected backend PID's fd directory.
- No decrypted client request byte is read/forwarded before proof.
- Failure closes both sockets and never reconnects the stream.

Result: a replacement may see only the fixed preflight if takeover occurs after
the pre-connect identity check. It receives no Authorization/body/client bytes.
If the expected process is already dead, it receives zero bytes.

### T3: Backend Dies After Proof

Threat: the expected backend dies while a long HTTP/SSE stream is active and a
replacement binds the internal port.

Controls:

- The client stream remains tied to the already proved socket; the proxy never
  reconnects it.
- Pump monitoring revalidates PID/start/boot and inode ownership.
- Death/EOF/ownership loss closes the TLS client connection.
- The next operation replaces proxy and backend together under lock.

Residual risk: in-flight work is lost and the client must retry through the new
generation.

### T4: Tuple Ambiguity Or Unsupported Evidence

Threat: procfs is malformed/unavailable, multiple entries match, address-family
translation is unexpected, or the tuple disappears between preflight and proof.

Controls:

- Require exactly one reverse ESTABLISHED tuple across tcp/tcp6.
- Stream both tables under line, entry, byte, time, and concurrent-scan bounds;
  require exactly one valid family-specific header as each table's first line,
  fully validate every state-dependent data-row column and address width, and
  let any structural or exceeded-bound failure invalidate the whole proof.
- Apply the same complete bounded two-table grammar and exact cross-table
  uniqueness to every Lua lifecycle listener ownership check before fd inode
  ownership is accepted; do not rely on a procfs read prefix.
- Require the exact inode under expected PID fds.
- Fail closed on zero/multiple matches, parsing error, permission error, timeout,
  or unsupported platform evidence.

Residual risk: root can forge all evidence. Non-Linux platforms are unsupported
for this relay rather than silently weakened.

### T5: Preflight Smuggling Or Resource Exhaustion

Threat: a replacement or compromised backend returns chunked, close-delimited,
oversized, malformed, or slow data to confuse response boundaries or consume
resources before proof.

Controls:

- The request is a fixed unauthenticated keep-alive health GET.
- Accept only HTTP/1.0/1.1 status `200` or `401` with explicit bounded
  `Content-Length`.
- Reject transfer encoding (including chunked), `Connection: close`, duplicate
  or invalid length, oversized header/body, EOF, and timeout.
- Bound active handlers and use no unbounded executor queue.

Residual risk: repeated clients can consume the configured bounded concurrency
and cause temporary denial of service.

### T6: CA Key Or Password Disclosure

Threat: another local user reads the CA signing key/password and impersonates
the public endpoint.

Controls:

- State/TLS directories are `0700`; stores/password/CA PEM are `0600`.
- Password is random, passed to keytool with `-storepass:file`, read directly by
  Java, wiped from its temporary character array, and omitted from state/argv.
- Logs and diagnostics do not print file content or inherited environment.
- Invalid material is isolated and replaced under lock.

Residual risk: the signing key is software-protected, not hardware-backed; the
intended user and root can read it. The CA PEM is non-secret but remains `0600`
to keep all generated material consistently private.

### T7: Browser Trust Confusion

Threat: users assume HTTPS works automatically, trust the wrong CA, or mistake a
certificate warning for an acceptable loopback condition.

Controls:

- Documentation gives the exact host CA path and stable URL source.
- Browser trust is explicitly manual and never bypassed/disabled.
- CA/leaf stay stable across normal recovery.
- Diagnostics expose CA path and certificate identity.

Residual risk: browser trust stores and import UI differ by platform; an
incorrect manual trust decision is outside application enforcement.

### T8: Schema-1 Credential Leak

Threat: deployed schema-1 state points at an attacker-controlled HTTP listener,
and diagnostics/recovery send Basic Auth before migration.

Controls:

- Schema 1 is labeled legacy and never probed.
- The plugin URL/CA resolvers expose only schema 2.
- Under lock, migration or explicit stop signals only an exact verified legacy
  executable/argv/PID.
- Dead verified legacy state may be removed without network access.

Residual risk: an unverifiable live legacy process is left running rather than
risk signaling an unrelated PID; manual intervention may be required.

### T9: Selective Proxy Or Backend Death

Threat: an administrator kills one member and leaves stale state/the other
member alive.

Controls:

- Reuse requires both exact process identities/listeners, certificate identity,
  and pinned health.
- Any member death causes proxy-first cleanup of the surviving verified member
  and a new pair/generation on next use.
- Public port and valid certificate material are reused.
- Local TUI recycles on generation/CA/process mismatch.
- There is no unbounded background watchdog.

Residual risk: repeated selective killing defeats availability; recovery remains
bounded and user-triggered.

### T10: PID Reuse, Reboot, Or Forged State

Threat: a stale PID now names another process, boot changed, or state fields are
malformed/tampered.

Controls:

- Validate hostname, boot ID, PID type, liveness/non-zombie state, proc start
  ticks, immutable runtime executable device/inode, current interpreted launch
  and Java source device/inode, exact argv, role semantics, and listener inode.
- Keep native `/proc/<pid>/exe` device/inode authoritative across an on-disk
  replacement, including a ` (deleted)` readlink; refuse to signal a live
  interpreted/source process after its current recorded path is replaced.
- Signal only after renewing and revalidating lifecycle lock ownership.
- Prefer leaking an unverifiable process over signaling an unrelated process.
- Missing/malformed/future state is not probed or executed.

Residual risk: same-user malicious state modification and root forgery are not
cryptographically prevented. Filesystem ownership is the cooperative-user trust
boundary.

### T11: Lock Owner Or State Writer Death

Threat: Neovim dies after lock acquisition or after one child starts but before
complete state publication.

Controls:

- Preserve boot-scoped monotonic renewable leases and lock inode ownership.
- Use mode-private fsynced atomic writes.
- Record generation-specific pending process identities before final state.
- A later lock winner stops only verified pending proxy/backend processes.
- Final schema-2 state appears only after pinned health.

Residual risk: death between process spawn and pending publication can leave a
short-lived/unmanaged process; bind conflicts remain safe and unknown PIDs are
not signaled. This narrow crash window cannot be made transactional without an
external supervisor/process broker.

### T12: Unsafe Scoped Reload

Threat: reload targets the wrong directory, leaks credentials, interrupts work,
or replaces the shared pair.

Controls:

- Revalidate complete schema-2 state and pinned health under lock.
- Resolve current absolute cwd and route every request.
- Refuse busy sessions, permissions, or questions.
- Supply CA/auth/body through protected stdin curl config.
- Validate recreated `/path`, reconnect SSE, and recycle only local TUI.
- Require both PIDs, generation, URL/port, and certificate identity unchanged.

Residual risk: OpenCode lacks an atomic idle-and-dispose transaction and a TUI
readiness endpoint.

## Kill/Replacement Matrix

| Event | Expected result |
| --- | --- |
| Proxy killed | Next operation stops verified backend and creates one new pair |
| Backend killed | Existing proxy closes streams; next operation stops proxy first and creates one new pair |
| Replacement binds internal before proof | At most fixed preflight; zero client Authorization/body |
| Replacement binds after expected backend death | Zero bytes because PID/start check fails before connect |
| TUI killed | Next operation recreates attach with CA, URL, generation, and cwd |
| Origin Neovim exits | No intentional pair stop; detached pair remains where runtime permits |
| Lock owner killed | Lease/pending recovery is bounded and generation-specific |
| All user processes killed | New MkChad remains lazy; first operation performs bounded recovery |

## Audit Focus

Audits must prioritize CA/password exposure, public proxy impersonation,
internal takeover before proof, same-connection violations, reconnects after
proof, proc tuple ambiguity, process signaling, lock/pending races, legacy HTTP
credential paths, unbounded handlers/retries, and false healthy diagnostics.
Severity/completion rules are in `docs/audit_policy.md`.

## Residual Risk Acceptance

The accepted residuals are root control, software-only CA-key protection,
manual browser trust, bounded denial of service, next-use rather than continuous
recovery, detached-runtime variability, loss of in-memory work, and the explicit
`SPOS-AUD-P1-004` local-user access exception. Credential
forwarding before exact proof, reconnecting a client stream to a replacement,
or probing legacy HTTP with auth are not accepted residual risks.
