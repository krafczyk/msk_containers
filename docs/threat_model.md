# Threat Model

## Scope

This threat model covers the single persistent OpenCode server described in
`docs/single-opencode-server/SPRINT_SPEC.md`.

The deployment has one intended user operating on a multi-user Linux system.
The system administrator is considered adversarial for availability purposes
and may kill one or more processes in the MkChad/OpenCode process chain at any
time.

The relevant process chain is:

```text
host mkchad launcher
  -> SingularityCE or Apptainer execution
    -> Neovim
      -> detached opencode serve
      -> opencode attach TUI
```

Other MkChad containers belonging to the same user may connect to the same
OpenCode server and run their own attached TUIs.

## Security Boundary

An administrator with root-equivalent access is outside any enforceable
security boundary. Such an administrator can:

- Kill, pause, trace, or replace any user process.
- Read or modify the user's files, state, logs, credentials, and environment.
- Reuse PIDs or launch processes under the user's identity.
- Modify the container image or runtime.
- Intercept or replace loopback traffic.
- Change clocks, hostnames, mounts, namespaces, limits, and kernel behavior.
- Prevent all future process creation.

The implementation cannot guarantee confidentiality, integrity, or
availability against a root-capable administrator. It must not claim otherwise.

The practical objective is graceful detection and recovery from selective
process termination when the administrator still permits the user to run
MkChad, OpenCode, and ordinary user processes afterward.

## Actors

### Intended User

The intended user owns the MkChad configuration, OpenCode state directory,
container processes, and OpenCode sessions. Multiple MkChad processes owned by
this user are cooperative but may race during startup or recovery.

### Other Local Users

Other unprivileged users share the host. They are not trusted with OpenCode
sessions or credentials. Normal Unix process and file permissions are expected
to limit their access, but an unauthenticated loopback HTTP server may still be
reachable by them when host policy permits it.

### Adversarial Administrator

The administrator may deliberately or automatically terminate selected
processes. The administrator may also terminate several related processes at
once. Recovery is possible only while at least one permitted MkChad process can
continue or a new MkChad process can start.

## Assets

### Availability Assets

- Ability to start MkChad without requiring OpenCode.
- Ability to start OpenCode lazily on first use.
- Ability to recover a killed OpenCode server on the next use.
- Stable discovery of the managed server URL.
- Correct coordination between concurrent MkChad processes.
- Ability to inspect live status without causing lifecycle changes.
- Ability to reload one directory instance without disrupting the shared server
  or unrelated directory clients.

### Integrity Assets

- Correct association between persisted state and the managed process.
- Correct server generation and PID tracking.
- Correct current-host state selection.
- Correct project-directory routing.
- Correct current-directory scoping for instance disposal and recreation.
- Correct startup-lock ownership.
- Assurance that stop and cleanup operations do not signal unrelated processes.

### Confidentiality Assets

- OpenCode provider credentials.
- `OPENCODE_SERVER_PASSWORD`, when configured.
- Session content and prompts.
- Project source code and paths.
- Server logs and state metadata.

## Trust Assumptions

- The intended user's processes are mutually cooperative.
- The home directory may be shared across several hosts.
- Hostnames identify state namespaces but are not security credentials.
- SingularityCE/Apptainer uses the host network and PID namespace unless runtime
  configuration says otherwise.
- The administrator may violate every filesystem, process, runtime, and network
  assumption.
- Other unprivileged users cannot normally modify files in mode-0700 directories
  or signal processes owned by the intended user.
- OpenCode's `/global/health` endpoint is the authoritative liveness check for a
  candidate URL, but it does not prove process ownership.
- Persisted PID and command metadata can support ownership validation but cannot
  defeat a root administrator intentionally forging them.

## Security Objectives

### Required Objectives

- MkChad startup remains usable when every OpenCode process is absent.
- Missing or killed processes are detected without trusting stale state.
- Recovery occurs lazily and is bounded.
- Concurrent recovery produces at most one managed server.
- Cleanup never signals a PID solely because it appears in stale state.
- Unknown services on candidate ports are not silently adopted.
- Malformed or missing state does not crash Neovim.
- Repeated process death does not create an unbounded restart loop.
- Diagnostic commands are observational and do not start processes.
- Scoped reload refuses to dispose an instance with active work or interactive
  requests and never starts an inactive shared server.
