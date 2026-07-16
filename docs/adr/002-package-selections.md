# ADR 002: Neovim Container Package Selections

- Status: Accepted
- Date: 2026-07-16

## Context

The Neovim container is a Fedora-based development environment built for
x86_64, aarch64, and ppc64le. It supplies Neovim, language runtimes, language
servers, build tools, OpenCode, and supporting command-line tools. The image is
used both interactively and to verify MkChad and Neovim plugin behavior.

The package list has grown incrementally across three architecture-specific
Dockerfiles. Without a central record, it is difficult to determine why a tool
is present, which architecture receives it, or whether a new package duplicates
an existing capability.

This ADR records every package or software component selected directly by the
Neovim Dockerfiles and the additional Lua/browser packages accepted for the
next image update. It does not enumerate transitive RPM, pip, LuaRock, npm, or
source-build dependencies because those are resolved by external package
managers and can change without a direct repository decision.

## Decision

Maintain the package selections below. New direct dependencies must be added to
this ADR, or supersede it, when their purpose or version policy differs from an
existing selection.

The architecture markers used below are:

- All: x86_64, aarch64, and ppc64le.
- x86: x86_64 only.
- ARM: aarch64 only.
- PPC: ppc64le only.

## Fedora Base Images

| Architecture | Base selection | Reason |
| --- | --- | --- |
| x86_64 | Fedora 43, pinned by image digest | Provides a repeatable primary image baseline and current development packages. |
| aarch64 | Fedora Rawhide | Provides sufficiently current native packages for the secondary ARM image, but currently follows a floating base. |
| ppc64le | Fedora Rawhide | Provides package availability for the less common Power architecture, but currently follows a floating base. |

The operating-system entries below are direct DNF install operands. Most are
Fedora package names, but DNF may satisfy an executable capability such as
`pgrep` or `clangd` through its provider package.

## Build and Source Management

| Packages | Architectures | Reason |
| --- | --- | --- |
| `git` | All | Clones Neovim, LuaJIT, Lua Language Server, JDTLS, and source-installed Python packages; also supports normal development workflows. |
| `wget`, `curl` | All | Download source archives and metadata. `curl` is used directly by the Dockerfiles; `wget` remains available for interactive development and upstream installers. |
| `gcc`, `gcc-c++` | All | Compile C and C++ dependencies, LuaJIT, Neovim, native Python extensions, and other source packages. |
| `make`, `cmake`, `ninja-build` | All | Provide the build systems used by LuaJIT, Neovim, Lua Language Server, and native dependencies. |
| `libstdc++-static` | All | Supplies static C++ runtime objects required by source builds that produce self-contained tooling. |
| `redhat-rpm-config` | All | Supplies Fedora compiler and linker configuration expected when building native Python and RPM-oriented source packages. |
| `rust`, `cargo` | All | Support Rust-based development tools and source installation of selected Rust utilities, including StyLua. |
| `zip`, `unzip`, `tar` | All | Extract and create the archive formats used by downloaded toolchains, language servers, and development workflows. |
| `gettext` | All | Provides translation and message-catalog tooling used by the Neovim build. |

## Shell and Command-Line Utilities

| Packages | Architectures | Reason |
| --- | --- | --- |
| `zsh` | All | Supplies the interactive shell expected by the MkChad environment. |
| `which` | All | Supports executable discovery in scripts and interactive diagnostics. |
| `ripgrep` | All | Supplies fast recursive text search used by Neovim plugins and development agents. |
| `jq` | x86, ARM | Supports machine-readable JSON inspection in development and integration workflows. It is not currently selected in the PPC Dockerfile. |
| `gh` | x86 | Supplies the GitHub CLI used by repository and future Sprint Loop CI workflows in the primary image. |
| `pgrep`, `procps-ng` | x86 | Supply process discovery and process-inspection commands used by server lifecycle and diagnostic workflows. `pgrep` is an executable capability provided by `procps-ng`, so the two DNF operands are redundant but recorded as written. |
| `iproute`, `lsof` | x86 | Supply network/interface and open-file diagnostics for local OpenCode server troubleshooting. |

