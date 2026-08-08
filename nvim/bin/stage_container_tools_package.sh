#!/usr/bin/env bash
# Stage one verified architecture-specific package into an isolated image context.
set -euo pipefail

architecture=${1:?usage: stage_container_tools_package.sh ARCHITECTURE CONTEXT}
context=${2:?usage: stage_container_tools_package.sh ARCHITECTURE CONTEXT}
[[ $# == 2 && $context == /* && -d $context ]] || exit 64

case $architecture in
  x86_64) suffix=X86_64 ;;
  aarch64) suffix=AARCH64 ;;
  ppc64le) suffix=PPC64LE ;;
  *) printf 'unsupported container-tools architecture: %s\n' "$architecture" >&2; exit 64 ;;
esac

archive_var="CONTAINER_TOOLS_PACKAGE_ARCHIVE_${suffix}"
digest_var="CONTAINER_TOOLS_PACKAGE_SHA256_${suffix}"
version_var="CONTAINER_TOOLS_PACKAGE_VERSION_${suffix}"
commit_var="CONTAINER_TOOLS_PACKAGE_SOURCE_COMMIT_${suffix}"
libc_var="CONTAINER_TOOLS_PACKAGE_LIBC_${suffix}"
archive=${!archive_var:-}
digest=${!digest_var:-}
version=${!version_var:-}
source_commit=${!commit_var:-}
libc=${!libc_var:-}

[[ -n $archive && -n $digest && -n $version && -n $source_commit && -n $libc ]] || {
  printf 'missing explicit package input for %s\n' "$architecture" >&2
  exit 64
}
[[ $archive == /* && -f $archive ]] || { printf 'package archive must be an absolute regular file: %s\n' "$archive" >&2; exit 64; }

script_dir=$(dirname "$(realpath "$0")")
repo=$(realpath "$script_dir/../..")
child="$repo/container_tools"
[[ $(git -C "$child" status --porcelain) == '' ]] || {
  printf '%s\n' 'container-tools source is dirty; refusing package staging' >&2
  exit 78
}
[[ $(git -C "$child" rev-parse HEAD) == "$source_commit" ]] || {
  printf '%s\n' 'container-tools source commit does not match package input' >&2
  exit 78
}

work_root=$(mktemp -d /tmp/mkchad-v1/container-tools-c11/image-package-verify.XXXXXX)
staged_archive="$context/.container-tools-package.tar.gz.$$"
cleanup() {
  rm -rf -- "$work_root"
  [[ -z $staged_archive || ! -e $staged_archive ]] || rm -f -- "$staged_archive"
}
trap cleanup EXIT
[[ ! -e $context/container-tools-package.tar.gz && ! -e $staged_archive ]] || {
  printf '%s\n' 'container-tools package is already staged in the image context' >&2
  exit 78
}
cp -- "$archive" "$staged_archive"
[[ $(sha256sum "$staged_archive" | awk '{print $1}') == "$digest" ]] || {
  printf '%s\n' 'container-tools package changed while staging' >&2
  exit 78
}
"$child/scripts/verify-package.sh" \
  --archive "$staged_archive" --sha256 "$digest" --version "$version" \
  --source-commit "$source_commit" --architecture "$architecture" --libc "$libc" \
  --work-root "$work_root" >/dev/null

mv -- "$staged_archive" "$context/container-tools-package.tar.gz"
staged_archive=
printf '%s\n' "$digest" > "$context/container-tools-package.sha256"
printf '%s\n' "$version" > "$context/container-tools-package.version"
printf '%s\n' "$source_commit" > "$context/container-tools-package.source-commit"
printf '%s\n' "$architecture" > "$context/container-tools-package.architecture"
printf '%s\n' "$libc" > "$context/container-tools-package.libc"
