# msk_containers Guide

## Purpose

This repository contains MkChad container images, launch scripts, and runtime
integration. It inherits the parent workspace's build, temporary-file, threat,
audit, commit, and testing policy.

## Package Selection Documentation

Update `docs/adr/002-package-selections.md` in the same change whenever a
directly selected container package or software component is added, removed,
upgraded, downgraded, moved to a different installation source, or given a
different architecture scope. This includes DNF, pip, npm, Cargo, and LuaRocks
packages as well as downloaded or source-built runtimes and tools. Transitive
dependency-only changes do not require an ADR update unless the repository
begins selecting that dependency directly.

## MkChad Live Config Protection

`~/.config/mkchad` is the user's live, working Neovim configuration. Treat it
as read-only. Do not edit, format, stage, commit, or run tests that mutate files
or lifecycle state through that checkout unless the user explicitly authorizes
live-config changes for the current task.

Use the `mkchad/` child checkout for MkChad edits, tests, and Git operations.
It is separate from the live configuration. Focused observational checks may
read live configuration or managed runtime state only when required, and must
not mutate either. Never use the live checkout as a convenient fallback when
submodule setup or tests fail.

## Runtime And Credential Safety

Treat live runtime paths as read-only unless the user explicitly requires a
focused mutation. Do not inspect unrelated OpenCode session data or credential
paths. Preserve unrelated changes and untracked files, including
`lazy-lock.json`; do not modify that file unless the user explicitly includes
it. Never inspect or expose credentials, including `~/.config/openai.token`,
SSH material, provider tokens, and inherited secrets.
