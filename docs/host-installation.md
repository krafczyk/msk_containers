# Host Installation

`bin/install_nvim.sh` is the authoritative installer for MkChad host launchers
and the container-tool launchers they use. Do not copy its individual outputs
from deployment metadata or call lower-level copies for a normal host install.

## Preflight And Apply

Run a non-mutating preflight before a deployment action:

```bash
bin/install_nvim.sh --check --recovery-dir /private/deployment-recovery
```

The installer validates every source and output, including delegated
`install_tools.sh` outputs. It rejects unsafe parents, symlinks, directories,
and files not owned by the current user. `--check` never creates target paths.

For apply, pass the same private, existing mode-`0700` recovery directory when
an existing launcher may need replacement:

```bash
bin/install_nvim.sh --recovery-dir /private/deployment-recovery
```

The installer rechecks under one per-target lock, retains prior bytes before
replacement, writes same-directory temporary files, and atomically replaces
only current-user-owned regular files. Byte-identical mode-`0755` outputs are
left untouched. Recovery directories are caller-owned deployment evidence and
must not be reused for another apply.

`bin/install_tools.sh` exposes the same `--check` and `--recovery-dir` contract
for its container-tool output set. `install_nvim.sh` remains the public entry
point when both launchers and tools are required.

The release deployer may set `MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1` after an
operator explicitly trusts every group-class or ACL writer on an ACL-managed
home. Under that setting, only `HOME` may be root- or current-user-owned and
group-writable. World-write access, foreign ownership, `.local` and `bin`
permissions, outputs, locks, and recovery directories retain their strict
checks. The default value is `0`; any value other than `0` or `1` is rejected.
This environment variable is an internal deployment handoff, not a substitute
for the public release-bootstrap trust option.

## Transported Images

`nvim/bin/install_nvim_container` continues to derive the revision for a raw
build image from its enclosing Git checkout. A raw image copied outside that
checkout requires its exact source commit explicitly:

```bash
nvim/bin/install_nvim_container --source-revision FULL_40_CHARACTER_SHA IMAGE
```

The option is valid only for raw `nvim_container_<architecture>.sif` images.
Managed image names retain their existing validation and do not accept a source
revision override.
