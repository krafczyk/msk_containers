# Optional OpenCode Transport Sprint Checklist

## Decisions

- [x] Keep the Java TLS proxy enabled by default.
- [x] Add strict protected-config Boolean `tls_proxy`; absence means `true`.
- [x] Do not add an environment override for `tls_proxy`.
- [x] Permit `false` only as an explicit trusted-host direct HTTP profile.
- [x] Require explicit shared stop and Neovim restart for transport changes.
- [x] Refuse automatic replacement when requested and active transports differ.
- [x] Repair explicit stop for a dead proxy with a verified live backend.
- [x] Keep recovery next-use; do not add a watchdog.
- [x] Retain protected TLS material while direct mode is active.
- [x] Use schema 3 with an explicit transport discriminator.

## Sprint Preparation

- [x] Archive the superseded TLS-only specification and checklist under
      `docs/archive/single-opencode-server-tls-baseline/`.
- [x] Preserve active governing paths for the new sprint.
- [x] Record implementation baselines and the archived sprint location.
- [ ] Read all in-scope `AGENTS.md` files before implementation.
- [ ] Re-read the active sprint spec, threat model, and audit policy before each
      Builder/Auditor cycle.
- [ ] Preserve MkChad's unrelated untracked `lazy-lock.json`.
- [ ] Preserve the unrelated `msk_containers` JDT archive.
- [ ] Use only `/tmp/opencode/**` for temporary fixtures.
- [ ] Do not inspect or expose real credentials or unrelated session data.
- [ ] Commit or push only with explicit user authorization.

## Policy Profiles

- [ ] Complete and review this section before any production implementation.
- [ ] Amend `docs/threat_model.md` with hardened TLS and trusted-host direct
      profiles.
- [ ] Amend `docs/audit_policy.md` so direct HTTP remains P0 in the hardened
      multi-user profile and is an explicit opt-out in the trusted-host profile.
- [ ] State that the protected config controls mode selection, not transport
      security.
- [ ] State that SSH tunneling does not restore local endpoint identity.
- [ ] State that Basic Auth remains required for multi-user TLS mode because the
      internal backend port is discoverable and directly reachable.
- [ ] State that Basic Auth over direct HTTP is not transport encryption.
- [ ] Enumerate the direct-mode threats excluded by trusted-host assumptions and
      the controls that remain mandatory.
- [ ] Stop the sprint without implementation if the two-profile policy cannot be
      approved.
- [ ] Add a reevaluation trigger if the trusted-host deployment gains untrusted
      users, packet-capture capability, non-loopback exposure, or different
      tunneling assumptions.

## Configuration

- [ ] Add `tls_proxy` to the supported config keys.
- [ ] Accept only JSON Boolean values.
- [ ] Default to enabled when absent.
- [ ] Reject string, number, null, array, and object values.
- [ ] Preserve current-user ownership, regular-file, mode-`0600`, size, and
      bounded JSON validation.
- [ ] Preserve environment precedence only for port, username, and password.
- [ ] Keep config and password content out of errors and diagnostics.
- [ ] Update `opencode-server.example.json` and MkChad README.
- [ ] Document process-cached loading and required Neovim restart.

## Schema 3

- [ ] Define `transport` as exactly `tls-proxy` or `loopback-http`.
- [ ] Retain common top-level `hostname`, `generation`, `host`, `port`, `url`,
      `port_source`, `started_at`, `cwd`, `boot_id`, and `backend` fields.
- [ ] Preserve all common backend PID/start/boot/argv/executable/listener fields.
- [ ] Require HTTPS, proxy, distinct backend port, CA path, and certificate
      identity for TLS state.
- [ ] Require HTTP, absent proxy/active-CA fields, and backend/public port
      equality for direct state.
- [ ] Add transport to pending metadata.
- [ ] Distinguish TLS backend-only pending state from complete direct pending
      state.
- [ ] Keep pending writes/removals and cleanup generation-conditional under the
      kernel fence.
- [ ] Keep all managed signals behind fresh identity validation and pidfds.
- [ ] Accept existing valid schema-2 state only as TLS mode.
- [ ] Reuse healthy schema-2 TLS state without unsafe mutation.
- [ ] Publish all new generations as schema 3.
- [ ] Preserve live schema-1 non-signaling behavior.
- [ ] Ensure older code treats schema 3 as unsupported and non-mutable.
- [ ] Document stop-before-downgrade requirements.

## Mode Agreement And Transitions

- [ ] Compare trusted active transport with process-cached requested mode before
      reuse.
