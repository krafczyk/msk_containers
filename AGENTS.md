# Workspace Guide

## Sprint Coordination

The parent MkChad development workspace at
`/data0/matthew/Projects/mkchad` owns sprint selection and cross-repository
sprint documents. Read its `AGENTS.md` before sprint work. Do not infer a
current sprint from this repository, directory ordering, or unchecked tracker
items.

This repository currently participates in the parent selector
`single-opencode-server/2`. Its governing documents are:

- `../docs/sprints/single-opencode-server/sprint_plan.md`
- `../docs/sprints/single-opencode-server/2/sprint_spec.md`
- `../docs/sprints/single-opencode-server/2/sprint_checklist.md`
- `../docs/sprints/single-opencode-server/2/threat_model.md`
- `../docs/sprints/single-opencode-server/2/audit_policy.md`

If sprint work is requested from this child without an explicit parent-resolved
selector, return to the parent coordination root or ask the user to select one.
Normal repository work does not require a sprint selection. Keep a resolved
selector fixed for the full Builder/Auditor invocation.

The superseded TLS-only implementation baseline is archived under
`../docs/sprints/single-opencode-server/1/`. Archived sprint documents are
historical evidence and are not governing documents for new work.

## Related Repositories

Only these child repositories are part of this sprint:

- `/data0/matthew/Projects/mkchad/msk_containers`
- `/data0/matthew/Projects/mkchad/mkchad`
- `/data0/matthew/Projects/mkchad/opencode.nvim`

Use the exact parent-workspace paths above. Do not enumerate the user's home
directory or unrelated repositories. Before editing a related repository, read
its own `AGENTS.md` if present.

Repository responsibilities:

- Parent workspace: sprint plans, specifications, checklists, and policies.
- `msk_containers`: container integration and verification evidence.
- `mkchad`: shared-server lifecycle and Neovim configuration integration.
- `opencode.nvim`: directory routing and lifecycle-hook implementation.

## MkChad Live Config Protection

`/home/matthew/.config/mkchad` is the user's live, working Neovim configuration.
Treat it as read-only. Do not edit, format, stage, commit, or run tests that
mutate files or lifecycle state through that checkout unless the user explicitly
authorizes live-config changes for the current task.

Perform MkChad edits, tests, and Git operations in the parent workspace's
`/data0/matthew/Projects/mkchad/mkchad` submodule. This checkout is separate
from the live configuration.

Focused observational checks may read the live checkout or its managed runtime
state when the sprint requires them, but must not mutate either one. Never use
the live checkout as a convenient fallback when submodule setup or tests fail.

## Runtime Paths

Treat live runtime paths as read-only unless the selected sprint explicitly
requires focused mutation. In particular, do not inspect unrelated OpenCode
session data or credential paths.

Create every temporary directory beneath `/tmp/opencode-mkchad`, for example
`/tmp/opencode-mkchad/<purpose>`. Do not create temporary directories directly
under `/tmp`, under `/var/tmp`, or through an unscoped `mktemp` default.

## Safety

Preserve unrelated changes and untracked files in every repository. In
particular, do not modify MkChad's untracked `lazy-lock.json` unless the user
explicitly includes it. Never inspect or expose credentials, including
`~/.config/openai.token`, SSH material, provider tokens, and inherited secrets.