- Errors clearly identify which process layer is unavailable.
- Secrets are not written into lifecycle state or displayed in diagnostics.

### Best-Effort Objectives

- The detached server survives the Neovim process that launched it.
- Attached TUIs reconnect or are recreated after server replacement.
- opencode.nvim and the invoking attached TUI refresh after a scoped directory
  instance reload while unrelated directory clients remain connected.
- The same persistent port is reused after selective process termination.
- Server logs survive process termination and aid diagnosis.
- A new MkChad process can recover when all previous MkChad processes were
  killed.

### Explicitly Unachievable Objectives

- Preventing an administrator from reading or changing user data.
- Preventing an administrator from killing all processes indefinitely.
- Proving that a PID, executable, health response, or state file was not forged
  by root.
- Preserving in-memory work when every process containing it is killed.
- Guaranteeing uninterrupted availability during process termination.
- Hiding an unauthenticated loopback service from root or other users who can
  access that endpoint.

## Threats And Controls

### T1: OpenCode Server Is Killed

Threat:

The administrator kills `opencode serve` while Neovim and one or more attached
TUIs remain alive.

Impact:

- HTTP and web access stop.
- opencode.nvim's SSE connection closes or times out.
- Attached TUIs temporarily disconnect.
- Persisted state may retain the dead PID and old generation.

Controls:

- Treat `/global/health` as authoritative rather than PID or state presence.
- Clear opencode.nvim connected/status state on SSE failure or heartbeat expiry.
- On the next OpenCode operation, acquire the startup lock and recheck health.
- Replace stale state with a new PID and generation.
- Recycle local attached TUIs when their remembered generation differs.
- Do not restart continuously in the background.

Residual risk:

The administrator can repeatedly kill every replacement. Recovery can also
race with TUI bootstrap because OpenCode has no attached-TUI readiness endpoint.

### T2: Attached TUI Is Killed

Threat:

The administrator kills one `opencode attach` process while the server and
Neovim remain alive.

Impact:

opencode.nvim may still publish TUI commands successfully at the HTTP layer,
but no local TUI is available to consume them.

Controls:

- Track the local Snacks terminal job separately from server health.
- Ensure a valid local attached TUI before every plugin operation.
- Recreate the TUI with the current URL, generation, and `--dir` value.
- Never interpret a successful `/tui/publish` response as proof of delivery.

Residual risk:

OpenCode exposes no TUI presence or readiness API, so a small startup race
remains after recreation.

### T3: Neovim Is Killed

Threat:

The administrator kills one Neovim process while its detached server and other
MkChad processes remain alive.

Impact:

- Unsaved editor state is lost.
- The local attached TUI may be killed or orphaned.
- The shared server should remain available where runtime behavior permits it.

Controls:

- Do not stop the shared server from `ExitPre`.
- Detach the server process from Neovim's event-loop lifetime.
- Let future MkChad processes discover the server through host-specific state
  and live health.
- Treat orphaned TUI cleanup as best effort.

Residual risk:

Some container runtimes or host policies may clean up detached descendants when
the originating container command exits.

### T4: Container Runtime Or Launcher Is Killed

Threat:

The administrator kills the SingularityCE/Apptainer launcher, its process tree,
or the host-side MkChad launcher.

Impact:

Neovim, attached TUI, and detached server may be killed together or in an
implementation-dependent subset.

Controls:

- Keep all state on host-visible persistent storage.
- Make ordinary MkChad startup independent of server presence.
- Let a newly launched MkChad process recover missing server state lazily.
- Namespace state by hostname to prevent recovery against another node's PID.

Residual risk:

No recovery occurs until a new MkChad process starts and an OpenCode operation
is requested.

### T5: Several Processes Are Killed

Threat:

The administrator kills any combination of Neovim, server, TUI, launcher, or
container processes.

Controls:

