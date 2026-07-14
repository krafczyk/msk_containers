# Audit Policy

## Purpose

This policy defines how implementation audits are performed and how findings
are prioritized for the single persistent OpenCode server sprint.

The primary remediation objective is to identify and resolve all P0 and P1
issues. Lower-priority findings should be recorded and addressed when they are
low risk to fix or directly support the sprint's acceptance criteria.

## Scope

Audits cover sprint-related changes in:

- `/data1/matthew/Projects/msk_containers`
- `/home/matthew/.config/mkchad`
- `/data1/matthew/Projects/opencode.nvim`

The audit should consider the combined behavior of all three repositories, not
only each repository in isolation.

The threat assumptions in `docs/threat_model.md` are normative for security and
availability findings.

## Audit Principles

- Findings take priority over summaries or stylistic commentary.
- Findings must describe observable impact, not only code preference.
- Every finding should include a concrete file and line reference when possible.
- Every finding should include a plausible trigger or reproduction path.
- Severity is based on impact and likelihood in the documented deployment.
- Root-equivalent administrator capabilities are not application-fixable by
  themselves; findings should instead focus on unsafe behavior after selective
  process disruption.
- Audits must not recommend evading system administration controls.
- Audits must preserve laziness: ordinary MkChad startup and status inspection
  must not start OpenCode.
- Audits must treat live health as liveness truth and persistent state as
  coordination metadata.
- Audits must account for shared homes, multiple hosts, multiple MkChad
  processes, PID reuse, and port races.
- Audits must not modify unrelated user changes.

## Priority Definitions

### P0: Critical

A P0 issue can cause catastrophic or broadly unsafe behavior under expected or
adversarial conditions.

Examples:

- Signaling or killing an unrelated process without reliable ownership checks.
- Disclosing provider credentials or server passwords in committed files,
  diagnostics, process arguments, or world-readable state.
- Corrupting or deleting unrelated user data.
- Executing attacker-controlled state as code or shell input.
- Entering an unbounded process-spawn or restart loop.
- Making ordinary MkChad startup consistently unusable across supported hosts.
- Connecting project commands to an untrusted endpoint while treating it as the
  managed server.

Policy:

- P0 findings block sprint completion.
- Begin remediation immediately.
- Add a regression test or explicit verification whenever feasible.
- Re-audit the fix and adjacent code paths before proceeding.
- Do not accept a P0 risk as a normal limitation.

### P1: High

A P1 issue can cause serious data exposure, persistent availability failure, or
incorrect cross-process behavior in a realistic deployment scenario.

Examples:

- Failure to recover after the managed server is selectively killed.
- A startup race that regularly creates multiple managed servers.
- Stale-lock handling that can block all future OpenCode use.
- Explicit `OPENCODE_PORT` silently falling back to another port.
- Adopting an unknown OpenCode endpoint without matching managed state.
- Reporting a dead server as healthy based only on cached state.
- Sending TUI commands to the wrong project directory.
- Failing to namespace process state by host on a shared home directory.
- Writing lifecycle state or logs with permissions readable by other users.
- A healthy server becoming dependent on the originating Neovim process because
  detachment was implemented incorrectly.
- A failed lifecycle hook preventing all future plugin actions without a bounded
  recovery path.

Policy:

- The team should resolve every P1 finding during the sprint.
- A P1 remains a release blocker unless it is proven unreachable in the scoped
  deployment or explicitly deferred with a documented owner, rationale, and
  bounded operational workaround.
- Re-audit the fix and its concurrency/failure paths.
- Add regression coverage or a repeatable manual verification procedure.

### P2: Medium

A P2 issue causes degraded behavior, confusing diagnostics, or a recoverable
failure that does not threaten unrelated processes or sensitive data.

Examples:

- `:OpenCodeInfo` omits useful but nonessential metadata.
- An error message lacks the server log path.
- TUI recreation requires a second user action after a rare race.
- A malformed optional state field produces a warning that is not actionable.
- The statusline takes longer than expected to clear after disconnect while live
  info remains correct.
- A bounded retry policy is unnecessarily slow but eventually succeeds or
  fails safely.

Policy:

- Record all P2 findings.
- Resolve P2 findings that are low-risk or necessary for acceptance criteria.
- Unresolved P2 findings require a concise residual-risk note.
- P2 findings do not automatically block sprint completion.

### P3: Low

A P3 issue is a minor maintainability, documentation, consistency, or user
experience concern with limited operational impact.

Examples:

- Inconsistent naming that does not change behavior.
- Missing comments around a non-obvious but safe branch.
- Minor duplicated code.
- Documentation wording or formatting issues.
- A diagnostic field could be ordered more clearly.

Policy:

- Record P3 findings when useful.
- Fix opportunistically.
- Do not delay P0/P1 work to address P3 findings.

## Required Audit Areas

### Process Safety

- Validate PID ownership before any signal.
- Validate process generation before state cleanup.
- Verify negative or reused PIDs cannot target unrelated processes or groups.
- Verify stop escalation remains scoped to the managed process.
- Verify detached process handles and file descriptors are closed safely.

### Concurrency

