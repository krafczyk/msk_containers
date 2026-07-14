# Workspace Guide

## Sprint Coordination Root

This repository is the coordination root for the single persistent OpenCode
server sprint. The governing documents are:

- `docs/single-opencode-server/SPRINT_SPEC.md`
- `docs/single-opencode-server/SPRINT_CHECKLIST.md`
- `docs/threat_model.md`
- `docs/audit_policy.md`

## Related Repositories

Only these repositories are part of this sprint:

- `/data1/matthew/Projects/msk_containers`
- `/home/matthew/.config/mkchad`
- `/data1/matthew/Projects/opencode.nvim`

Use these exact paths. Do not enumerate other directories under
`/data1/matthew/Projects`, the user's home directory, or unrelated repositories.
Before editing a related repository, read its own `AGENTS.md` if present.

Repository responsibilities:

- `msk_containers`: sprint documents, container integration, and evidence.
- `mkchad`: shared-server lifecycle and Neovim configuration integration.
- `opencode.nvim`: directory routing and lifecycle-hook implementation.

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
