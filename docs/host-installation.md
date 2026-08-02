# Host Installation

`bin/install_nvim.sh` is the public installer for MkChad host launchers and
their container-tool launchers. Normal callers use this interface rather than
copying individual outputs.

## Release Deployer Handoff

The schema-2 `mkchad-release` deployer calls the pinned checkout with a fresh,
private mode-`0700` directory for both preflight and apply:

```bash
bin/install_nvim.sh --check --recovery-dir /private/deployment-recovery
bin/install_nvim.sh --recovery-dir /private/deployment-recovery
```

`--check` validates sources and outputs without creating target paths. Apply
rechecks under its per-target lock and leaves byte-identical mode-`0755` outputs
untouched. The directory is an ephemeral caller input used by the existing
installer replacement interface; it is not deployment evidence and must not be
reused for another apply.

`bin/install_tools.sh` exposes the same `--check` and `--recovery-dir`
interface. `install_nvim.sh` remains the public entrypoint when both launchers
and tools are needed.

## Transported Images

For a raw image outside its source checkout, the image installer requires its
exact source revision:

```bash
nvim/bin/install_nvim_container --source-revision FULL_40_CHARACTER_SHA IMAGE
```

The schema-2 deployer first invokes the same interface with `--dry-run`, then
runs apply only after complete preflight. Managed image names retain their
existing validation and do not accept a source revision override.