- Audit startup lock acquisition, ownership, expiry, and removal.
- Audit concurrent first-use startup from separate Neovim processes.
- Audit state replacement while another process is reading.
- Audit recovery when the lock owner or state writer is killed.
- Audit port bind races in automatic and explicit modes.
- Verify all callback and promise paths resolve exactly once.

### Liveness And Recovery

- Verify `/global/health` is the authoritative liveness check.
- Verify all retries and polls are bounded.
- Verify server death clears stale connection presentation.
- Verify next-use recovery after server death.
- Verify TUI recreation after TUI death or generation change.
- Verify failure does not make ordinary MkChad startup unusable.

### State Integrity

- Verify hostname namespacing.
- Verify atomic state writes.
- Verify malformed, absent, stale, and future-schema state handling.
- Verify cleanup is conditional on matching generation.
- Verify state and logs use restrictive permissions.
- Verify no secrets are persisted.

### Endpoint And Port Safety

- Verify unknown endpoints are not adopted based only on health.
- Verify explicit port conflicts fail without fallback.
- Verify automatic fallback is bounded and persisted.
- Verify auth failures are distinguished from availability failures.
- Verify the server binds only to loopback.

### Directory Routing

- Verify every opencode.nvim request sends the current cwd header.
- Verify every attached TUI uses the corresponding `--dir`.
- Verify cwd changes recycle the local TUI.
- Verify distinct project directories do not receive each other's TUI commands.
- Record the same-directory multi-TUI limitation rather than presenting it as
  solved.

### Laziness And Side Effects

- Verify MkChad startup starts no OpenCode process.
- Verify plugin load starts no OpenCode process.
- Verify `:OpenCodeInfo` starts no process and writes no lifecycle state.
- Verify statusline rendering has no lifecycle side effects.
- Verify first OpenCode use performs bounded preparation.

### Diagnostics

- Verify live info distinguishes HTTP health, PID state, plugin SSE, and local
  TUI state.
- Verify stale state is not reported as healthy.
- Verify errors identify URL, port, and log path where safe.
- Verify credentials and inherited environment values are not printed.
- Verify server/local version mismatch is reported accurately.

### Regression And Compatibility

- Verify existing mappings and terminal positions.
- Verify SingularityCE and Apptainer behavior where environments are available.
- Verify mounted npm overrides still take precedence.
- Verify x86_64 and aarch64 baseline updates.
- Verify ppc64le remains untouched.
- Verify unrelated worktree changes remain untouched.

## Audit Workflow

1. Read `docs/single-opencode-server/SPRINT_SPEC.md`.
2. Read `docs/single-opencode-server/SPRINT_CHECKLIST.md`.
3. Read `docs/threat_model.md`.
4. Inspect worktree status in every in-scope repository.
5. Identify the exact sprint diff in every repository.
6. Review behavior across repository boundaries.
7. Run static checks and focused tests.
8. Exercise process-kill, race, state-corruption, and port-conflict scenarios.
9. Report findings ordered by P0, P1, P2, then P3.
10. Include file/line references and reproduction details.
11. Remediate P0/P1 findings before lower-priority cleanup.
12. Re-run affected checks after each remediation.
13. Perform a final re-audit of the combined diff.
14. Record unresolved risks and verification gaps.

## Finding Format

Use this structure:

```text
[P1] Short finding title
Location: path/to/file.lua:123
Impact: What can go wrong and why it matters.
Trigger: The concrete sequence or condition that exposes the issue.
Evidence: Relevant code behavior, test result, or log observation.
Remediation: The smallest safe change that addresses the root cause.
Verification: How to prove the remediation works.
```

Do not inflate severity because a root administrator could bypass the system.
Assign severity based on whether application behavior introduces additional harm
or fails its documented recovery contract under selective disruption.

## P0/P1 Resolution Standard

A P0 or P1 finding is resolved only when:

- The root cause is understood.
- The implementation is corrected or the affected behavior is removed.
- Relevant tests or repeatable verification steps pass.
- Adjacent failure and concurrency paths are reviewed.
- The combined cross-repository behavior remains consistent.
- The fix does not introduce an equal or higher-severity regression.
- Documentation and checklist entries are updated when behavior changes.

Closing a finding because the happy path works is insufficient. Process death,
stale state, concurrent startup, and PID reuse must be considered where relevant.

## Exceptions

P0 exceptions are not permitted for sprint completion.

A P1 may be deferred only when all of the following are recorded:

- Why the issue cannot reasonably be resolved in the sprint.
- Why the affected path is unreachable or acceptably bounded in the scoped
  deployment.
- The operational workaround.
- The responsible owner.
- A follow-up issue or sprint item.
- The condition that will trigger re-evaluation.

The inability to defend against root is not itself a P1 exception. The audit
must distinguish impossible root resistance from fixable unsafe application
behavior.

## Completion Gate

The audit passes when:

- No P0 findings remain.
- Every P1 is resolved, or an explicit exception meeting this policy is
  documented.
- Required acceptance criteria have verification evidence.
- Remaining P2/P3 findings and test gaps are recorded.
- No secrets or unrelated changes are present in the final diffs.
- The implementation still fails safely when one or more process-chain members
  are killed.

The preferred outcome is zero unresolved P0 and P1 findings.