- [ ] Reuse only a matching healthy generation.
- [ ] Refuse opposite-mode ensure with explicit stop/restart guidance.
- [ ] Never auto-replace a healthy opposite-mode generation.
- [ ] Let `:OpenCodeStop` follow trusted state independent of requested mode.
- [ ] Prevent stale opposite-mode Neovim instances from generation flapping.
- [ ] Recycle local TUI when transport changes.
- [ ] Preserve valid TLS files across disable/re-enable.
- [ ] Validate/reuse or safely regenerate retained material only when TLS is
      re-enabled.

## Common Lifecycle

- [ ] Preserve lazy startup and observational info.
- [ ] Preserve the process-held kernel fence and renewable logical lock.
- [ ] Preserve bounded subprocess execution, output caps, TERM/KILL escalation,
      reaping, and callback cleanup.
- [ ] Preserve exact configured-port refusal and bounded automatic selection.
- [ ] Preserve exact backend executable, argv, start, boot, and listener proof.
- [ ] Publish complete state only after mode-appropriate health succeeds.
- [ ] Preserve generation-specific pending cleanup and state removal.
- [ ] Keep Neovim exit from stopping the shared service.

## TLS Mode

- [ ] Preserve separate public and internal ports.
- [ ] Preserve stable CA and leaf validation/generation.
- [ ] Preserve Java runtime and source identity validation.
- [ ] Preserve TLS handshake, fixed unauthenticated preflight, tuple/inode proof,
      complete proc scanning, and no-reconnect behavior.
- [ ] Preserve backend-first launch and proof followed by proxy launch and proof.
- [ ] Preserve pinned authenticated HTTPS health before state publication.
- [ ] Preserve proxy-first explicit stop for a complete pair.
- [ ] Keep every archived Java/TLS security test passing unchanged.

## Direct Mode

- [ ] Launch only OpenCode on the selected public port.
- [ ] Publish `http://127.0.0.1:<port>`.
- [ ] Require `backend.port == state.port`.
- [ ] Skip internal-port selection.
- [ ] Skip Java and proxy-source discovery/validation.
- [ ] Skip keytool and certificate validation/generation.
- [ ] Create no new TLS material on a fresh direct-only deployment.
- [ ] Prove the exact backend owns the public listener before health or state
      publication.
- [ ] Reject helper-listener adoption and public-port replacement races.
- [ ] Use HTTP health only for a fully validated direct pending generation.
- [ ] Preserve Basic Auth when supplied without claiming transport encryption.
- [ ] Fail exact configured-port conflicts without fallback.

## Death And Stop

- [ ] Keep proxy/backend recovery next-use rather than watchdog-driven.
- [ ] Prove proxy-only death leaves backend/state unchanged before an ensuring
      action.
- [ ] Keep `:OpenCodeInfo` observational after proxy death.
- [ ] Keep reload from starting an unhealthy service.
- [ ] On ensure after proxy death, stop the verified backend and replace the full
      TLS generation.
- [ ] Repair `:OpenCodeStop` to clean a verified surviving backend after proxy
      death without launching a replacement.
- [ ] Never signal a surviving backend if its identity is unverifiable.
- [ ] Preserve matching state unless all exact managed roles are confirmed dead.
- [ ] Preserve bounded TERM, exit wait, KILL escalation, and final death check.
- [ ] Preserve state on identity, helper, signal, timeout, escalation, or final
      death-confirmation failure.
- [ ] Keep public-port reuse conditional on availability.
- [ ] Keep valid CA identity stable across ordinary TLS recovery.
- [ ] Recover a dead direct backend on the next ensuring action.
- [ ] Never adopt a surviving TLS backend as direct mode.
- [ ] Never reconnect a stale client stream to a replacement process.

## Clients

- [ ] Return HTTPS and CA only for validated TLS state.
- [ ] Return HTTP and nil CA only for validated direct state.
- [ ] Inject `NODE_EXTRA_CA_CERTS` only in TLS mode.
- [ ] Include transport in TUI reuse/recycle identity.
- [ ] Preserve Basic Auth and body delivery through protected curl stdin.
- [ ] Preserve request-time directory routing for REST and SSE.
- [ ] Verify existing opencode.nvim HTTP/no-CA behavior.
- [ ] Verify existing opencode.nvim HTTPS/pinned-CA behavior.
- [ ] Avoid an opencode.nvim production change unless focused tests demonstrate
      a missing transport-neutral behavior.

## Reload And Diagnostics

- [ ] Make reload invariants transport-aware.
- [ ] Always preserve backend PID, generation, URL, port, and transport.
- [ ] Require proxy PID and certificate identity only in TLS mode.
- [ ] Report requested and active transport.
- [ ] Report mode mismatch and exact stop/restart remediation.
- [ ] Report active HTTP or HTTPS URL accurately.
- [ ] Omit active proxy/CA claims in direct mode.
- [ ] Label retained TLS material inactive while direct mode runs.
- [ ] Send health only after transport-appropriate ownership/listener validation.

