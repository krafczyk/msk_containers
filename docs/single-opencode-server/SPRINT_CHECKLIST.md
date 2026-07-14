# Single Persistent OpenCode Server Sprint Checklist

## Decisions

- [x] Use one lazy detached proxy/backend pair per user and host.
- [x] Use stable host-CA-authenticated HTTPS on the public loopback port.
- [x] Keep OpenCode on a distinct automatic high internal loopback port.
- [x] Preserve `OPENCODE_PORT`/preferred `4096` as public-port policy.
- [x] Prove backend ownership on the exact established connection before client
      bytes are read/forwarded.
- [x] Use Java 21 `SSLServerSocket`, PKCS12, keytool, and virtual threads; do not
      add OpenSSL.
- [x] Preserve Basic Auth rather than generating OpenCode credentials.
- [x] Warn that TLS authenticates the server, not clients, and that both
      loopback endpoints are locally accessible without a user-supplied
      `OPENCODE_SERVER_PASSWORD`.
- [x] Preserve renewable lifecycle locking from MkChad `cdf5499`.
- [x] Preserve bounded initial SSE connection behavior from opencode.nvim
      `e04b7a7`.
- [x] Treat schema 1 as deployed legacy state and migrate under lock without an
      authenticated HTTP probe.

## Worktree Safety

- [x] Read all in-scope `AGENTS.md` and governing documents before edits.
- [x] Restrict implementation to the three sprint repositories.
- [x] Preserve untracked MkChad `lazy-lock.json`.
- [x] Preserve untracked msk_containers JDT archive.
- [x] Use only `/tmp/opencode/...` for runtime fixtures.
- [x] Do not inspect real credentials or session data.
- [x] Do not change Dockerfiles; existing Java/keytool support was sufficient.
- [x] Commit and push only with explicit user authorization.

## Certificate Material

- [x] Generate stable EC CA and `127.0.0.1` leaf with keytool/PKCS12.
- [x] Generate a random mode-`0600` password file.
- [x] Use keytool `-storepass:file`; keep password content out of argv.
- [x] Keep state root and TLS directory `0700`.
- [x] Keep CA PEM, stores, leaf evidence, password, state, and logs `0600`.
- [x] Validate/reuse material under lock and regenerate only absent/invalid
      material.
- [x] Atomically isolate invalid material and publish a complete replacement.
- [x] Keep certificate identity stable across ordinary process recovery.
- [x] Persist CA path and certificate identity, not password/key content.

## Java TLS Proxy

- [x] Load PKCS12 directly into `SSLContext`/`SSLServerSocket`.
- [x] Bind loopback only and permit TLS 1.2/1.3.
- [x] Disable ALPN/HTTP/2 negotiation.
- [x] Bound concurrent virtual-thread handlers.
- [x] Stream proc TCP tables with line/entry/byte/time bounds and separately
      bound concurrent proof scans; require one valid family-specific first-line
      header per table, fully validate all state-dependent row columns and exact
      family address widths, and reject partial or structurally incomplete scans.
- [x] Complete TLS before backend connection and application reads.
- [x] Revalidate backend PID start and boot identity before connecting.
- [x] Send only fixed unauthenticated keep-alive `GET /global/health`.
- [x] Bound preflight timeout, headers, and body.
- [x] Accept only bounded `200`/`401` with explicit `Content-Length`.
- [x] Reject malformed, oversized, transfer-encoded/chunked, close-delimited,
      or timed-out preflight responses.
- [x] Map the exact reverse ESTABLISHED tuple in procfs.
- [x] Require exactly one tuple and its inode under expected backend PID fds.
- [x] Pump raw bytes bidirectionally only on that same socket after proof.
- [x] Never reconnect a client stream.
- [x] Monitor process/start/boot/inode ownership while pumping and fail closed.
- [x] Fail closed when Linux procfs evidence is unavailable.

## Schema 2 And Lifecycle

- [x] Record one generation with stable HTTPS URL/CA/certificate identity.
- [x] Record exact proxy PID/start/executable/argv/public port/log.
- [x] Record exact backend PID/start/executable/argv/internal port/version/log.
- [x] Record immutable runtime and launch executable device/inode identities for
      both roles, plus Java source identity for the proxy.
- [x] Record host boot ID and public port source.
- [x] Keep secrets and sensitive file content out of state.
- [x] Use fsynced same-directory temporary writes and atomic rename.
- [x] Use mode-`0600` transient pending metadata for interrupted startup cleanup.
- [x] Publish complete state only after both listeners and pinned health pass.
- [x] Preserve lock lease renewal, owner/inode checks, stale reclaim, and bounded
      waiting.
