# Host Installation

`bin/install_nvim.sh` is the public installer for MkChad host launchers. Host
`container_tools` is installed separately from the deployment-selected source
checkout through normal CMake configure, build, and install commands. The
launcher installer accepts no source, archive, or package-identity inputs.

## Host Launcher Recovery

Use the public installer directly when an existing MkChad host launcher is
missing, damaged, or unable to return valid lifecycle status. Run these commands
from the trusted `msk_containers` checkout whose launcher revision should be
installed:

```bash
recovery_dir=$(mktemp -d "${TMPDIR:-/tmp}/mkchad-launcher-recovery.XXXXXX")
chmod 700 "$recovery_dir"
bin/install_nvim.sh --check --recovery-dir "$recovery_dir"
bin/install_nvim.sh --recovery-dir "$recovery_dir"
```

On an ACL-managed HPC system where the exact `$HOME` root is root-owned or
group-writable, explicitly enable the deployment trust profile for both manual
invocations:

```bash
MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1 bin/install_nvim.sh --check --recovery-dir "$recovery_dir"
MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1 bin/install_nvim.sh --recovery-dir "$recovery_dir"
```

The profile applies only to `$HOME`: it permits root or current-user ownership
and group write while still rejecting world write. Existing strict checks on
`.local`, `.local/bin`, outputs, locks, and recovery state remain in force. Use
it only when every group-class or ACL writer on `$HOME` is trusted.

If a supported filesystem presents directory ownership or write modes that
cannot satisfy even that scoped profile, the operator may explicitly disable
directory ownership and write-mode policy for one manual invocation:

```bash
bin/install_nvim.sh --no-directory-trust-checks --check --recovery-dir "$recovery_dir"
bin/install_nvim.sh --no-directory-trust-checks --recovery-dir "$recovery_dir"
```

This option treats every writer able to replace entries in `$HOME`, `.local`,
`.local/bin`, or the recovery directory as trusted for that invocation. It does
not permit directory symlinks or non-directories, unsafe output types or owners,
foreign-owned locks, or a recovery directory whose mode is not `0700`. Prefer
the narrower `MKCHAD_TRUST_GROUP_WRITABLE_ROOTS=1` profile whenever it works.

`--check` performs a read-only preflight. Apply records every replaced launcher
in the private recovery directory. Retain that directory until
`~/.local/bin/mkchad-opencode-server status --json` returns exactly one valid
JSON document and the interrupted deployment succeeds. This procedure does not
install or replace `container_tools`.

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

## Persistent MkChad Profile

`nvim`, `nvim_shell`, `mkchad`, and host `mkchad-opencode-server` select
SingularityCE before Apptainer when both are installed. All four launchers use
one persistent container profile: they bind the writable npm base and an
external `XDG_STATE_HOME` at the same path, inject the same MkChad XDG
environment, and run `mkchad-container-bootstrap` so the image selects its
architecture and Node-major npm prefix before the payload starts. Payload
command, environment, and arguments do not select a separate persistent
instance.

The shared profile forms its identity from `$HOME` rather than the caller's
working directory, preventing caller-directory automatic mounts from creating
a different persistent instance. The bootstrap restores each payload's caller
working directory before execution, so relative editor paths retain their
normal meaning when that directory is visible through the common mount plan.
Generic `nvim` applies the caller's nonempty `NVIM_APPNAME` only inside its
payload; when unset or empty it starts generic Neovim. `nvim_shell` similarly
removes the profile's MkChad app name before starting `/bin/bash`. With no
arguments it starts an interactive shell; otherwise it forwards arguments such
as `-c COMMAND` without changing the persistent profile identity.
`mkchad-opencode-server status` remains a foreground diagnostic path and does
not share or create a persistent instance. Its host evidence reports the
selected runtime family and the identity of the exact selected executable.

## Release Deployer Handoff

The schema-2 deployer calls the pinned `msk_containers` checkout with a fresh,
private mode-`0700` directory for launcher preflight and apply:

```bash
bin/install_nvim.sh --check --recovery-dir /private/deployment-recovery
bin/install_nvim.sh --recovery-dir /private/deployment-recovery
```

`--check` validates launcher outputs without creating target paths. Recovery is
private and records replaced launcher bytes. Release deployment independently
checks out its pinned `container_tools` component, installs it beneath
`${HOME}/.local` with CMake, and verifies its compile-time JSON identity.

## Image Construction

The architecture image-build scripts invoke Docker Buildx or
SingularityCE/Apptainer directly. Dockerfiles build their reviewed,
full-commit-pinned `container-tools` checkout with CMake and install it under
`/opt/msk/container-tools`; SIF definitions only convert the corresponding
Docker archive. Image construction never selects a host `container-tools`
package, `CT_ROOT`, archive, or package identity file.

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

## Selected-Root Runtime Evidence

`tests/container_tools_selected_root_runtime_test.sh` is the parent-side
selected-root evidence harness. Its deterministic `--self-test` delegates the
closed `container-tools.runtime-evidence/v1` report and exact-cleanup checks to
the finalized `container_tools` child, then verifies the expected host and
in-container package identities, matching product major, and image digest. Its
fake Cargo, Slurm, and alternate-root repair cases prove the parent admission
and exact-once dispatch boundary only.

```bash
bash tests/container_tools_selected_root_runtime_test.sh --self-test
```

`--run-native` refuses cross-major package identities before it probes a
candidate, and returns `77` when the requested local runtime or immutable image
candidate is unavailable. It does not claim Bash parity or final-image
operability: the child runner still requires the retained image and a
release-specific selected-root runner before either claim can be accepted.
