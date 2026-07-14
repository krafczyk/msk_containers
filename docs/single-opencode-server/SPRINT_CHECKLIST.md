# Single Persistent OpenCode Server Sprint Checklist

## Usage

This checklist tracks implementation of the design in
`SPRINT_SPEC.md`. Complete an item only after its implementation and applicable
verification are finished. Record deviations in the sprint notes before marking
the affected item complete.

## Sprint Decisions

- [x] Use a lazy, detached server launched from an existing MkChad container.
- [x] Do not use a Singularity/Apptainer instance.
- [x] Do not start OpenCode during ordinary MkChad startup.
- [x] Recover a killed server on the next OpenCode operation.
- [x] Store persistent coordination state under `stdpath("state")`.
- [x] Namespace state by hostname for shared home directories.
- [x] Bind the server only to `127.0.0.1`.
- [x] Honor existing server auth environment variables without generating any.
- [x] Prefer port `4096` when no persisted or explicit port exists.
- [x] Fail instead of falling back when `OPENCODE_PORT` is explicitly set.
- [x] Carry upstream opencode.nvim PR #239 behavior in the custom fork.
- [x] Use the existing `:OpenCodeInfo` as the live diagnostic command.
- [x] Add `:OpenCodeReload` as a safe current-directory instance reload rather
      than a shared-server restart.
- [x] Update x86_64 and aarch64 OpenCode baselines to `1.17.20`.
- [x] Leave ppc64le unchanged.

## Preparation

- [x] Confirm working trees and record unrelated changes in `msk_containers`.
- [x] Confirm working tree and unrelated changes in `/home/matthew/.config/mkchad`.
- [x] Note that `/home/matthew/.config/mkchad/lazy-lock.json` is currently
      untracked and must not be changed unless explicitly included later.
- [x] Locate the fork checkout at `/data1/matthew/Projects/opencode.nvim`.
- [x] Confirm the fork starts from current upstream-compatible main.
- [x] Create focused implementation branches in each repository as appropriate.
- [x] Record the starting commit for each repository in the sprint notes.
- [x] Confirm `opencode-ai@1.17.20` remains the current intended baseline.

## Workstream A: opencode.nvim Fork

### Directory Routing

- [ ] Apply the PR #239 directory-header change to current fork main.
- [ ] Resolve `vim.fn.getcwd()` for every request rather than at plugin load.
- [ ] Add `x-opencode-directory` only when cwd is non-empty.
- [ ] Preserve existing auth, content, timeout, and SSE request behavior.
- [ ] Verify the header is present on `/path` requests.
- [ ] Verify the header is present on `/event` requests.
- [ ] Verify the header is present on `/tui/publish` requests.
- [ ] Add an inline reference to upstream PR #239.
- [ ] Note that MkChad intentionally keeps attached TUI and Neovim cwd aligned.

### Ensure Hook

- [ ] Add the optional `server.ensure` field to Lua annotations.
- [ ] Define the callback contract as `callback(ok, err)`.
- [ ] Invoke `server.ensure` before every `discovery.get()` lookup.
- [ ] Continue immediately when no ensure hook is configured.
- [ ] Convert ensure-hook exceptions into useful operation errors.
- [ ] Reject an operation when the hook reports failure.
- [ ] Ensure each callback path resolves or rejects exactly once.
- [ ] Preserve existing configured URL behavior after ensure succeeds.
- [ ] Preserve local server discovery for users without the hook.
- [ ] Preserve existing `server.start` fallback for users without the hook.
- [ ] Verify `ask`, `select`, `prompt`, `command`, and operators all pass through
      the hook.

### Disconnect And Status

- [ ] Clear `Server.connected` on curl failure as before.
- [ ] Clear connection state on heartbeat expiry as before.
- [ ] Clear stale statusline URL on ungraceful disconnect.
- [ ] Clear stale idle/busy/error status on disconnect.
- [ ] Avoid introducing background reconnection.
- [ ] Verify next operation reconnects through `discovery.get()`.

### Fork Documentation And Checks

- [ ] Document PR #239 as a carried upstream patch.
- [ ] Document the fork-specific `server.ensure` option.
- [ ] Document conditions for removing custom changes.
- [ ] Mention possible OpenCode v2 supersession.
- [ ] Run `stylua` on changed Lua files.
- [ ] Run the repository's available Lua language/static checks.
- [ ] Review the fork diff against current main.
- [ ] Confirm no unrelated upstream files changed.
- [ ] Make the fork revision available to MkChad before changing its plugin URL.