- [x] Select public and internal ports under lock with bounded attempts.
- [x] Launch backend first and prove exact process/listener ownership.
- [x] Launch proxy with immutable backend PID/start/boot/port and prove listener.
- [x] Prove every Lua lifecycle listener with a bounded streaming, exact-header,
      full-row, complete-two-table scanner and exact cross-table uniqueness
      before checking `/proc/<pid>/fd` inode ownership.
- [x] Require pinned authenticated HTTPS health before publication.
- [x] Stop proxy first, then exact verified backend.
- [x] Replace both when either process/listener/identity/health fails.
- [x] Keep CA and valid public port across normal recovery.
- [x] Retain no `ExitPre` shared-pair stop.
- [x] Recycle TUI on process, directory, URL, generation, or CA identity change.
- [x] Keep all retries, waits, cleanup, and escalation bounded.

## Legacy And Unsafe State

- [x] Label schema 1 as legacy in diagnostics.
- [x] Never probe a schema-1 HTTP URL or give it to opencode.nvim.
- [x] Stop only an exact verified schema-1 process before migration.
- [x] Allow explicit stop to remove verified/dead legacy state without HTTP.
- [x] Treat missing state as inactive.
- [x] Diagnose malformed state without probing it; replace only under lock.
- [x] Refuse to overwrite unsupported future schema.
- [x] Refuse to signal live unverifiable PIDs.
- [x] Treat pre-inode schema-2/pending metadata as malformed and require bounded
      replacement or trusted manual process accounting.

## Clients

- [x] Supply MkChad curl `cacert` through protected stdin config.
- [x] Keep MkChad Basic Auth and JSON bodies in protected stdin config.
- [x] Preserve request-time current-directory routing and HTTP/1.1.
- [x] Add opencode.nvim optional `server.ca_cert` path/resolver.
- [x] Resolve and supply CA for every REST and SSE request.
- [x] Keep opencode.nvim CA, credentials, and bodies out of curl argv.
- [x] Preserve opencode.nvim request-time directory headers.
- [x] Give local attach `NODE_EXTRA_CA_CERTS=<state ca.pem>` in child options.
- [x] Preserve attach HTTPS URL, `--dir`, auth inheritance, and terminal layout.
- [x] Preserve scoped reload and validate both PIDs, generation, URL/port, and CA
      identity across reload.
- [x] Keep info observational and refuse network probes for untrusted state.

## Focused Verification Completed

- [x] Java source compiles with `javac --release 21`.
- [x] Valid certificate material remains byte-stable and corrupted CA material
      regenerates as a new private mode-correct identity.
- [x] Java proxy passes pinned authenticated HTTP.
- [x] Java proxy passes long-lived SSE.
- [x] Curl fails without CA and succeeds with CA.
- [x] Installed OpenCode 1.17.18 attach reaches the fixture only with
      `NODE_EXTRA_CA_CERTS` supplied.
- [x] Installed OpenCode 1.17.18 starts with fixture Basic Auth, accepts the
      proxy's unauthenticated `401` keep-alive preflight, and passes pinned
      authenticated health.
- [x] Replacement-before-proof receives only fixed preflight and no client
      Authorization/body.
- [x] Replacement-after-backend-death receives zero bytes.
- [x] Inode/expected-PID mismatch fails before forwarding client bytes.
- [x] PID-start and boot-ID mismatch fail before listening.
- [x] Concurrent proxy clients complete through bounded handlers.
- [x] Concurrent startup converges on one generation/proxy/backend pair.
- [x] Originating Neovim workers exit while detached pinned health remains live.
- [x] Proxy-only death replaces both and preserves CA identity.
- [x] Backend-only death replaces both and preserves CA identity.
- [x] TUI death recreates the local attach.
- [x] Automatic public conflict selects one persisted fallback.
- [x] Explicit public conflict fails without fallback.
- [x] Separate internal bind/listener takeover is rejected before proxy/client
      traffic.
- [x] Legacy migration and diagnostics pass without HTTP probing.
- [x] Malformed state info/recovery remains bounded.
- [x] Auth `401` preserves the existing generation.
- [x] Info remains lazy.
- [x] Reload success, refusal, and reconnect rejection remain bounded while
      preserving the pair.