The x86-only diagnostic selections reflect the current primary development
image. They are not a claim that the secondary images have equivalent lifecycle
diagnostics.

## Locale Support

| Packages | Architectures | Reason |
| --- | --- | --- |
| `glibc-locale-source`, `glibc-langpack-en`, `glibc-gconv-extra` | All | Build and provide the `en_US.UTF-8` locale used by Neovim, language servers, and development tools. |

Each image generates `en_US.UTF-8` with `localedef` after these packages are
installed.

## Python Runtime and Development

| Packages | Architectures | Reason |
| --- | --- | --- |
| `python3` | All | Provides the Python runtime used by editor integrations, language tooling, and project development. |
| `python3-devel` | All | Supplies Python headers needed to compile native extensions. |
| `python3-pip` | All | Installs the selected Python packages into the image. |
| `python3-virtualenv` | All | Supports isolated project environments and clean-install verification. |
| `libffi-devel` | All | Supplies FFI headers required by Python packages and native integrations. |
| `openssl-devel` | All | Supplies TLS and cryptographic headers for native Python and service integrations. |

The Dockerfiles directly install these Python packages with pip:

| Python package | Architectures | Version policy | Reason |
| --- | --- | --- | --- |
| `pydantic` | All | Tracks the upstream `main` branch | Provides typed data validation used by Python development and provider tooling. This floating source should be pinned separately for reproducible builds. |
| `openai` | All | Unpinned | Provides the OpenAI Python client for provider-facing development and scripts. |
| `jedi` | All | Unpinned | Provides Python completion and static-analysis support. |
| `pynvim` | All | Unpinned | Provides the Python client and remote-plugin integration for Neovim. |
| `python-lsp-server[all]` | All | Unpinned, including its `all` extra | Provides a Python language server and its complete optional analysis, formatting, and linting feature set. |

The broad and floating pip selections favor a batteries-included interactive
environment over a minimal or fully reproducible Python dependency closure.

## Node.js and npm Packages

Node.js is downloaded from nodejs.org rather than installed through DNF so each
architecture can use an explicitly selected upstream build.

| Architecture | Node.js version | Archive architecture |
| --- | --- | --- |
| x86_64 | `22.22.3` | `linux-x64` |
| aarch64 | `20.19.3` | `linux-arm64` |
| ppc64le | `20.19.3` | `linux-ppc64le` |

The following npm packages are installed globally into the immutable image
baseline:

| npm package | Architectures | Version policy | Reason |
| --- | --- | --- | --- |
| `neovim` | All | Unpinned | Provides the Node.js client used by Neovim remote plugins and integrations. |
| `basedpyright` | All | Unpinned | Provides Python type checking and language-server support. |
| `opencode-ai` | All | `1.17.20` on x86 and ARM; `1.17.18` on PPC | Provides the OpenCode CLI/server used by MkChad. The explicit version prevents an uncontrolled latest-version change during image construction. |

At runtime, MkChad bind-mounts an architecture-neutral writable npm parent at
`/opt/msk/npm-global`. The container definitions intend to select an
architecture- and Node-major-specific child and place it ahead of the immutable
baseline. That selection currently does not occur because launcher `--env`
values are applied after `%environment` is evaluated, so the conditional cannot
see `MSK_NPM_GLOBAL_BASE`. Until the runtime integration is corrected, the
immutable npm baseline remains the active selection.

## Java and JDTLS

| Packages | Architectures | Reason |
| --- | --- | --- |
| `java-21-openjdk-devel` | All | Provides the Java 21 runtime and compiler required by Java development and JDTLS. |
| `java-21-openjdk-jmods` | All | Provides Java module files required when building or running modular Java tooling. |
| `maven` | All | Supports Java project development and Maven-based editor workflows. The JDTLS source builds use their repository-owned `mvnw` wrapper rather than this Fedora package. |

JDTLS is installed separately from Fedora packages:

| Architecture | Selection | Reason |
| --- | --- | --- |
| x86_64 | Eclipse JDTLS milestone `1.56.0` archive | Uses an identified milestone and verifies the downloaded archive checksum before extraction. |
| aarch64 | Current default branch of `eclipse-jdtls/eclipse.jdt.ls` | Builds a native-compatible repository artifact where the milestone archive path is not used. |
| ppc64le | Current default branch of `eclipse-jdtls/eclipse.jdt.ls` | Builds JDTLS for an architecture without the selected x86 archive path. |

The ARM and PPC selections are floating and should be pinned when a validated
revision is identified.

## Neovim Native Dependencies and Tools

| Packages | Architectures | Reason |
| --- | --- | --- |
| `libvterm`, `libvterm-devel` | All | Provide the terminal-emulation library and headers used by Neovim. |
| `msgpack`, `msgpack-devel` | All | Provide MessagePack runtime support and headers used by Neovim RPC. |
| `clangd` | All | Provides C and C++ language-server support in the editor. DNF resolves this executable capability through its Fedora provider package. |
| `xclip` | x86 | Integrates Neovim with X11 clipboard commands in the primary image. |
| `xsel` | ARM, PPC | Provides the equivalent X11 clipboard integration selected for the secondary images. |

Each container definition currently sets `CC=clang`, but the Dockerfiles select
only the `clangd` capability. Fedora satisfies that capability with
`clang-tools-extra`, which does not provide the `clang` compiler. The `CC`
selection is therefore currently unsatisfied. A future change must either add
the `clang` package or select an installed compiler such as GCC and update this
ADR in the same change.

## Source-Built Neovim Stack

The following components are built or installed directly from upstream sources
rather than selected as Fedora packages.

| Component | Architectures | Version policy | Reason |
| --- | --- | --- | --- |
| OpenResty LuaJIT | All | Floating branch `v2.1-agentzh` | Provides a common LuaJIT-compatible runtime, including PPC64LE interpreter support. See ADR 001. |
| Neovim | x86 | Tag `v0.12.4` | Provides the current primary editor and satisfies the Sprint Loop plugin's Neovim 0.12 minimum. |
| Neovim | ARM, PPC | Tag `v0.11.2` | Provides the currently validated secondary-architecture editor baseline. It does not satisfy plugins that require Neovim 0.12. |
| Lua Language Server | x86 | Tag `3.17.1` | Provides Lua diagnostics, completion, and language intelligence. |
| Lua Language Server | ARM, PPC | Tag `3.15.0` | Provides the currently selected secondary-architecture Lua language tooling. ARM uses a modified build sequence because its upstream tests fail under the cross-build environment. |

## Accepted Additions

The following selections are accepted by this ADR but are not yet present in
the Dockerfiles. The image update that installs them must preserve the version
and scope decisions below or update this ADR.

| Tool | Installation source | Version policy | Initial scope | Reason |
| --- | --- | --- | --- | --- |
| StyLua | Cargo crate `stylua` | Pin `2.5.2` and install with `--locked` | All | Provides deterministic Lua formatting and `stylua --check`. Building with the existing Cargo toolchain avoids architecture-specific release binaries. |
| LuaRocks | Fedora package `luarocks` | Fedora base version | All | Installs and manages the selected Lua linter and its Lua dependencies. |
| Luacheck | LuaRock `luacheck` | Pin `1.2.0-1` | All | Detects undefined globals, unused values, and other Lua defects not covered by formatting. |
| `xdg-utils` | Fedora package | Fedora base version | x86 initially | Provides `xdg-open`, the Linux URL-handler interface used by Neovim's default `vim.ui.open()` path. |
| Chromium | Fedora package `chromium` | Fedora security-update stream | x86 initially | Provides an interactive browser for operator-driven OpenCode session-opening verification. |
| NSS tools | Fedora package `nss-tools` | Fedora base version | x86 initially | Provides `certutil` for an isolated NSS certificate database used to prepare and verify private-CA browser trust. |

StyLua and Luacheck require repository-owned configuration and documented check
commands. Installing them does not itself define a formatting or lint policy.