## Workstream B: Persistent State

### Paths And Permissions

- [ ] Derive the root from `vim.fn.stdpath("state")`.
- [ ] Add the `opencode/<sanitized-hostname>` namespace.
- [ ] Create the state directory with mode `0700`.
- [ ] Define the `state.json` path.
- [ ] Define the `server.log` path.
- [ ] Define the `startup.lock` directory path.
- [ ] Create state and log files with mode `0600`.
- [ ] Verify no credential values are persisted.

### State Schema

- [ ] Define schema version `1`.
- [ ] Store hostname.
- [ ] Store PID.
- [ ] Store a unique process generation.
- [ ] Store host, port, and URL.
- [ ] Store start timestamp.
- [ ] Store neutral cwd.
- [ ] Store log path.
- [ ] Store resolved executable path.
- [ ] Store local OpenCode version used to launch.
- [ ] Optionally store the server-reported version after readiness.
- [ ] Reject or diagnose unsupported future schema versions safely.

### State I/O

- [ ] Read missing state as an inactive normal condition.
- [ ] Handle malformed JSON without crashing Neovim.
- [ ] Validate required field types.
- [ ] Write through a temporary file in the same directory.
- [ ] Rename the completed temporary file atomically.
- [ ] Prevent concurrent readers from observing partial JSON.
- [ ] Remove temporary files owned by failed writes.
- [ ] Remove state only when generation still matches the caller's target.

## Workstream C: Port Policy

### Explicit `OPENCODE_PORT`

- [ ] Detect whether `OPENCODE_PORT` was explicitly set and non-empty.
- [ ] Validate integer syntax.
- [ ] Validate range `1..65535`.
- [ ] Use the explicit port exactly.
- [ ] Reuse a matching healthy managed server.
- [ ] Fail if a different persisted managed server remains healthy.
- [ ] Fail if the explicit port is occupied by an unknown service.
- [ ] Fail if startup loses a bind race.
- [ ] Include the port and log path in startup failure diagnostics.
- [ ] Never select a fallback for an explicit port.

### Automatic Port

- [ ] Reuse a healthy persisted managed endpoint.
- [ ] Reuse the persisted port after a clean/stale process exit when available.
- [ ] Prefer `4096` when no usable state exists.
- [ ] Detect an occupied unknown `4096` without adopting it.
- [ ] Select an available high fallback port when necessary.
- [ ] Persist the fallback port.
- [ ] Bound fallback attempts.
- [ ] Retry a bind race only in automatic mode.
- [ ] Report the selected port source through `:OpenCodeInfo`.

## Workstream D: Live Health

- [ ] Probe `GET /global/health`.
- [ ] Use bounded connection and total timeouts.
- [ ] Apply configured Basic Auth automatically.
- [ ] Require a successful HTTP response.
- [ ] Parse JSON safely.
- [ ] Require `healthy == true`.
- [ ] Capture server version.
- [ ] Capture request latency.
- [ ] Distinguish connection refused.
- [ ] Distinguish timeout.
- [ ] Distinguish HTTP 401.
- [ ] Distinguish invalid JSON.
- [ ] Distinguish an unhealthy response.
- [ ] Keep health as the only authoritative liveness signal.

## Workstream E: Startup Lock

- [ ] Acquire the lock with atomic directory creation.
- [ ] Write owner PID, hostname, and timestamp metadata.
- [ ] Probe health before lock acquisition.
- [ ] Re-probe health immediately after lock acquisition.
- [ ] Make non-owners poll state and health rather than spawn.
- [ ] Bound contender wait duration.
- [ ] Detect a dead lock owner.
- [ ] Detect a lock beyond the startup deadline.
- [ ] Verify lock ownership before stale lock removal.
- [ ] Retry acquisition only within a bounded policy.
- [ ] Release the owned lock after successful startup.
- [ ] Release the owned lock after startup failure.
- [ ] Coalesce concurrent ensure callbacks inside one Neovim process.
- [ ] Resolve every coalesced callback exactly once.

## Workstream F: Detached Server Lifecycle