- [x] Renewable lease survives beyond the original lease and dead owner reclaim
      remains bounded.
- [x] Existing opencode.nvim curl-security and SSE-connect tests pass.
- [x] New opencode.nvim pinned REST/SSE test verifies request-time CA,
      credentials, body, and directory behavior.
- [x] Wrong and missing private CA fail closed; REST/SSE CA, credentials, and
      body stay out of argv.
- [x] Table-driven complete/pending malformed-state info/ensure/reload/stop
      checks remain bounded and do not signal or request.
- [x] Atomic native executable replacement preserves original-process ownership
      through authoritative `/proc/<pid>/exe`, including ` (deleted)`, while a
      same-argv native process on another inode is refused.
- [x] `SPOS-AUD-P1-006` interpreted-launch and Java-source identities are
      compared at every generic process identity gate; original interpreted
      identity passes, same-argv/same-runtime replacement and Java source
      replacement fail closed, and stop does not signal unverifiable processes.
- [x] Synthetic large proc tables pass under a constrained heap; malformed,
      truncated, oversized, and overlong tables fail closed, and proof scans
      remain separately concurrency-bounded.
- [x] `SPOS-AUD-P1-005` constrained-heap empty, headerless, repeated-header,
      malformed-header, data-before-header, and match-plus-incomplete-other-table
      cases fail closed; production IPv4/IPv6 proc headers pass integration.
- [x] Auditor pass 6 fully validates Java and Lua proc row fields, exact
      family widths and state-dependent column counts; Java malformed fields
      4-16, wrong-family, missing/extra, truncation, ambiguity, complete-other-
      table, and constrained-heap cases pass, while Lua passes >8 KiB,
      malformed ignored-field, wrong-family, header/empty/truncation/duplicate,
      incomplete-other-table, and controlled production-listener cases.
- [x] No-password startup/diagnostic warning and public/direct-internal invalid
      credential `401` checks pass.
- [x] Focused MkChad Lua and Python tests pass.
- [x] `git diff --check` passes in all three repositories.

## Explicit P1 Exception

- [x] `SPOS-AUD-P1-004` is explicitly deferred under the exception in
      `docs/audit_policy.md`. No generated or forced password was introduced.
- [x] Decision-maker/user accepted the policy gate on 2026-07-14 for this
      deployment scope, acknowledging that untrusted same-host users can access
      no-password deployments. The risk remains unresolved/conditional and was
      not code-fixed; TLS/CA is not client access control.
- [x] The bounded operational workaround is to set a strong existing
      `OPENCODE_SERVER_PASSWORD` before first use, or set it and stop/restart an
      existing pair.
- [ ] `SPOS-FOLLOWUP-AUTH-001` resolves or re-accepts the local-user access risk
      at its documented reevaluation trigger.

## Runtime And Release Evidence Still Open

- [ ] Verify installed OpenCode 1.17.20 attach with `NODE_EXTRA_CA_CERTS` (local
      installed runtime is 1.17.18).
- [ ] Verify real OpenCode 1.17.20 authenticated API/SSE and web UI, beyond the
      exact fixtures and local 1.17.18 lifecycle check.
- [ ] Manually import the host CA into a supported browser and verify the stable
      HTTPS web UI.
- [ ] Verify detached pair persistence and recovery on a SingularityCE target.
- [ ] Verify detached pair persistence and recovery on an Apptainer target.
- [ ] Build/install x86_64 container baseline and verify 1.17.20.
- [ ] Build/install aarch64 container baseline and verify 1.17.20.
- [ ] Verify mounted npm runtime override in supported containers.
- [ ] Run LuaLS and StyLua in the normal CI toolchain when available locally/CI.
- [x] Publish opencode.nvim CA support as `a383638` and update the MkChad
      immutable pin to that exact revision.
- [ ] Publish MkChad `99bf651` and the final coordination-document revision
      after explicit push authorization.

## Evidence