`xdg-utils` supplies URL dispatch but not a browser. Chromium is therefore
selected as well for a self-contained x86 image. Installing `nss-tools` does not
trust a certificate automatically; private-CA tests must import a disposable CA
into an isolated profile and must not disable certificate verification.

Browser package availability and runtime behavior must be proven before these
browser selections are extended to aarch64 or ppc64le.

## Packages Not Selected

- Playwright and Puppeteer are not selected because no browser-automation suite
  currently exists, their downloaded browser model is a poor fit for Fedora and
  ppc64le, and they duplicate the selected system browser.
- Selenium and `chromedriver` are not selected because WebDriver is unnecessary
  for the current operator-driven browser demonstration.
- `chromium-headless` is not selected because it does not satisfy the current
  interactive demonstration and would duplicate Chromium.
- Xvfb is not selected because no headed browser automation is being run without
  a display.
- Selene is not selected because it would duplicate Luacheck without satisfying
  the selected Luacheck verification command.
- A second Lua runtime is not selected for linting. LuaRocks and Luacheck should
  use the image's compatible Lua environment rather than introducing a separate
  project runtime without a demonstrated need.

## Consequences

- The image remains a broad development environment rather than a minimal
  runtime image.
- Source compilers, headers, and package managers remain in the final image so
  users can build native editor tooling interactively.
- Architecture-specific package differences are intentional but must remain
  visible; a successful x86 build does not prove parity on ARM or PPC.
- The x86 image is the only current architecture that satisfies Neovim 0.12
  requirements.
- Chromium will materially increase image size and the frequency of
  security-driven rebuilds.
- Several current pip and source selections float. Builds are not fully
  reproducible until those inputs and the Rawhide bases are pinned.
- `python-lsp-server[all]` installs a large transitive Python feature set that is
  intentionally not duplicated in this direct-selection inventory.
- DNF, pip, npm, and LuaRocks continue to resolve transitive dependencies. Their
  resolved package lists should be captured as build artifacts when exact image
  provenance is required.

## Alternatives Considered

### Use Only Distribution Packages

Rejected because the required Neovim, OpenCode, Node.js, LuaJIT PPC64LE support,
and language-server versions are not consistently available from one Fedora
repository across all architectures.

### Remove Build Dependencies from the Final Image

Rejected for the current development-container model because users and editor
package managers need to compile native tools at runtime. A multi-stage minimal
runtime image may be evaluated separately.

### Require Exact Architecture Parity

Rejected as an immediate rule because upstream binary and package availability
differs across x86_64, aarch64, and ppc64le. Differences must be documented and
validated rather than hidden.

### Use Only Lua Language Server for Lua Verification

Rejected because Lua Language Server does not enforce formatting and does not
replace a focused repository-configured linter.

### Use Only the Host Browser

Not selected as the baseline because it leaves URL-opener and browser
availability outside the image. Explicit and verified host-browser integration
remains acceptable for deployments that do not want Chromium in the image.

## References

- `nvim/x86/nvim_container_x86.dockerfile`
- `nvim/aarch64/nvim_container_aarch64.dockerfile`
- `nvim/ppc64le/nvim_container_ppc64le.dockerfile`
- `nvim/x86/nvim_container_x86.def`
- `nvim/aarch64/nvim_container_aarch64.def`
- `nvim/ppc64le/nvim_container_ppc64le.def`
- `nvim/bin/mkchad`
- [StyLua 2.5.2](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.5.2)
- [Luacheck 1.2.0-1 rockspec](https://luarocks.org/luacheck-1.2.0-1.rockspec)
- [Fedora LuaRocks package](https://packages.fedoraproject.org/pkgs/luarocks/luarocks/)
- [Fedora xdg-utils package](https://packages.fedoraproject.org/pkgs/xdg-utils/xdg-utils/)
- [Fedora Chromium package](https://packages.fedoraproject.org/pkgs/chromium/chromium/)
- [Fedora nss-tools package](https://packages.fedoraproject.org/pkgs/nss/nss-tools/)
