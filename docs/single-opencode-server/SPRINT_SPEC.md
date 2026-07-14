# Single Persistent OpenCode Server Sprint Specification

## Document Status

| Field | Value |
| --- | --- |
| Status | Proposed |
| Scope | `msk_containers`, MkChad configuration, and `krafczyk/opencode.nvim` |
| Primary platform | SingularityCE and Apptainer with their default host network and PID behavior |
| OpenCode baseline | `opencode-ai@1.17.20` on x86_64 and aarch64 |
| OpenCode endpoint | Loopback HTTP with a stable, host-specific port |
| Authentication | Use existing `OPENCODE_SERVER_PASSWORD` and `OPENCODE_SERVER_USERNAME` only |
| State root | `${XDG_STATE_HOME:-$HOME/.local/state}/mkchad/opencode/<hostname>` |

## Summary

Replace MkChad's per-Neovim OpenCode backend with one lazily created, detached
OpenCode server per user and host. Every MkChad process will reuse that backend,
while retaining its own directory-scoped `opencode attach` TUI.

Starting MkChad must not start OpenCode. The first operation that needs OpenCode
will ensure that the shared backend is healthy, start it when necessary, attach a
TUI for the current Neovim directory, and then continue the requested operation.
If the server is killed, the next OpenCode operation will recover it.

Persistent state is coordination and diagnostic data, not proof of liveness.
Every liveness decision must use OpenCode's live `/global/health` endpoint.

## Motivation

The current integration creates an OpenCode web server for each MkChad process.
Each process chooses a random high port and stores process state only in Lua
variables owned by that Neovim process. This has several undesirable effects:

- Every MkChad process consumes resources for a separate backend.
- Web URLs change from one MkChad process to another.
- Sessions cannot be reached consistently from one web endpoint.
- Another MkChad process cannot discover or manage the first process's backend.
- `:OpenCodeInfo` reports only the job launched by the current Neovim process.
- Closing the Neovim process stops its backend through an `ExitPre` callback.
- A backend killed by a headnode policy cannot be recovered by another existing
  MkChad process using the current in-memory process tracking.

OpenCode supports multiple directory-scoped instances on one server when clients
send `x-opencode-directory` or `?directory=...`. The official TUI also supports
`opencode attach URL --dir PATH`. These capabilities make one shared backend
feasible, provided that opencode.nvim sends the current Neovim directory with
every request.

## Goals

- Start no OpenCode process merely because MkChad starts.
- Maintain at most one managed OpenCode backend per user and host.
- Start the backend lazily on the first OpenCode operation.
- Keep the backend alive after its originating Neovim process exits.
- Reuse the backend from later MkChad processes.
- Recover a killed backend on the next OpenCode operation.
- Preserve the existing lazy Snacks terminal workflow.
- Attach one directory-scoped TUI for each MkChad process that uses OpenCode.
- Route opencode.nvim requests using the current Neovim working directory.
- Give the web endpoint a stable port for the lifetime of host-specific state.
- Prefer port `4096` when no port is explicitly configured or already persisted.
- Provide fresh, truthful diagnostics through `:OpenCodeInfo`.
- Reload one directory's server-side OpenCode configuration without restarting
  the shared backend through `:OpenCodeReload`.
- Preserve the existing mounted npm prefix and live OpenCode update behavior.
- Update supported container baselines to the current OpenCode release.

## Non-Goals

- Do not start a Singularity or Apptainer instance.
- Do not run Singularity recursively from inside the MkChad container.
- Do not start the backend at login, boot, or ordinary MkChad startup.
- Do not add systemd, cron, or a continuously running host watchdog.
- Do not automatically restart a healthy server merely because a newer local
  OpenCode executable has been installed.
- Do not automatically generate or persist an OpenCode server password.
- Do not expose the server on non-loopback interfaces.
- Do not change OpenCode's session storage format.
- Do not attempt to prove attached-TUI presence through the OpenCode HTTP API;
  no such presence endpoint exists.
- Do not solve routing between multiple attached TUIs using the same directory.
- Do not present a directory-instance reload as a reload of process-cached global
  OpenCode configuration. Global configuration changes may still require an
  explicit shared-server stop and restart.
- Do not modify the ppc64le OpenCode baseline in this sprint.
- Do not commit or overwrite unrelated worktree changes.

## Repositories And Ownership

### Container Repository

Repository: `/data1/matthew/Projects/msk_containers`

Responsibilities:

- Update the x86_64 OpenCode baseline to `1.17.20`.
- Update the aarch64 OpenCode baseline to `1.17.20`.
- Leave ppc64le unchanged.
- Retain the architecture-specific mounted npm prefix that can override the
  image baseline at runtime.