### Launch

- [ ] Resolve the OpenCode executable that the current MkChad would run.
- [ ] Query and retain its local version.
- [ ] Launch `opencode serve` rather than `opencode web`.
- [ ] Pass `--hostname 127.0.0.1`.
- [ ] Pass the selected `--port`.
- [ ] Set process cwd to `$HOME`.
- [ ] Open stdin from `/dev/null`.
- [ ] Append stdout to the mode-0600 server log.
- [ ] Append stderr to the same server log.
- [ ] Use detached `vim.uv.spawn` behavior.
- [ ] Store the returned PID and generation atomically.
- [ ] Unreference and close libuv handles correctly.
- [ ] Wait for valid OpenCode health rather than an open TCP port.
- [ ] Update state after readiness if server metadata changes.
- [ ] Include the log path in all launch errors.
- [ ] Clean only matching failed-generation state.

### Persistence

- [ ] Remove the MkChad `ExitPre` server stop callback.
- [ ] Verify normal Neovim exit does not intentionally signal the server.
- [ ] Verify the server survives originating Neovim exit on SingularityCE.
- [ ] Verify the server survives originating Neovim exit on Apptainer.
- [ ] Document any runtime where detached children are cleaned up.

### Recovery

- [ ] Detect failed health with otherwise valid state.
- [ ] Detect a dead recorded PID.
- [ ] Replace stale state only under the startup lock.
- [ ] Launch a new generation on next use.
- [ ] Let another MkChad win recovery safely.
- [ ] Recycle local TUI when generation changes.
- [ ] Verify opencode.nvim reconnects after recovery.

### Explicit Stop

- [ ] Acquire startup lock before stopping.
- [ ] Confirm state hostname.
- [ ] Confirm PID is a positive live PID.
- [x] Inspect `/proc/<pid>/cmdline` when available.
- [x] Confirm OpenCode serve command and port before signaling.
- [x] Refuse to signal an unverifiable or reused PID.
- [ ] Send graceful termination to the verified process/process group.
- [ ] Wait for process exit and failed health.
- [ ] Bound graceful stop wait.
- [ ] Escalate only against the verified managed generation.
- [ ] Remove matching state after stop.
- [ ] Release the lock.
- [ ] Close the current Neovim's local TUI.
- [ ] Notify that the stopped backend was shared.

## Workstream G: Attached TUI

- [ ] Build the command with the current managed URL.
- [ ] Add `--dir` with an absolute current Neovim cwd.
- [ ] Preserve existing auth environment behavior.
- [ ] Do not expose passwords in process arguments.
- [ ] Preserve Snacks terminal positions and dimensions.
- [ ] Preserve non-entering terminal creation behavior.
- [ ] Track local terminal command and job validity.
- [ ] Track attached URL.
- [ ] Track attached directory.
- [ ] Track attached server generation.
- [ ] Reuse the local terminal when all tracked values match.
- [ ] Recreate the local terminal when URL changes.
- [ ] Recreate the local terminal when cwd changes.
- [ ] Recreate the local terminal when generation changes.
- [x] Recreate the local terminal when its process exits.
- [ ] Allow a bounded bootstrap interval for a new attach process.
- [ ] Document that OpenCode has no TUI readiness/presence endpoint.
- [ ] Do not interpret `/tui/publish == true` as proof of delivery.

## Workstream H: MkChad Command Integration

- [ ] Configure `server.ensure` with the MkChad lifecycle callback.
- [ ] Configure the URL as a host-state-aware value or resolver.
- [ ] Set `server.start = false` when ensure owns startup.
- [ ] Preserve `:Opencode` default toggle behavior.
- [ ] Preserve `:Opencode toggle`.
- [ ] Preserve `:Opencode start`.
- [ ] Preserve `:Opencode stop` with new shared semantics.
- [ ] Preserve `:Opencode ask`.
- [ ] Preserve `:Opencode select`.
- [ ] Preserve arbitrary OpenCode command forwarding.
- [ ] Preserve `:Opencode move` and its completions.
- [ ] Add `:Opencode info` and completion.
- [x] Add `:Opencode reload` and completion.
- [ ] Preserve `:OpenCodeStart`.
- [ ] Preserve `:OpenCodeStop`.
- [ ] Preserve `:OpenCodeInfo`.
- [x] Add `:OpenCodeReload`.
- [ ] Update command descriptions to distinguish local TUI from shared server.
- [ ] Ensure plugin mappings invoke the lifecycle hook before TUI operations.
- [ ] Verify operator mappings remain expression mappings.

