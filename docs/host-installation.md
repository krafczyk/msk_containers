# Host Installation

`bin/install_nvim.sh` is the public installer for MkChad host launchers and a
verified container-tools package. It requires one explicit package identity:
archive, SHA-256, version, source commit, architecture, and libc family. The
same values may be passed as `--container-tools-*` options or as the
`CONTAINER_TOOLS_HOST_PACKAGE_*` environment variables used by deployment.
Normal callers use this interface rather than copying individual outputs.

## Container Tool Override

Host launchers normally resolve `ct_*.sh` tools from the complete package in
`~/.local/bin`. Set `CT_ROOT` to choose another complete package `bin/`
directory:

```bash
CT_ROOT=/opt/container-tools/bin mkchad
```

`CT_ROOT` must be an absolute complete package `bin/` directory containing
`container-tools` and all five compatibility scripts. Raw checkouts and partial
packages fail without falling back to co-located tools. An unset or empty
`CT_ROOT` preserves co-located lookup. The override affects only container-tool
dispatch, not MkChad launchers, bootstrap scripts, image lifecycle commands, or
configuration, cache, state, and persistent-instance paths.

## Release Deployer Handoff

The schema-2 `mkchad-release` deployer calls the pinned checkout with a fresh,
private mode-`0700` directory for both preflight and apply:

```bash
bin/install_nvim.sh --check --container-tools-archive PACKAGE ...
bin/install_nvim.sh --recovery-dir /private/deployment-recovery --container-tools-archive PACKAGE ...
```

`--check` validates archive identity without creating target paths. Apply uses
the child package installer transaction for `${HOME}/.local`, then installs
launcher files under the same parent lock. Recovery is private and records
replacement state; the two managed directory updates are recoverable rather
than claimed to be one impossible multi-directory atomic rename.

`bin/install_tools.sh` exposes the same `--check` and `--recovery-dir`
interface. `install_nvim.sh` remains the public entrypoint when both launchers
and tools are needed.

## Writable npm Cleanup

`nvim_clear_npm_global` removes the complete host-side writable npm root at
`~/.local/share/msk_containers/npm-global`, including every architecture and
Node-major prefix. Stop MkChad editors and the managed OpenCode service before
running it. The next launch recreates the root, and command resolution falls
back to the immutable packages in the active image until packages are installed
there again.

```bash
nvim_clear_npm_global --dry-run
nvim_clear_npm_global
```

The command accepts no path override. It refuses symbolic, foreign-owned, or
group/world-writable managed paths and preserves sibling data under
`~/.local/share/msk_containers`.

## Transported Images

For a raw image outside its source checkout, the image installer requires its
exact source revision:

```bash
nvim/bin/install_nvim_container --source-revision FULL_40_CHARACTER_SHA IMAGE
```

The schema-2 deployer first invokes the same interface with `--dry-run`, then
runs apply only after complete preflight. Managed image names retain their
existing validation and do not accept a source revision override.