- Retain the current mount detection and MkChad container launch behavior.

Expected files:

- `nvim/x86/nvim_container_x86.dockerfile`
- `nvim/aarch64/nvim_container_aarch64.dockerfile`

### MkChad Configuration Repository

Repository: `/home/matthew/.config/mkchad`

Responsibilities:

- Implement persistent host-scoped server state.
- Implement the detached backend process lifecycle.
- Implement port selection and startup coordination.
- Continue managing directory-scoped attached TUIs with Snacks.
- Enhance `:OpenCodeInfo` with live diagnostics.
- Remove automatic server shutdown on Neovim exit.
- Configure the custom opencode.nvim fork and its lifecycle hook.

Expected files:

- `lua/configs/opencode.lua`
- `lua/plugins/init.lua`
- `lazy-lock.json` only if explicitly accepted as part of dependency locking;
  it is currently an untracked user file and must otherwise remain untouched.

### opencode.nvim Fork

Repository: `https://github.com/krafczyk/opencode.nvim`

Local checkout: `/data1/matthew/Projects/opencode.nvim`

Responsibilities:

- Apply the directory-routing behavior from upstream PR #239 on top of current
  main, rather than pinning the stale PR head.
- Provide an asynchronous pre-operation lifecycle hook that MkChad can use to
  ensure its backend and local attached TUI.
- Clear stale connection/status state after an ungraceful server disconnect.
- Document the fork-specific behavior and the upstream dependency.

Expected files:

- `lua/opencode/config.lua`
- `lua/opencode/server/init.lua`
- `lua/opencode/server/discovery/init.lua`
- `lua/opencode/events/status.lua`
- `plugin/events/status.lua` if a new disconnect event is introduced
- `README.md` or a focused fork-maintenance note

## Current Behavior

The current MkChad OpenCode configuration does the following:

- Chooses a random available port between `49152` and `65535`, unless
  `OPENCODE_PORT` is set.
- Starts `opencode web` as a Neovim-owned job.
- Stores the job ID and PID only in the current Lua process.
- Tests readiness using a TCP connection rather than OpenCode health data.
- Starts `opencode attach URL` without an explicit directory.
- Stops the server and closes the terminal through `ExitPre`.
- Reports `:OpenCodeInfo` from cached in-process job state.
- Pins upstream `nickjvandyke/opencode.nvim` using a released version.

## Target Architecture

### Process Topology

```text
Host
|
+-- MkChad container A
|   |-- Neovim A
|   |-- detached opencode serve (only if A wins initial startup)
|   `-- opencode attach --dir /project/a
|
+-- MkChad container B
|   |-- Neovim B
|   `-- opencode attach --dir /project/b
|
`-- 127.0.0.1:<persistent-port>
    `-- shared OpenCode HTTP API and web UI
```

The detached server inherits the mount namespace, environment, OpenCode
configuration, and executable path of the MkChad container that creates it. The
existing MkChad wrapper already establishes the required mounts. Because the
current launch does not request a private network or PID namespace, the server's
loopback endpoint and PID are shared with other default MkChad executions on the
same host.

### Laziness Contract

The following operations must not start the server:

- Launching MkChad.
- Loading the opencode.nvim plugin.
- Running `:checkhealth opencode`.
- Running `:OpenCodeInfo`.
- Running `:OpenCodeReload` when no healthy managed server exists.
- Viewing a statusline component.

The following operations may ensure or start the server:

- `require("opencode").ask(...)`
- `require("opencode").select(...)`
- `require("opencode").prompt(...)`
- `require("opencode").command(...)`
- Executing an opencode.nvim operator.
- `:OpenCodeStart`
- `:Opencode start`
- Toggling a TUI when no usable backend exists.

### Backend Command

The managed command is:

```text
opencode serve --hostname 127.0.0.1 --port <port>
```

`serve` is preferred over `web` because the server exposes the same web UI while
avoiding an automatic browser-open attempt. The command must run with `$HOME` as
its neutral process working directory. Individual requests and attached TUIs
select their own project directories.

### Detachment

Launch the backend with `vim.uv.spawn` using detached process behavior:

- Set `detached = true`.
- Set `cwd` to `$HOME`.
- Connect stdin to `/dev/null`.
- Append stdout and stderr to the mode-0600 server log.
- Record the returned PID.
- Unreference and close the local process handle correctly so Neovim shutdown
  does not wait for the backend.
- Do not register an `ExitPre` handler that stops the shared server.

This is intentionally a best-effort persistent process rather than a formal
service manager. Persistence after the originating Neovim exits must be tested
on each supported SingularityCE and Apptainer environment. If a runtime or site
policy kills the process, next-use recovery remains mandatory.