### Scoped Configuration Reload

- [x] Resolve the absolute current Neovim directory at reload invocation time.
- [x] Report inactive without starting OpenCode when no healthy managed server
       exists.
- [x] Require matching managed state before sending the mutating reload request.
- [x] Query directory-routed session status before disposal.
- [x] Query pending permission and question state before disposal.
- [x] Refuse reload while current-directory work or interactive requests are
       active.
- [x] Do not provide a force or bang bypass for the active-work refusal.
- [x] Send authenticated `POST /instance/dispose` for the current directory.
- [x] Keep Basic Auth credentials out of argv, logs, notifications, and state.
- [x] Clear stale opencode.nvim connection and status state after disposal.
- [x] Recreate the directory instance through a bounded benign request.
- [x] Validate that the recreated `/path` matches the invocation directory.
- [x] Reconnect opencode.nvim to the recreated instance.
- [x] Recycle only the invoking Neovim's local attached TUI.
- [x] Preserve shared server PID, generation, URL, and port across reload.
- [x] Leave other directory instances and their attached TUIs usable.
- [x] Coalesce repeated reload requests in one Neovim process.
- [x] Bound and safely converge concurrent same-directory reloads from separate
       MkChad processes.
- [x] Report the failed phase and directory on dispose, recreation, reconnect,
       or TUI recreation failure.
- [x] Document that scoped reload does not guarantee refreshing process-cached
       global OpenCode configuration.

## Workstream I: Live `:OpenCodeInfo`

- [ ] Keep the command observational.
- [ ] Ensure it does not call `server.ensure`.
- [ ] Ensure it does not invoke plugin discovery.
- [ ] Ensure it does not create a TUI.
- [ ] Ensure it does not create state merely by running.
- [ ] Report state directory.
- [ ] Report missing/valid/malformed/stale state.
- [ ] Report URL and port source.
- [ ] Run a fresh health request.
- [ ] Report health latency.
- [ ] Report server version.
- [ ] Report local executable version.
- [ ] Warn on local/server version mismatch.
- [ ] Report PID and validated process state.
- [ ] Report generation and start timestamp.
- [ ] Report log path.
- [ ] Report plugin SSE connected/disconnected state.
- [ ] Report current Neovim cwd.
- [ ] Probe and report routed `/path` when healthy.
- [ ] Report local TUI process, URL, directory, and generation.
- [ ] Report HTTP-level TUI presence as unknown/unsupported.
- [ ] Distinguish unauthorized health from unavailable health.
- [ ] Avoid printing credentials.
- [ ] Use warning/error severity consistently.

## Workstream J: Plugin Source Selection

- [ ] Change the plugin source to `krafczyk/opencode.nvim`.
- [ ] Track fork main or an explicit accepted fork revision.
- [ ] Remove `version = "*"` so Lazy does not select an older release tag and
      bypass the custom fork commits.
- [ ] Confirm dependency loading remains unchanged.
- [ ] Confirm configured commands still trigger lazy loading.
- [ ] Confirm configured keymaps still trigger lazy loading.
- [ ] Decide explicitly whether to update/commit `lazy-lock.json`.
- [ ] Leave the existing untracked lock file untouched unless that decision is
      affirmative.

## Workstream K: Container Baseline

- [x] Change x86_64 `OPENCODE_VERSION` from `1.17.0` to `1.17.20`.
- [x] Change aarch64 `OPENCODE_VERSION` from `1.17.18` to `1.17.20`.
- [x] Leave ppc64le unchanged.
- [x] Preserve the mounted npm prefix override.
- [ ] Verify x86_64 package installation.
- [ ] Verify aarch64 package installation.
- [ ] Verify `opencode --version` reports `1.17.20` without an override.
- [ ] Verify a newer mounted runtime still takes precedence.

## Static Verification

