# Workspace Guide

## Sprint Coordination

The parent MkChad development workspace is the coordination root for the
optional OpenCode transport sprint. The governing documents are:

- `../docs/sprints/single-opencode-server/2/sprint_spec.md`
- `../docs/sprints/single-opencode-server/2/sprint_checklist.md`
- `../docs/sprints/single-opencode-server/2/threat_model.md`
- `../docs/sprints/single-opencode-server/2/audit_policy.md`

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

- `msk_containers`: sprint documents, container integration, and evidence.
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

Runtime paths in `opencode.jsonc` are available for focused verification. Treat
them as read-only unless a sprint test explicitly requires mutation. In
particular, do not inspect unrelated OpenCode session data or credential paths.

Create every temporary directory beneath `/tmp/opencode-mkchad`, for example
`/tmp/opencode-mkchad/<purpose>`. Do not create temporary directories directly
under `/tmp`, under `/var/tmp`, or through an unscoped `mktemp` default.

## Safety

Preserve unrelated changes and untracked files in every repository. In
particular, do not modify MkChad's untracked `lazy-lock.json` unless the user
explicitly includes it. Never inspect or expose credentials, including
`~/.config/openai.token`, SSH material, provider tokens, and inherited secrets.