## Persistent State Model

### State Directory

Use Neovim's state root and namespace it by hostname:

```text
<stdpath("state")>/opencode/<sanitized-hostname>
```

With `NVIM_APPNAME=mkchad`, the normal expansion is:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/mkchad/opencode/<hostname>
```

Hostname namespacing is required because `$HOME` and XDG directories may be
shared by several cluster nodes.

Directory permissions must be `0700`. State and log files must be `0600`.

### State Files

| Path | Purpose |
| --- | --- |
| `state.json` | Current managed server metadata |
| `server.log` | Combined append-only server stdout and stderr |
| `startup.lock/` | Atomic cross-Neovim startup lock directory |

### State Schema

The initial schema should contain at least:

```json
{
  "schema": 1,
  "hostname": "headnode.example",
  "pid": 12345,
  "generation": "<unique-start-token>",
  "host": "127.0.0.1",
  "port": 4096,
  "url": "http://127.0.0.1:4096",
  "started_at": "2026-07-14T12:34:56Z",
  "cwd": "/home/user",
  "log": "/home/user/.local/state/mkchad/opencode/headnode.example/server.log",
  "executable": "/resolved/path/to/opencode",
  "process_executable": "/resolved/runtime/executable",
  "argv": ["/resolved/runtime/executable", "serve", "--hostname", "127.0.0.1", "--port", "4096"],
  "local_version": "1.17.20"
}
```

Do not store `OPENCODE_SERVER_PASSWORD`, provider credentials, tokens, or other
secrets in this file.

### Atomic Writes

Write JSON to a mode-0600 temporary file in the same directory, flush/close it,
and rename it over `state.json`. Readers must tolerate missing, malformed, or
newer-schema state and report a useful diagnostic rather than crashing MkChad.

### Process Generation

Every backend launch receives a unique generation token. Each Neovim process
records the generation associated with its local attached TUI. If shared state
reports a different generation, the local TUI must be recycled before the next
operation so it performs a fresh bootstrap against the replacement server.

## Source Of Truth Rules

Use these signals in this order:

| Signal | Meaning |
| --- | --- |
| Successful `/global/health` response | A compatible OpenCode HTTP server is live at the URL |
| Matching managed state and valid PID | Useful ownership/control evidence, but not liveness |
| Occupied TCP port | Something is listening; it may not be OpenCode or may belong to another user |
| Existing state file | Historical metadata only |
| opencode.nvim statusline cache | Presentation state only |

No code path may report "running" based only on a PID, job ID, state file, or
open TCP port.

## Port Selection

### Explicit Port

If `OPENCODE_PORT` is set and non-empty:

- Parse it as an integer from `1` through `65535`.
- Use exactly that port.
- Do not select a fallback port.
- If a managed healthy server already uses that port, reuse it.
- If another managed server is healthy on a different persisted port, fail and
  instruct the user to stop it before changing the explicit port.
- If the port is occupied by an unknown or incompatible process, fail clearly.
- If startup loses a bind race, fail clearly and include the port and log path.

### Automatic Port

If `OPENCODE_PORT` is absent:

- Reuse a healthy managed server from host-specific state.
- Reuse the persisted port when the prior managed server is down and the port is
  available.
- Prefer port `4096` when no valid state exists.
- If `4096` is occupied by an unknown process, choose an available high port.
- Persist the fallback port so later MkChad processes use the same endpoint.
- If a bind race occurs during automatic selection, retry with another port
  within a bounded attempt count.

An unknown OpenCode server responding on a candidate port must not be adopted
without matching managed state. This prevents accidental connection to another
user's loopback service on a shared host.

## Health Probing

Probe:

```text
GET <url>/global/health
```

Requirements:

- Use a short bounded connection and total timeout.
- Apply Basic Auth from the existing `OPENCODE_SERVER_USERNAME` and
  `OPENCODE_SERVER_PASSWORD` environment variables when configured.
- Require successful HTTP status and valid JSON.
- Require `healthy == true`.
- Capture the server-reported version.
- Distinguish connection failure, timeout, unauthorized response, invalid JSON,
  and an unhealthy response in diagnostics.
- Record latency for `:OpenCodeInfo`.

## Startup Coordination

### Locking

Use atomic creation of `startup.lock/` as the cross-process lock. The lock owner
must write owner metadata containing its PID, hostname, and acquisition time.

The lock algorithm is:

1. Probe the selected endpoint before attempting the lock.
2. Return immediately if the managed server is healthy.
3. Attempt to create `startup.lock/` atomically.
4. If acquisition fails, poll managed state and health for a bounded interval.
5. Return when the winner's server becomes healthy.
6. Treat the lock as stale only when its owner is gone or its bounded startup
   deadline has expired.
7. Remove stale lock data and retry acquisition once.
8. Always release a lock owned by the current process on success or failure.

Lock cleanup must verify ownership before removing the lock so one contender
cannot remove another contender's active lock.

### Startup Sequence

The lock winner must:

1. Re-read state and re-probe health.
2. Reject explicit-port conflicts.
3. Validate or discard stale state.
4. Resolve the OpenCode executable and local version.
5. Select the port according to the port policy.
6. Create a new generation token.
7. Open `/dev/null` and the append-only log descriptors.
8. Spawn the detached `opencode serve` process.
9. Atomically write initial state with the returned PID and generation.
10. Poll `/global/health` until success or timeout.
11. Update state with the server-reported version if desired.
12. Return the URL and generation to the caller.
13. On failure, include the server log path in the error.
14. Remove state only when it still describes the failed generation.
15. Release the startup lock.

### Waiting Contenders

Processes that do not own the startup lock must not launch their own backend.
They must poll the winner's state and health. They may retry ownership only after
the lock is proven stale or the startup deadline expires.

## Stale State And PID Safety

Before signaling a PID from `state.json`:

- Confirm the state hostname matches the current host.
- Confirm the PID is a positive integer.
- Confirm the PID still exists.
- When `/proc/<pid>/cmdline` is readable, confirm it is the expected OpenCode
  serve process and includes the managed port.
- Refuse to kill an unverifiable reused PID.
- Prefer leaking an unmanageable process over killing an unrelated process.

When state describes a dead process and health is down, remove or replace the
state under the startup lock. When health is up but process ownership cannot be
verified, report the server as live but unmanaged and do not stop it.

## opencode.nvim Fork Requirements

### Directory Header

Apply the behavior from upstream PR #239 to the current fork main:

```text
x-opencode-directory: <current Neovim cwd>
```

Add it to every request made by `Server:curl`, including health-independent
instance requests, `/event`, and `/tui/publish`.

The implementation must:

- Resolve `vim.fn.getcwd()` at request time.
- Skip the header only when the directory is unavailable or empty.
- Preserve existing auth and content headers.
- Include a comment referencing upstream PR #239.
- Note that the patch should be revisited when upstream merges or supersedes it.

MkChad must always attach its TUI with the same directory, making the PR's
directory assumption intentional for this integration.

### Pre-Operation Ensure Hook

Add an optional asynchronous server option, tentatively named `server.ensure`:

```lua
---@field ensure? fun(callback: fun(ok: boolean, err?: string))
```

`discovery.get()` must invoke it before using an existing connection, resolving
a configured URL, discovering local processes, or invoking an OpenCode action.

Behavior:

- No hook means unchanged upstream behavior.
- A successful callback continues normal discovery and connection.
- A failed callback rejects the operation with its error.
- Exceptions thrown by the hook become a useful rejection.
- The hook must be safe to call before every public OpenCode operation.
- MkChad will configure `server.start = false` because `ensure` owns lifecycle.

### Disconnect State

When the server's SSE curl exits or the heartbeat deadline expires:

- Clear `Server.connected` as today.
- Clear stale statusline URL and state.
- Expose a disconnected state immediately to status presentation code.
- Do not perform background reconnection.
- Let the next operation invoke `server.ensure` and reconnect lazily.

### Fork Maintenance Note

Document:

- The upstream base revision or release.
- The carried PR #239 behavior.
- The fork-specific `server.ensure` hook.
- The condition for removing each divergence.
- That OpenCode v2 may supersede parts of this architecture.

## MkChad Lifecycle Requirements

### Ensure Operation

MkChad's implementation of the fork hook must:

1. Resolve current host-specific state.
2. Resolve the current Neovim directory.
3. Probe a persisted or explicit managed endpoint.
4. Start a detached server when health is down.
5. Wait for valid health.
6. Ensure a local attached TUI exists for the current directory and generation.
7. Invoke the hook callback only after preparation succeeds or fails.

Repeated ensure calls in one Neovim process must coalesce while startup is in
progress. Every waiting callback must resolve exactly once.

### Attached TUI

The local terminal command is:

```text
opencode attach <managed-url> --dir <absolute-current-directory>
```

Pass Basic Auth through the existing OpenCode environment variables. Do not put
passwords in command arguments or state files.

Recycle the local terminal when:

- Its process is no longer valid.
- Its URL differs from managed state.
- Its attach directory differs from current Neovim cwd.
- Its remembered generation differs from managed server generation.

The OpenCode HTTP API cannot confirm TUI presence or readiness. A successful
`/tui/publish` response is not proof that a TUI consumed the event. On newly
created terminals, allow a short bounded bootstrap interval before continuing an
operation. Document that this avoids the common race but cannot provide a formal
readiness guarantee without upstream API support.

### Directory Changes

Resolve the current working directory at operation time. If `:cd`, project
switching, or another action changes Neovim cwd, close the old local attached
TUI and attach a replacement for the new directory before sending commands.

### Terminal Commands

Preserve these behaviors:

| Command | Target behavior |
| --- | --- |
| `:Opencode` / `:Opencode toggle` | Ensure backend, then toggle local attached TUI |
| `:Opencode start` | Ensure backend and show/create local attached TUI |
| `:Opencode stop` | Explicitly stop the shared managed backend and close local TUI |
| `:Opencode ask` | Ensure backend/TUI, then ask |
| `:Opencode select` | Ensure backend/TUI, then select |
| `:Opencode move ...` | Move only the local Snacks terminal window |
| `:Opencode info` | Show live information without starting anything |
| `:Opencode reload` | Safely reload the current directory's OpenCode instance and local TUI |
| `:OpenCodeStart` | Alias for explicit ensure/start behavior |
| `:OpenCodeStop` | Explicit shared-server stop |
| `:OpenCodeInfo` | Live observational diagnostics |
| `:OpenCodeReload` | Scoped current-directory configuration reload |

The explicit stop command affects every MkChad and web client using that shared
backend. Its description and notification must say "shared server".

### Explicit Stop

Stopping must:

1. Acquire the startup lock.
2. Re-read state.
3. Verify process ownership and command line.
4. Send graceful termination to the managed process or process group.
5. Wait for health to fail and the process to exit.
6. Escalate only to the verified managed process when necessary.
7. Remove state only for the stopped generation.
8. Release the lock.
9. Close the current Neovim's attached TUI.

Do not stop the server on Neovim exit.

### Scoped Configuration Reload

`:OpenCodeReload` and `:Opencode reload` reload only the server-side
OpenCode instance routed to the current absolute Neovim directory. They must not
stop, replace, or change the PID, generation, URL, or port of the healthy shared
`opencode serve` process. Other directory instances and their attached TUIs must
remain usable.

The command exists for project-scoped `opencode.json`/`opencode.jsonc`, agents,
commands, skills, plugins, MCP configuration, and other state initialized with an
OpenCode directory instance. Existing `AGENTS.md` contents are already read for
new model work by OpenCode and do not require this command. OpenCode 1.17.20
caches portions of global configuration for the server-process lifetime, so the
command must state that it does not guarantee reloading
`~/.config/opencode/opencode.json` or
`~/.config/opencode/opencode.jsonc`; use
`:OpenCodeStop` followed by the next OpenCode operation when a full process
reload is required.

OpenCode 1.17.20 exposes `POST /instance/dispose` but has no released reload
command. Upstream reload work remains open in `anomalyco/opencode` PR #9871,
and issue #36495 documents that instance disposal closes the directory-scoped
`/event` stream. Treat this implementation as a version-specific compatibility
layer and revisit it when upstream ships a stable reload API.

Reloading must:

1. Resolve the current absolute Neovim directory at invocation time.
2. Probe the managed endpoint and report an inactive result without starting a
   server when no healthy managed backend exists.
3. Verify that the healthy endpoint matches managed state before sending a
   mutating request.
4. Query the directory-routed `/session/status`, pending permission, and pending
   question APIs. Refuse reload while any current-directory operation or
   interactive request is active; do not add a force/bang bypass in this sprint.
5. Send an authenticated, directory-routed `POST /instance/dispose` without
   exposing credentials in process arguments, logs, notifications, or state.
6. Treat the expected directory-scoped SSE disconnect as a reload transition,
   clear stale opencode.nvim connection/status state, and reconnect rather than
   replacing the shared backend.
7. Recreate the directory instance with a bounded benign request such as
   `GET /path`, and require its routed path to equal the invocation directory.
8. Close and recreate the invoking Neovim's local `opencode attach` process so
   client-side TUI configuration and server inventories are refreshed.
9. Wait only for the existing bounded TUI bootstrap interval; do not claim the
   OpenCode API proves attached-TUI readiness.
10. Report success only after instance recreation, routed-path validation,
    opencode.nvim reconnection, and local TUI process recreation complete.

Repeated reload requests in one Neovim process must coalesce. Concurrent reloads
from separate MkChad processes for the same directory must converge on one usable
recreated instance or return a bounded actionable error; they must not stop the
shared server or leave all clients permanently disconnected. A reload for one
directory must not dispose a different directory instance.

## `:OpenCodeInfo` Requirements

The command must be asynchronous, observational, and based on fresh probes. It
must not invoke opencode.nvim discovery, `server.ensure`, server startup, or TUI
creation.

Report:

| Field | Source |
| --- | --- |
| State directory | Computed host-specific state path |
| State status | Missing, valid, malformed, stale, or unsupported schema |
| URL | Explicit configuration or managed state |
| Port source | Explicit environment, persisted, preferred 4096, or fallback |
| HTTP backend | Live health probe |
| Health latency | Timed live request |
| Server version | `/global/health` response |
| Local version | `opencode --version` |
| PID | Managed state |
| PID status | Live process check and ownership validation |
| Generation | Managed state |
| Start time | Managed state |
| Log path | Managed state/computed path |
| Plugin SSE | `require("opencode.server").connected` and subscription state |
| Neovim cwd | Live `vim.fn.getcwd()` |
| Routed path | Live `/path` request with directory header when backend is up |
| Local TUI | Snacks terminal job validity, URL, directory, and generation |
| TUI API presence | Explicitly "unknown/unsupported" |

Severity guidelines:

- Healthy managed server: informational success.
- No state and no server: normal inactive state, not an error.
- State present and health down: warning.
- Explicit port occupied by an unknown service: error.
- Authentication failure: error without printing credentials.
- Local/server version mismatch: warning with explicit stop/start guidance.
- Connected plugin SSE with failed live health: warning and stale-connection note.

Do not add a separate `:OpenCodeStatus` command unless implementation experience
shows a distinct need. `:OpenCodeInfo` and `:Opencode info` are the single live
diagnostic interface for this sprint.

## Statusline Requirements

The statusline may continue to use event-driven cached state for low overhead,
but it must not display a stale connected URL after `Server:disconnect()`.
`:OpenCodeInfo`, not the statusline, remains the authoritative diagnostic.

## OpenCode Version Policy

At sprint definition time, npm reports `opencode-ai@1.17.20` as latest.

Update:

- x86_64 baseline from `1.17.0` to `1.17.20`.
- aarch64 baseline from `1.17.18` to `1.17.20`.

Leave ppc64le unchanged. The npm package currently declares only x64 and arm64
CPU support, and ppc64le support is outside this sprint.

The mounted npm prefix remains authoritative at runtime, allowing users to
install a newer OpenCode without rebuilding the SIF. A running persistent server
does not change executable code after a live update. `:OpenCodeInfo` must expose
version mismatches, and users can run `:OpenCodeStop` followed by the next
OpenCode operation to launch the updated executable.

## Security And Privacy

- Bind only to `127.0.0.1`.
- Honor existing Basic Auth environment variables.
- Do not invent credentials in this sprint.
- Warn in documentation that loopback is shared by local users on multi-user
  systems and an unset password permits local access by those users.
- Set state directory permissions to `0700`.
- Set state and log permissions to `0600`.
- Never print server passwords, provider credentials, API tokens, or complete
  inherited environments.
- Do not adopt an unknown OpenCode server on an occupied port.
- Validate managed PIDs before signaling them.

## Failure Handling

| Failure | Required behavior |
| --- | --- |
| Missing state | Treat as inactive; select a port only on ensure |
| Malformed state | Warn in info; replace under lock during ensure |
| Stale PID | Do not report healthy; replace state under lock |
| Reused PID | Refuse to signal if command ownership cannot be verified |
| Health timeout | Report timeout distinctly and include URL |
| HTTP 401 | Report authentication failure without exposing credentials |
| Occupied automatic port | Select and persist another high port |
| Occupied explicit port | Fail without fallback |
| Startup bind race | Retry only for automatic selection; fail for explicit port |
| Server exits before ready | Clear matching generation and include log path |
| Another MkChad is starting | Wait for lock winner and health |
| Startup lock owner dies | Reclaim stale lock after bounded validation |
| Server killed after startup | Recover on next OpenCode operation |
| TUI survives server replacement | Recycle it on generation mismatch |
| TUI attach fails | Keep healthy backend; report local attach failure |
| Neovim cwd changes | Reattach local TUI for new directory |
| Reload requested while work or an interactive prompt is active | Refuse without disposing the instance |
| Reload requested with no healthy managed server | Report inactive without starting a server |
| Instance dispose or recreation fails | Keep the shared backend running; report the directory and failed phase |
| Instance reload closes directory SSE | Clear stale state and reconnect with bounded retry |
| Local OpenCode updated | Keep healthy server; report mismatch in info |
| Unknown healthy OpenCode on port | Do not adopt without matching state |

## Known Limitations

- A detached process is less strongly supervised than a container instance or
  systemd service.
- Some SingularityCE/Apptainer or site configurations may clean up detached
  child processes when the originating container command exits.
- Recovery occurs on the next OpenCode operation, not continuously.
- The OpenCode API cannot report whether an attached TUI is ready.
- A short TUI bootstrap delay reduces but cannot eliminate first-publish races.
- Multiple attached TUIs for the same directory may all receive directory-routed
  TUI commands.
- Server mounts are inherited from the MkChad container that creates it. Mounts
  introduced later require server replacement.
- `:OpenCodeReload` does not guarantee reloading process-cached global OpenCode
  configuration and cannot preserve an active in-memory operation, so it refuses
  reload while directory work or an interactive request is active.
- Local users can reach an unauthenticated loopback server on shared machines.

## Compatibility Requirements

- Preserve x86_64 and aarch64 container behavior.
- Preserve SingularityCE and Apptainer launch support.
- Preserve `NVIM_APPNAME=mkchad`.
- Preserve `OPENCODE_CONFIG` forwarding.
- Preserve `OPENCODE_PORT` as an override, with stricter explicit-port failure.
- Preserve `OPENCODE_SERVER_USERNAME` and `OPENCODE_SERVER_PASSWORD` behavior.
- Preserve terminal positions: bottom, top, left, right, float, and default.
- Preserve existing OpenCode mappings and command names unless specifically
  extended with `info` and `reload`.
- Preserve architecture-specific mounted npm prefix selection.

## Implementation Sequence

### Phase 1: Fork Foundation

1. Create a working branch from current main in
   `/data1/matthew/Projects/opencode.nvim`.
2. Apply PR #239's directory header to current code.
3. Add the asynchronous pre-operation ensure hook.
4. Clear status state on disconnect.
5. Add fork maintenance documentation.
6. Run formatting and available static checks.

### Phase 2: MkChad State Manager

1. Replace random per-Neovim port selection with persisted host-specific state.
2. Add live health probing and result classification.
3. Add atomic state writes and startup lock handling.
4. Add detached process launch and logging.
5. Add explicit stop with PID validation.
6. Remove `ExitPre` server shutdown.

### Phase 3: TUI And Plugin Integration

1. Point Lazy at `krafczyk/opencode.nvim` main.
2. Configure `server.ensure` and disable fallback `server.start` behavior.
3. Add `--dir` to attached TUI commands.
4. Track local TUI URL, directory, and generation.
5. Recycle TUI on backend generation or cwd changes.
6. Preserve existing terminal layout and toggling.
7. Add scoped `:OpenCodeReload` and `:Opencode reload` handling.
8. Refuse active-instance reloads, dispose/recreate only the current directory
   instance, reconnect opencode.nvim, and recycle the local attached TUI.

### Phase 4: Diagnostics

1. Replace cached `:OpenCodeInfo` logic with live probes.
2. Add `:Opencode info` and completion.
3. Report process, state, HTTP, SSE, directory, TUI, log, and version layers.
4. Verify the command never starts OpenCode.

### Phase 5: Container Baseline

1. Update x86_64 to `opencode-ai@1.17.20`.
2. Update aarch64 to `opencode-ai@1.17.20`.
3. Leave ppc64le unchanged.

### Phase 6: Integration Verification

1. Verify syntax and formatting in all changed repositories.
2. Verify first-use startup.
3. Verify multi-MkChad reuse and startup races.
4. Verify persistence across originating Neovim exit.
5. Verify killed-process recovery.
6. Verify web access and directory routing.
7. Verify explicit and automatic port conflict behavior.
8. Verify diagnostics, scoped reload, and explicit stop.

## Acceptance Criteria

### Laziness

- Starting MkChad does not create an OpenCode process or state file.
- `:OpenCodeInfo` before first use reports inactive without starting OpenCode.
- The first OpenCode action starts the backend and local attached TUI.

### Singleton Behavior

- Two MkChad processes on one host use one backend URL and generation.
- Concurrent first actions result in one healthy managed server.
- A waiting contender does not launch a second server.

### Persistence And Recovery

- Closing the MkChad process that launched the server does not intentionally stop
  the server.
- A later MkChad process reuses the same healthy server.
- Killing the managed server causes the next OpenCode action to start a new
  generation.
- A local TUI associated with an old generation is recycled on next use.

### Directory Routing

- Every opencode.nvim request includes the current Neovim cwd header.
- Every attached TUI uses `--dir` with the same absolute cwd.
- MkChad processes in distinct directories receive their intended TUI commands.
- Changing Neovim cwd causes a directory-correct reattach.

### Port Behavior

- Without state or an override, port `4096` is preferred.
- An automatically selected fallback port persists across MkChad processes.
- An unavailable explicit `OPENCODE_PORT` fails without fallback.
- An unknown server or service is not adopted solely because it occupies a port.

### Diagnostics

- `:OpenCodeInfo` uses a fresh health request.
- It distinguishes inactive, healthy, unhealthy, unauthorized, and stale-state
  conditions.
- It reports server and local OpenCode versions.
- It reports state, PID, generation, log, SSE, cwd, and local TUI information.
- It does not claim to know HTTP-level TUI presence.
- It never starts or stops the server.

### Explicit Stop

- `:OpenCodeStop` stops only a verified managed server.
- It removes state only for the stopped generation.
- It never signals an unrelated reused PID.
- Neovim exit does not invoke shared-server stop.

### Scoped Configuration Reload

- `:OpenCodeReload` does not start an inactive server.
- Reload refuses while current-directory work, permission prompts, or questions
  are active.
- Reload applies changed project-scoped configuration to subsequent operations.
- The shared server PID, generation, URL, and port remain unchanged.
- Other directory instances remain connected and usable.
- opencode.nvim reconnects and the invoking Neovim receives a newly created
  directory-correct attached TUI.
- Reload never claims that process-cached global configuration was refreshed.

### Version Baseline

- x86_64 and aarch64 Dockerfiles use `opencode-ai@1.17.20`.
- ppc64le remains unchanged.
- Runtime npm override behavior remains intact.

## Verification Matrix

| Scenario | Expected result |
| --- | --- |
| Start MkChad, do nothing | No server, state, or TUI is created |
| Run info before first use | Inactive report; no side effects |
| First ask | Server starts, health passes, TUI attaches, ask reaches TUI |
| Open second MkChad in another project | Same URL; second directory-scoped TUI |
| First use in both editors simultaneously | One lock winner and one backend |
| Exit original editor | Server remains healthy where runtime permits |
| Kill server PID | State becomes stale; no false healthy report |
| Invoke next OpenCode action | New generation starts and plugin reconnects |
| Change cwd | Old local TUI recycled; new `--dir` used |
| Occupy 4096, no override | High fallback selected and persisted |
| Occupy explicit override | Clear failure; no fallback |
| Set wrong password | Unauthorized diagnostic; no credential disclosure |
| Update local OpenCode while server runs | Info reports version mismatch |
| Reload with no running server | Inactive result; no process or state is created |
| Reload while a session or prompt is active | Clear refusal; instance and clients remain intact |
| Change project config, then reload | Current directory instance uses the new config without a server PID/generation change |
| Reload project A while project B is connected | Project A reconnects; project B and the shared backend remain usable |
| Invoke same-directory reload concurrently | One usable instance remains; both commands finish or fail within bounds |
| Stop shared server | Verified process stops; state clears |
| Use web UI | Stable persisted URL serves web application |

## Test And Tooling Constraints

The current `msk_containers` workspace environment does not provide a
`singularity` or `apptainer` executable. Repository-level syntax, formatting,
and static checks can run here, but detached-process persistence and mount
inheritance must be validated on at least one real SingularityCE host and one
real Apptainer host when available.

Full multi-architecture container rebuilds are expensive and may be separated
from source-level verification. The sprint is not complete until the supported
architecture baseline changes have at least passed their normal build path or a
documented equivalent CI build.

## Rollback Plan

If shared-server behavior is unreliable:

1. Restore the upstream opencode.nvim plugin source and released version.
2. Restore the prior per-Neovim random-port implementation in MkChad.
3. Restore the `ExitPre` cleanup only for the per-Neovim server model.
4. Remove the scoped reload commands if instance disposal or client refresh is
   unreliable; this does not require reverting shared-server lifecycle state.
5. Stop any verified detached managed server through the new stop command or
   validated PID state.
6. Preserve server logs and failed state metadata for diagnosis.

Container baseline updates are independent and do not need rollback unless the
new package fails the supported architecture build.

## Follow-Up Work

- Reassess the architecture when OpenCode v2's shared backend behavior is
  released and documented.
- Remove the forked directory patch if upstream PR #239 or an equivalent lands.
- Propose the pre-operation ensure hook upstream if it proves generally useful.
- Add an upstream TUI registration/readiness endpoint if reliable publish
  acknowledgement becomes necessary.
- Replace the scoped reload workaround when upstream ships a stable reload API
  that covers project and global configuration without unsafe instance disposal.
- Consider generated Basic Auth credentials for shared hosts in a separate
  security sprint.
- Consider instance or systemd supervision only if best-effort detached
  persistence proves insufficient on target machines.