- [ ] Format changed MkChad Lua files with the repository's StyLua settings.
- [ ] Format changed fork Lua files with its StyLua settings.
- [ ] Run available Lua language checks in the fork.
- [ ] Check all edited shell/Docker syntax where applicable.
- [ ] Search for remaining random per-Neovim port selection code.
- [ ] Search for remaining `opencode web` lifecycle commands in MkChad config.
- [ ] Search for remaining `ExitPre` shared-server shutdown behavior.
- [ ] Search for attached TUI commands missing `--dir`.
- [ ] Search for stale references to upstream `nickjvandyke/opencode.nvim` in
      MkChad plugin configuration.
- [x] Verify reload requests route to `/instance/dispose` with the current cwd.
- [x] Verify reload code never invokes shared-server stop or startup paths.
- [ ] Review diffs in all repositories.
- [ ] Confirm unrelated changes were not modified.

## Integration Verification

### Lazy Startup

- [ ] Start MkChad and verify no OpenCode server process appears.
- [ ] Verify no state file is created at ordinary startup.
- [ ] Run `:checkhealth opencode` and verify it starts nothing.
- [ ] Run `:OpenCodeInfo` and verify it starts nothing.
- [ ] Trigger the first ask and verify one server starts.
- [ ] Verify the first local attached TUI starts with the correct `--dir`.

### Shared Server

- [ ] Open two MkChad processes on one host.
- [ ] Use different project directories.
- [ ] Trigger OpenCode from both.
- [ ] Verify both report the same URL and generation.
- [ ] Verify only one backend process exists.
- [ ] Verify each has its own local attached TUI.
- [ ] Verify directory-routed commands reach the intended distinct-directory TUI.
- [ ] Record the known behavior when two TUIs use the same directory.

### Concurrent Startup

- [ ] Remove prior managed state safely.
- [ ] Trigger first use from two MkChad processes concurrently.
- [ ] Verify one startup lock winner.
- [ ] Verify the loser waits rather than spawning.
- [ ] Verify both operations eventually connect to one backend.
- [ ] Verify lock files are cleaned after success.

### Persistence

- [ ] Record the originating Neovim PID and server PID.
- [ ] Exit the originating Neovim normally.
- [ ] Verify the server health endpoint remains live.
- [ ] Verify web access remains available.
- [ ] Start another MkChad and verify server reuse.
- [ ] Repeat on a SingularityCE target.
- [ ] Repeat on an Apptainer target.

### Killed Server Recovery

- [ ] Start a server and at least one attached TUI.
- [ ] Kill only the recorded server process to simulate headnode enforcement.
- [ ] Verify `:OpenCodeInfo` reports state/health disagreement.
- [ ] Trigger another OpenCode operation.
- [ ] Verify a new PID and generation are written.
- [ ] Verify health returns on the same persisted URL when the port is free.
- [ ] Verify the old-generation local TUI is recycled.
- [ ] Verify opencode.nvim establishes a new SSE connection.
- [ ] Verify the repeated operation reaches the replacement TUI, allowing for
      the documented bootstrap limitation.

### Port Selection

- [ ] With no state and free `4096`, verify `4096` is selected.
- [ ] Restart MkChad and verify `4096` is reused.
- [ ] Occupy `4096` with an unrelated process.
- [ ] Verify an automatic high port is selected.
- [ ] Restart MkChad and verify the fallback port is reused.
- [ ] Set `OPENCODE_PORT` to a free port and verify exact use.
- [ ] Set `OPENCODE_PORT` to an occupied port and verify clear failure.
- [ ] Verify no fallback occurs for explicit port failure.
- [ ] Verify an unknown OpenCode process is not silently adopted.

### Authentication

- [ ] Test with no password and confirm loopback operation.
- [ ] Test with an existing `OPENCODE_SERVER_PASSWORD`.
- [ ] Verify the server requires Basic Auth.
- [ ] Verify opencode.nvim health and requests authenticate.
- [ ] Verify `opencode attach` authenticates through environment configuration.
- [ ] Test an incorrect password and verify a clear 401 diagnostic.
- [ ] Verify no password appears in state, logs generated by MkChad, commands, or
      notifications.

### Directory Changes

- [ ] Start in project A and verify routed `/path` is project A.
- [ ] Change Neovim cwd to project B.
- [ ] Trigger an OpenCode operation.
- [ ] Verify the old attached terminal closes.
- [ ] Verify the new attach command uses project B.
- [ ] Verify opencode.nvim requests carry project B's directory header.

### Information Command