## Focused Tests

- [ ] Add table-driven `tls_proxy` config parsing tests.
- [ ] Add schema-2/schema-3 TLS/direct/pending validation matrices.
- [ ] Add malformed cross-transport and future-schema cases.
- [ ] Add direct startup without Java/keytool/certificate dependencies.
- [ ] Add direct authenticated and unauthenticated HTTP tests.
- [ ] Add exact and automatic port-conflict tests in both modes.
- [ ] Add TLS-to-direct and direct-to-TLS explicit transition tests.
- [ ] Add stale opposite-mode Neovim refusal tests.
- [ ] Expand proxy-death tests for the no-watchdog interval, info, reload,
      ensuring recovery, port/CA stability, and explicit partial stop.
- [ ] Test partial stop with TERM resistance, KILL escalation, helper failure,
      timeout, identity mismatch, and unconfirmed death; require state retention
      on every incomplete cleanup.
- [ ] Add direct backend death and replacement-listener tests.
- [ ] Add direct listener-adoption race tests.
- [ ] Parameterize concurrent startup for both modes.
- [ ] Parameterize reload and TUI tests for both modes.
- [ ] Verify direct mode creates no TLS files from an empty fixture.
- [ ] Verify retained TLS files survive direct mode unchanged.
- [ ] Verify credentials/config content stay out of state, argv, logs,
      notifications, Git diffs, and test output.

## Regression Verification

- [ ] Run the full MkChad serial lifecycle suite.
- [ ] Run pending-generation, state-validation, lock-lease, fence-race, startup-
      race, executable-identity, proc-scanner, reload, and concurrent-startup
      suites.
- [ ] Run bounded-subprocess timeout/overflow/reaping matrices.
- [ ] Run pidfd signaling tests.
- [ ] Run Java `--release 21 -Xlint:all -Werror`.
- [ ] Run Java tuple, malformed proc-table, constrained-heap, concurrency, HTTP,
      SSE, replacement, and credential-forwarding tests.
- [ ] Run opencode.nvim protected-curl, TLS, HTTP, and SSE tests.
- [ ] Run Python compile checks.
- [ ] Run `git diff --check` in every changed repository.
- [ ] Run available Lua formatting/static checks or record unavailable tooling.

## Documentation

- [ ] Update MkChad README with both topology diagrams and security profiles.
- [ ] Update config examples and stop/restart ordering.
- [ ] Update threat model and audit policy before claiming implementation
      readiness or changing production code.
- [ ] Keep archived TLS-only documents unchanged.
- [ ] Distinguish archived TLS evidence from new direct-mode evidence.
- [ ] Document direct-mode browser HTTP behavior and scheme-changing bookmarks.
- [ ] Document killed-proxy immediate effects and exact recovery triggers.
- [ ] Document that `:OpenCodeStop` affects all shared clients in both modes.

## Runtime Evidence

- [ ] Verify a real TLS-mode browser session with trusted CA.
- [ ] Verify a real direct-mode browser session through the intended SSH tunnel.
- [ ] Verify TLS-mode Basic Auth on public and direct internal endpoints.
- [ ] Verify direct-mode Basic Auth and record the accepted plaintext-loopback
      limitation.
- [ ] Verify killed-proxy client disconnect and next-use recovery.
- [ ] Verify killed-proxy explicit partial stop.
- [ ] Verify disable/re-enable preserves valid CA identity.
- [ ] Verify rollback removes `tls_proxy`, stops the final schema-3 TLS
      generation, and leaves no complete/pending schema-3 metadata before an old
      MkChad baseline starts.
- [ ] Verify detached persistence in each supported container runtime and mode.

## Audit And Completion Gate

- [ ] A fresh Auditor confirms schema migration and downgrade behavior cannot
      orphan or multiply managed generations.
- [ ] A fresh Auditor confirms direct mode is constrained to the declared
      trusted-host profile and is never presented as multi-user hardening.
- [ ] A fresh Auditor confirms enabled mode retains every archived P0/P1 control.
- [ ] A fresh Auditor confirms partial-pair stop signals only freshly verified
      identities through pidfd under the fence.
- [ ] No policy-reportable P0/P1 findings remain within either profile's stated
      assumptions.
- [ ] The explicit no-password local-user exception remains accurately scoped.
- [ ] No secrets or unrelated untracked files appear in any diff or commit.
- [ ] Required implementation, tests, docs, and runtime evidence are complete.
- [ ] Changed revisions are committed and pushed only after explicit user
      authorization.