| Remaining capability | Required behavior |
| --- | --- |
| Neovim remains, server killed | Next OpenCode operation starts a replacement |
| Neovim and server remain, TUI killed | Next OpenCode operation recreates TUI |
| Server remains, all Neovim processes killed | New MkChad reuses healthy server |
| Server and all Neovim processes killed | New MkChad starts normally; first OpenCode use starts replacement |
| Every user process killed | Recovery begins only after the user can start MkChad again |
| Process creation denied | Fail clearly without unbounded retries |

Residual risk:

In-flight prompts, unsaved buffers, and transient TUI state may be lost.

### T6: PID Is Reused

Threat:

The server dies and the kernel assigns its old PID to an unrelated process
before cleanup.

Impact:

An unsafe stop or recovery path could kill an unrelated user process.

Controls:

- Validate hostname, PID type, process existence, command line, and managed port
  before signaling.
- Match the expected state generation before cleanup.
- Refuse to signal when ownership cannot be verified.
- Prefer leaving an unmanaged process over killing an unrelated process.

Residual risk:

Root can forge every validation signal. This control protects against ordinary
PID reuse, not an administrator deliberately impersonating the process.

### T7: Startup Lock Owner Is Killed

Threat:

The administrator kills a MkChad process after it acquires the startup lock but
before it releases the lock or finishes state creation.

Impact:

Other MkChad processes may wait forever or incorrectly assume startup is active.

Controls:

- Store lock-owner PID, hostname, and acquisition time.
- Bound lock wait and server startup durations.
- Reclaim a lock only after validating that its owner is gone or its deadline
  has expired.
- Recheck health before and after lock acquisition.
- Use generation-conditional cleanup.

Residual risk:

Clock manipulation or root-forged owner processes can defeat stale-lock logic.
All waits must still be bounded.

### T8: State Write Is Interrupted

Threat:

The administrator kills the writer during state creation or replacement.

Impact:

State may be missing, stale, or malformed.

Controls:

- Write to a same-directory temporary file.
- Close the file before atomic rename.
- Tolerate missing and malformed state.
- Use live health and lock-protected recovery.
- Ignore or clean abandoned temporary files safely.

Residual risk:

The server may be healthy but temporarily unmanaged if the process starts before
the final state rename and the writer is killed.

### T9: Unknown Process Occupies The Port

Threat:

Another user, an unrelated process, or the administrator occupies port `4096`,
the persisted automatic port, or an explicit `OPENCODE_PORT`.

Impact:

- The managed server cannot bind.
- The integration could connect to the wrong service.
- An unknown OpenCode server could expose or mix another user's sessions.

Controls:

- Require matching managed state before adopting an existing endpoint.
- Validate OpenCode health but do not treat health alone as ownership.
- Fall back to a persisted high port only in automatic mode.
- Fail clearly without fallback when `OPENCODE_PORT` is explicit.
- Bound bind-race retries.

Residual risk:

Root can impersonate a managed endpoint and alter matching state.

### T10: Restart Thrashing

Threat:

The administrator repeatedly kills the server, startup consistently fails, or
the selected port repeatedly races.

Impact:

Unbounded recovery could consume CPU, create excessive logs, or worsen host
policy violations.

Controls:

- Recover only on explicit OpenCode use.
- Bound lock waits, health polls, startup attempts, and port-selection attempts.
- Return actionable failure after the bounded attempt.
- Do not run a continuous watchdog.
- Keep diagnostic commands side-effect free.

Residual risk:

Repeated user actions can still trigger repeated bounded attempts.

### T11: Stale Status Is Presented As Live

Threat:

Cached job IDs, PIDs, URLs, or statusline state remain after selective process
termination.

Impact:

The user may believe the backend is healthy and lose commands sent to a missing
TUI or server.

Controls:

- Clear plugin status on disconnect.
- Make `:OpenCodeInfo` perform a fresh health request.
- Display process state, HTTP health, plugin SSE, and local TUI state as separate
  layers.
- Label attached-TUI API presence as unknown.

Residual risk:

Any displayed status is a point-in-time observation and may change immediately
after the check.

### T12: Local Data Exposure

Threat:

Other local users access the loopback server, lifecycle state, or logs.

Controls:

- Bind only to `127.0.0.1`.
- Use state directories with mode `0700`.
- Use state and log files with mode `0600`.
- Honor existing OpenCode Basic Auth environment variables.
- Never persist passwords in lifecycle state.
- Document that loopback without authentication is not private on a multi-user
  host.

Residual risk:

The selected policy does not generate a password automatically. Other local
users may reach an unauthenticated loopback server, and root can read everything.

### T13: Unsafe Or Misrouted Instance Reload

Threat:

A scoped reload disposes the wrong directory instance, interrupts active model
or tool work, destroys a pending permission/question continuation, leaks Basic
Auth credentials, or restarts the shared backend instead of refreshing one
instance.

Impact:

- In-flight work or interactive requests may be lost.
- Another project's agents, tools, MCP servers, or attached TUI may be disrupted.
- The user may believe changed global configuration was applied when it remains
  cached by the long-running server process.
- A directory-scoped SSE disconnect may leave opencode.nvim permanently stale.

Controls:

- Resolve and route the absolute current Neovim directory at invocation time.
- Require a healthy endpoint that matches managed state before disposal.
- Query directory-routed session status, permissions, and questions, and refuse
  reload while work or an interactive request is active.
- Do not provide a force/bang override in this sprint.
- Authenticate `POST /instance/dispose` without putting credentials in argv,
  logs, notifications, or state.
- Recreate and validate the same directory through `/path` before reporting
  success.
- Treat the expected instance-dispose event as a bounded reconnect transition,
  then refresh opencode.nvim and only the invoking Neovim's attached TUI.
- Verify shared server PID, generation, URL, and port remain unchanged and that
  another directory stays usable.
- State explicitly that directory reload does not guarantee refreshing
  process-cached global configuration.

Residual risk:

OpenCode does not provide a single atomic "idle and dispose" transaction, so
work can begin after the preflight checks and before disposal. The implementation
must keep this interval short, handle conflict/failure without restarting the
shared backend, and document that a full process restart remains necessary for
some global configuration. OpenCode also cannot prove attached-TUI readiness.

## Process-Kill Test Matrix

| Test | Processes killed | Expected outcome |
| --- | --- | --- |
| K1 | Shared OpenCode server | Next use creates a new generation |
| K2 | One attached TUI | Next use recreates that Neovim's TUI |
| K3 | One Neovim | Server remains where runtime permits; other clients continue |
| K4 | Startup lock owner | Another client reclaims stale lock after bounded wait |
| K5 | State writer before rename | State is missing/old but readable; next use recovers |
| K6 | Server and attached TUI | Next use starts server, then recreates TUI |
| K7 | Server and originating Neovim | Another/new MkChad starts replacement on use |
| K8 | All MkChad/OpenCode processes | New MkChad starts without OpenCode; first use recovers |
| K9 | Replacement server repeatedly | Each user action makes one bounded attempt and reports failure |
| K10 | Server after local binary update | Info reports outage/mismatch; next generation uses current binary |

## Audit Focus

Audits should prioritize:

- Accidental signaling of unrelated processes.
- Unbounded restart, polling, or lock loops.
- Incorrect adoption of unknown endpoints.
- Secret disclosure in state, logs, process arguments, or diagnostics.
- False healthy status based on stale state.
- Failure to recover after selective process termination.
- Cross-host state or PID confusion on shared home directories.
- Races that create multiple managed servers.
- Directory-routing failures that send commands to the wrong project TUI.
- Scoped reloads that interrupt active work, dispose the wrong directory, expose
  credentials, restart the shared backend, or strand clients after SSE closure.
- Changes that make MkChad startup depend on OpenCode availability.

Severity and remediation expectations are defined in `docs/audit_policy.md`.

## Residual Risk Acceptance

The design accepts that an adversarial administrator can always win. A complete
denial of process creation, repeated process termination, filesystem tampering,
or root-level endpoint impersonation cannot be resolved in application code.

The sprint is successful when selective process death produces bounded,
observable failure and reliable next-use recovery under otherwise functional
user permissions. It is not successful if it attempts to evade administrator
controls, loops indefinitely, kills unrelated processes, or reports stale state
as healthy.