- [ ] Verify inactive output before first use.
- [ ] Verify healthy managed output after first use.
- [ ] Verify server and local versions are shown.
- [ ] Verify PID, generation, URL, state path, and log path are shown.
- [ ] Verify plugin SSE and local TUI states are shown separately.
- [ ] Verify routed current directory is shown.
- [ ] Verify killed-server output is a warning rather than false success.
- [ ] Verify malformed-state output is actionable.
- [ ] Verify unauthorized output is distinct.
- [ ] Verify running info never changes lifecycle state.

### Stop And Restart

- [ ] Run explicit stop on a healthy managed server.
- [ ] Verify the validated PID exits.
- [ ] Verify health fails afterward.
- [ ] Verify matching state is removed.
- [ ] Verify local attached terminal closes.
- [ ] Verify another MkChad observes the outage.
- [ ] Trigger the next OpenCode operation and verify lazy restart.
- [ ] Create a fake state file with an unrelated live PID.
- [ ] Verify stop refuses to signal that PID.

### Scoped Configuration Reload

- [ ] Run `:OpenCodeReload` before first use and verify it starts nothing and
      creates no lifecycle state.
- [ ] Start a healthy shared server and record PID, generation, URL, and port.
- [ ] Change project-scoped OpenCode configuration for project A.
- [ ] Run `:OpenCodeReload` from project A.
- [ ] Verify project A's instance observes the changed configuration.
- [ ] Verify server PID, generation, URL, and port did not change.
- [ ] Verify opencode.nvim reconnects after the expected instance-dispose event.
- [ ] Verify project A's local attached TUI is recreated with the same URL and
      correct `--dir`.
- [ ] Keep project B connected during project A reload and verify project B
      remains usable without TUI recreation.
- [ ] Start an active operation and verify reload refuses without disposal.
- [ ] Leave a permission request pending and verify reload refuses.
- [ ] Leave a question pending and verify reload refuses.
- [ ] Invoke reload concurrently from two MkChad processes in the same directory
      and verify bounded convergence on one usable instance.
- [ ] Verify no credential appears in reload curl argv or diagnostics.
- [ ] Change process-cached global config and verify reload does not falsely claim
      that it refreshed it.

### Runtime Upgrade

- [ ] Start the image-baseline OpenCode server.
- [ ] Install or select a newer OpenCode in the mounted npm prefix.
- [ ] Verify the existing server remains on its original version.
- [ ] Verify `:OpenCodeInfo` reports the mismatch.
- [ ] Stop the shared server explicitly.
- [ ] Trigger the next operation.
- [ ] Verify the replacement uses the mounted newer executable.

### Web UI

- [ ] Open the persisted URL in a browser or SSH-forwarded browser.
- [ ] Verify the web UI loads through `opencode serve`.
- [ ] Verify the web UI can browse server-visible directories.
- [ ] Create sessions in two distinct directories.
- [ ] Verify terminal and web clients can see shared sessions as expected.

## Regression Verification

- [ ] Existing OpenCode ask mapping still works.
- [ ] Existing OpenCode select mapping still works.
- [ ] Existing operator mappings still work.
- [ ] Existing half-page scroll mappings still work.
- [ ] Existing terminal position selection still works.
- [ ] Existing terminal toggle behavior still works.
- [ ] Existing permission prompts still work.
- [ ] Existing file reload behavior still works.
- [ ] Existing `OPENCODE_CONFIG` is used by the detached server.
- [ ] Existing npm-global override is used by the detached server.
- [ ] Ordinary `nvim` container launch remains unaffected.
- [ ] MkChad mount detection remains unchanged.
- [ ] No ppc64le file changes are included.

## Documentation

- [ ] Document state directory and files.
- [ ] Document preferred/fallback port behavior.
- [ ] Document explicit `OPENCODE_PORT` failure behavior.
- [ ] Document how to obtain the current web URL with `:OpenCodeInfo`.
- [ ] Document explicit shared-server stop behavior.
- [x] Document scoped reload behavior, active-work refusal, and current-directory
       isolation.
- [x] Document that global process-cached config may require shared stop/restart.
- [ ] Document local-user exposure when password auth is unset.
- [ ] Document version mismatch and restart procedure.
- [ ] Document detached-process runtime limitations.
- [ ] Document the same-directory multi-TUI limitation.
- [ ] Document the upstream PR #239 dependency.
- [ ] Document how to remove fork changes after upstream support lands.

