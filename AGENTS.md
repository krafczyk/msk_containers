# Workspace Guide

## Sprint Coordination Root

This repository is the coordination root for the optional OpenCode transport
sprint. The governing documents are:

- `docs/single-opencode-server/SPRINT_SPEC.md`
- `docs/single-opencode-server/SPRINT_CHECKLIST.md`
- `docs/threat_model.md`
- `docs/audit_policy.md`

The superseded TLS-only implementation baseline is archived under
`docs/archive/single-opencode-server-tls-baseline/`. Archived sprint documents
are historical evidence and are not governing documents for new work.

## Related Repositories

Only these repositories are part of this sprint:

- `/data1/matthew/Projects/msk_containers`
- MkChad, whose live checkout is `/home/matthew/.config/mkchad`
- `/data1/matthew/Projects/opencode.nvim`

Use the exact persistent paths above for `msk_containers` and `opencode.nvim`.
Use an isolated MkChad clone as required below. Do not enumerate other
directories under `/data1/matthew/Projects`, the user's home directory, or
unrelated repositories. Before editing a related repository, read its own
`AGENTS.md` if present.

Repository responsibilities:

- `msk_containers`: sprint documents, container integration, and evidence.
- MkChad clone: shared-server lifecycle and Neovim configuration integration.
- `opencode.nvim`: directory routing and lifecycle-hook implementation.

## MkChad Live Config Protection

`/home/matthew/.config/mkchad` is the user's live, working Neovim configuration.
Treat it as read-only. Do not edit, format, stage, commit, or run tests that
mutate files or lifecycle state through that checkout unless the user explicitly
authorizes live-config changes for the current task.

Before starting new MkChad implementation work, create a fresh clone of the
published MkChad repository beneath `/tmp/opencode/<purpose>/mkchad` and perform
all edits, tests, and Git operations in that clone. Clone the repository rather
than copying the live checkout so untracked files, runtime state, and local
secrets cannot enter the worktree. The chosen clone path is in scope for that
task and must be reported in implementation evidence.

Focused observational checks may read the live checkout or its managed runtime
state when the sprint requires them, but must not mutate either one. Never use
the live checkout as a convenient fallback when clone setup or tests fail.

## Runtime Paths

Runtime paths in `opencode.jsonc` are available for focused verification. Treat
them as read-only unless a sprint test explicitly requires mutation. In
particular, do not inspect unrelated OpenCode session data or credential paths.

Create every temporary directory beneath `/tmp/opencode`, for example
`/tmp/opencode/<purpose>`. Do not create temporary directories directly under
`/tmp`, under `/var/tmp`, or through an unscoped `mktemp` default.

## Safety

Preserve unrelated changes and untracked files in every repository. In
particular, do not modify MkChad's untracked `lazy-lock.json` unless the user
explicitly includes it. Never inspect or expose credentials, including
`~/.config/openai.token`, SSH material, provider tokens, and inherited secrets.