| Date | Area | Evidence |
| --- | --- | --- |
| 2026-07-14 | Baseline | MkChad started this redesign at `cdf5499`; opencode.nvim at `e04b7a7`; msk_containers at `7cde376`. |
| 2026-07-14 | Proxy | `python3 tests/tls_proxy_integration.py` passed HTTP, SSE, curl CA rejection/success, installed attach CA, concurrent clients, replacement, preflight parser, inode/PID, start, and boot checks. `MkChadTlsProxyTupleTest` passed exact, missing, and ambiguous tuple cases. |
| 2026-07-14 | Local OpenCode | Installed 1.17.18 passed a real Basic-Auth lifecycle: unauthenticated proxy preflight returned reusable `401`, pinned authenticated health succeeded, and exact pair cleanup completed. |
| 2026-07-14 | Lifecycle | Isolated headless lifecycle passed schema 2, permissions, auth 401, TUI death, proxy/backend death, stable CA, explicit conflict, malformed recovery, and legacy migration. |
| 2026-07-14 | Concurrency | `python3 tests/concurrent_startup.py` passed two-process startup, one generation/pair, automatic fallback, origin exit persistence, pinned health, and cleanup. |
| 2026-07-14 | Reload | Isolated headless reload passed inactive laziness, routed preflights/dispose/path, pair preservation, reconnect rejection, and busy refusal. |
| 2026-07-14 | Lock | Existing cross-process lease test passed with renewal and dead-owner reclaim. |
| 2026-07-14 | Environment | Java/keytool 25 can compile/run Java 21 source; local OpenCode is 1.17.18. SingularityCE, Apptainer, container builders, and StyLua are unavailable. LuaLS ran but its CI library/runtime metadata was not initialized and it emitted 828 repository-wide undefined-global/type warnings, so it is not clean static evidence. |
| 2026-07-14 | Auditor pass 4 repair | Serial MkChad lifecycle/race/lease/reload/certificate/state/executable/concurrent-startup/proxy tests passed. Java `--release 21 -Xlint:all -Werror`, tuple/truncation/malformed proof, and `-Xmx24m` large/concurrent table tests passed. opencode.nvim protected curl, request-time REST/SSE CA, wrong/missing CA, and SSE-connect tests passed. `SPOS-AUD-P1-004` remains the explicit exception above; publication/pin remains open. |
| 2026-07-14 | `SPOS-AUD-P1-004` acceptance | Decision-maker/user explicitly accepted the policy gate for this deployment scope, acknowledged untrusted same-host access when no password is supplied, and agreed to set a strong password before first use or stop/set/restart. Risk remains unresolved/conditional and not code-fixed; TLS/CA is not client access control. |
| 2026-07-14 | Auditor pass 5 repair | Proc proof requires complete family-specific headers and complete bounded scans of both tables before exact cross-table uniqueness. Generic process identity compares interpreted launch and Java source inodes while retaining native `/proc/<pid>/exe` authority. Constrained-heap Java proof, proxy integration, executable/lifecycle/state/reload/lease/startup, opencode.nvim curl/TLS/security/SSE, and diff checks were rerun as recorded in the repair report. |
| 2026-07-14 | Auditor pass 6 `SPOS-AUD-P1-005` repair | Java and Lua now validate exact family-specific headers, all required proc row fields, 17-column ordinary and 12-column `SYN_RECV`/`TIME_WAIT` forms, complete newline-terminated tcp/tcp6 scans, and exact cross-table uniqueness. Java lint/compile, tuple/header/truncation/malformed/large/concurrency, proxy integration, serial MkChad lifecycle/startup/reload/lease/state/identity/certificate/concurrent-startup, Lua >8 KiB and controlled-listener proof, and opencode.nvim TLS/security/SSE tests passed. Runtime/container/browser and publication/pin gates remain open. |
| 2026-07-14 | Auditor pass 7 | Reported no remaining code P0/P1. `SPOS-AUD-P1-004` remains the explicitly accepted conditional exception. The only code-release gate was immutable fork publication and pinning. |
| 2026-07-14 | Fork publication | Published opencode.nvim CA support as `a38363837c564a14f50a3a72f58f7df8dbeff3ad`; MkChad `99bf651` pins `a383638`. A fresh remote fork clone passed curl-security and SSE tests, and the cross-repository TLS integration passed with `OPENCODE_NVIM_ROOT` set to that clean clone. |

## Completion Gate

- [x] `SPOS-AUD-P0-003` implementation and clean-fork fixture evidence are
      complete in committed revisions.
- [x] No known P0/P1 remains in the implemented same-connection relay path;
      the `SPOS-AUD-P1-004` policy gate is accepted for this deployment scope,
      but its risk remains unresolved/conditional outside the code-fixed claim.
- [x] No secrets or unrelated untracked files were added to diffs.
- [ ] Runtime/container/browser gates above are complete.
- [x] The reviewed opencode.nvim revision is published and the committed MkChad
      pin references it exactly.
- [ ] MkChad and final coordination-document revisions are published.