## Final Review

- [ ] All acceptance criteria in `SPRINT_SPEC.md` pass.
- [ ] All supported static checks pass.
- [ ] SingularityCE integration evidence is recorded.
- [ ] Apptainer integration evidence is recorded or its absence is documented.
- [ ] x86_64 baseline build/install evidence is recorded.
- [ ] aarch64 baseline build/install evidence is recorded.
- [ ] Security-sensitive state and logs have correct permissions.
- [ ] No secrets are present in repository diffs.
- [ ] No unrelated user changes were reverted or modified.
- [ ] Fork, MkChad config, and container diffs are reviewed together.
- [ ] Rollback procedure is still valid after final implementation.
- [ ] Remaining limitations and follow-up work are recorded.

## Sprint Notes

| Date | Repository | Note / Deviation / Evidence |
| --- | --- | --- |
| 2026-07-14 | msk_containers | Started at `797e038`; unrelated untracked `nvim/x86/jdt-language-server-1.56.0-202601291528.tar.gz` preserved. `npm view opencode-ai@1.17.20 version --json` returned `"1.17.20"`. |
| 2026-07-14 | mkchad | Started at `61c46cf`; unrelated untracked `lazy-lock.json` preserved and not modified. |
| 2026-07-14 | opencode.nvim | Started at upstream-compatible `8cb752f`; fork work is on `builder/single-opencode-server`. |
| 2026-07-14 | environment | `singularity`, `apptainer`, `docker`, `podman`, `stylua`, and `hadolint` are unavailable. Container build/install and runtime validation remain open. |
| 2026-07-14 | opencode.nvim | Pushed `ab5eefe` to `origin/builder/single-opencode-server`; MkChad pins that available revision. Headless tests verified directory headers on `/path`, `/event`, and `/tui/publish`, ensure success/exception handling, and status clearing. LuaLS could not initialize its bundled read-only metadata path; StyLua is unavailable. |
| 2026-07-14 | mkchad | Committed `1f93458`. Headless tests used isolated XDG state roots and the installed OpenCode 1.17.18 to verify lazy config load, inactive info with no state, invalid explicit-port rejection, detached first-use start, live health, 0700/0600 state permissions, normal Neovim-exit reuse, and verified shared stop. These are host-process checks, not SingularityCE/Apptainer validation. |
| 2026-07-14 | repair cycle 1 | Added focused headless regressions for exact `/proc` argv validation (including port-prefix and near-match refusal), a synchronized two-process lock race, delayed-health contender reuse of one generation, SIGKILL local-TUI recreation, explicit-port conflict preservation, authenticated 401 preservation, and a deterministic startup bind-race fixture whose unknown health responder is refused and whose failed child leaves no live orphan. The opencode.nvim curl regression verifies `/proc/<curl-pid>/cmdline` contains neither the Basic-Auth password nor JSON body while the protected stdin config request completes. These remain host-process checks; SingularityCE/Apptainer are unavailable. |
| 2026-07-14 | sprint scope | Added `:OpenCodeReload` and `:Opencode reload` as current-directory instance reloads. They must refuse active work, preserve the shared server and unrelated directories, reconnect opencode.nvim, recreate the local attached TUI, and avoid claiming to reload process-cached global config. OpenCode 1.17.20 has `/instance/dispose` but no released reload command; upstream PR #9871 and issue #36495 remain relevant. |
| 2026-07-14 | mkchad | Committed `8197e4d`: added scoped reload commands and an authenticated, directory-routed reload flow. Isolated headless fixtures verified inactive reload creates no state, busy work refuses without disposal, successful reload preflights status/permissions/questions, posts `/instance/dispose`, validates routed `/path`, clears/reconnects plugin state, recreates the local TUI, and preserves PID/generation/URL/port. This is fixture coverage only; OpenCode 1.17.20 and multi-directory runtime verification remain open. |

## Completion Record

| Field | Value |
| --- | --- |
| Fork revision |  |
| MkChad revision |  |
| Container revision |  |
| SingularityCE verification host/version |  |
| Apptainer verification host/version |  |
| OpenCode server version |  |
| Completed by |  |
| Completion date |  |
