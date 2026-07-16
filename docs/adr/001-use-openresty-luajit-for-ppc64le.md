# ADR 001: Use OpenResty's LuaJIT Branch for PPC64LE

- Status: Accepted (retrospective)
- Date: 2026-07-16
- Decision introduced: 2025-04-11

## Context

The Neovim container is built for x86_64, aarch64, and ppc64le. Neovim needs a
LuaJIT-compatible runtime on each architecture, and using the same LuaJIT source
across the images reduces architecture-specific differences.

The initial container definitions selected OpenResty's `luajit2` repository and
its `v2.1-agentzh` branch for all three architectures. The repository history
does not contain an explicit rationale for that selection, so this ADR records
the rationale reconstructed from the selected sources and their architecture
support.

At the time of the decision, upstream LuaJIT `v2.1` explicitly rejected 64-bit
PowerPC targets with `#error "No support for PPC64"`. OpenResty's branch included
a PPC64 support patch based on upstream work and Fedora's PPC64 patch set. That
patch added PPC64 and PPC64LE VM support, ELFv2 handling, unwinding fixes, and
PowerPC-specific correctness fixes.

OpenResty's branch disables the JIT compiler on PPC64 because its PPC64 JIT
backend is not implemented. It still provides the LuaJIT interpreter and FFI,
which are sufficient for Neovim's Lua runtime on ppc64le. The x86_64 and
aarch64 builds retain their normal JIT support.

The name `v2.1-agentzh` identifies a maintained branch, not an immutable release
version. The current Dockerfiles therefore follow the branch tip at build time.

## Decision

Use `https://github.com/openresty/luajit2` branch `v2.1-agentzh` as the LuaJIT
source for the x86_64, aarch64, and ppc64le Neovim images.

This choice is primarily an architecture-compatibility decision: it provides a
common LuaJIT-compatible runtime while retaining PPC64LE support that upstream
LuaJIT `v2.1` did not provide.

Keep the PPC64LE limitation explicit: the VM runs in interpreter mode on that
architecture because JIT compilation is disabled.

Pinning the source to an immutable reviewed commit or release tag is a separate
reproducibility improvement. Any future pin must retain successful native or
emulated builds and Neovim startup checks on all three supported architectures.

## Consequences

- The ppc64le image can use a LuaJIT-compatible runtime instead of maintaining
  a separate Lua implementation or dropping the architecture.
- All Neovim images use one LuaJIT source and broadly consistent Lua and FFI
  behavior.
- PPC64LE does not receive JIT performance benefits.
- The OpenResty branch contains changes beyond PPC64 support, so upgrades need
  validation against Neovim and the supported plugin set.
- Following a mutable branch reduces build reproducibility until the source is
  pinned to an immutable revision.
- Replacing this implementation requires explicit ppc64le evidence; a successful
  x86_64-only build is insufficient.

## Alternatives Considered

### Upstream LuaJIT `v2.1`

Rejected for the original cross-architecture baseline because its source
explicitly rejected PPC64. Upstream support must be reevaluated from source and
with a working ppc64le build before this decision is superseded.

### Fedora's LuaJIT Package

Not selected because the container builds its Neovim Lua runtime consistently
from source across architectures, and package availability or patch content may
vary between the pinned Fedora release and Rawhide images.

### Standard Lua Without LuaJIT

Rejected because it would diverge from Neovim's expected LuaJIT-oriented runtime
and FFI behavior and would create a separate compatibility path for ppc64le.

### Drop PPC64LE Support

Rejected because ppc64le is an intentional target of the container repository.

## References

- `nvim/x86/nvim_container_x86.dockerfile`
- `nvim/aarch64/nvim_container_aarch64.dockerfile`
- `nvim/ppc64le/nvim_container_ppc64le.dockerfile`
- Repository commits `8b7f8ff`, `807fe6b`, and `b09a199`
- [OpenResty LuaJIT branch](https://github.com/openresty/luajit2/tree/v2.1-agentzh)
- [OpenResty PPC64 support commit](https://github.com/openresty/luajit2/commit/2763a421d6219c8cb2bbd39246de619dc796bab6)
- [Upstream LuaJIT architecture status](https://luajit.org/status.html#architectures)
