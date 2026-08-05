#!/usr/bin/env bash
# Host-bridge backend runtime smoke, schema mkchad.host-bridge-backend-runtime/v1.
#
# Responsibility: prove each packaged backend separately from whether this runtime
# permits its host-dependent mechanism. A valid invocation emits exactly one JSON
# object and exits 0, including missing, malformed, timed-out, or denied backends.
# Help writes usage to stdout and exits 0. Invalid arguments exit 2, write
# concise usage to stderr, and emit no JSON.
#
# Parameters: --bwrap and --proot accept absolute executable paths for fixtures;
# --timeout accepts 1-60 seconds; --architecture accepts x86_64/amd64 or
# aarch64/arm64; --runtime-kind accepts docker, sif, direct, or unknown.
# Reasons are bounded to missing, invalid-version, timeout, operation-failed, and
# operational. Version output and backend stdout/stderr are never reported.
#
# Side effects: creates a mode-0700 temporary directory under ${TMPDIR:-/tmp} for
# bounded command captures, then removes it on exit. It reads no live state or
# credentials. Docker example: docker run --rm --mount
# type=bind,src="$PWD/tests",dst=/tests,readonly image
# /tests/host_bridge_backend_runtime_test.sh --runtime-kind docker.
# SIF example: apptainer exec --bind "$PWD/tests:/tests:ro" image.sif /tests/host_bridge_backend_runtime_test.sh --runtime-kind sif.
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: host_bridge_backend_runtime_test.sh [--bwrap ABSOLUTE_PATH] [--proot ABSOLUTE_PATH] [--timeout 1..60] [--architecture x86_64|amd64|aarch64|arm64] [--runtime-kind docker|sif|direct|unknown]'
}

normalize_architecture() {
  case $1 in
    x86_64|amd64) printf '%s\n' x86_64 ;;
    aarch64|arm64) printf '%s\n' aarch64 ;;
    *) return 1 ;;
  esac
}

require_absolute_path() {
  [[ $1 == /* && $1 != *$'\n'* ]]
}

bwrap_path=
proot_path=
timeout_seconds=5
architecture=
runtime_kind=direct

while (( $# > 0 )); do
  case $1 in
    --bwrap)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      require_absolute_path "$2" || { usage >&2; exit 2; }
      bwrap_path=$2
      shift 2
      ;;
    --proot)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      require_absolute_path "$2" || { usage >&2; exit 2; }
      proot_path=$2
      shift 2
      ;;
    --timeout)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      if ! [[ $2 =~ ^[1-9][0-9]*$ ]] || (( $2 > 60 )); then
        usage >&2
        exit 2
      fi
      timeout_seconds=$2
      shift 2
      ;;
    --architecture)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      architecture=$(normalize_architecture "$2") || { usage >&2; exit 2; }
      shift 2
      ;;
    --runtime-kind)
      (( $# >= 2 )) || { usage >&2; exit 2; }
      case $2 in
        docker|sif|direct|unknown) runtime_kind=$2 ;;
        *) usage >&2; exit 2 ;;
      esac
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z $architecture ]]; then
  architecture=$(normalize_architecture "$(uname -m)") || architecture=unknown
fi

if [[ -z $bwrap_path ]]; then
  bwrap_path=$(command -v bwrap || true)
fi
if [[ -z $proot_path ]]; then
  proot_path=$(command -v proot || true)
fi

tempdir=$(mktemp -d "${TMPDIR:-/tmp}/host-bridge-backend-runtime.XXXXXX")
chmod 700 "$tempdir"
trap 'rm -rf -- "$tempdir"' EXIT

run_bounded() {
  local label=$1
  shift

  if timeout --signal=TERM --kill-after=1 "$timeout_seconds" "$@" \
    > "$tempdir/$label.stdout" 2> "$tempdir/$label.stderr"; then
    run_status=0
  else
    run_status=$?
  fi
}

status_reason() {
  case $1 in
    124|137) printf '%s\n' timeout ;;
    *) printf '%s\n' operation-failed ;;
  esac
}

bwrap_installed=false
bwrap_operational=false
bwrap_reason=missing
bwrap_version_valid=false
proot_installed=false
proot_operational=false
proot_reason=missing
proot_version_valid=false

if [[ -n $bwrap_path && -x $bwrap_path ]]; then
  run_bounded bwrap-version "$bwrap_path" --version
  bwrap_version=$(<"$tempdir/bwrap-version.stdout")
  if (( run_status == 0 )) && [[ $bwrap_version =~ ^bubblewrap[[:space:]][0-9]+(\.[0-9]+){1,2}$ ]]; then
    bwrap_installed=true
    bwrap_version_valid=true
    run_bounded bwrap-operation "$bwrap_path" \
      --unshare-user --uid 0 --gid 0 --ro-bind / / --dev /dev --proc /proc -- /bin/true
    if (( run_status == 0 )); then
      bwrap_operational=true
      bwrap_reason=operational
    else
      bwrap_reason=$(status_reason "$run_status")
    fi
  elif (( run_status == 124 || run_status == 137 )); then
    bwrap_reason=timeout
  else
    bwrap_reason=invalid-version
  fi
fi

if [[ -n $proot_path && -x $proot_path ]]; then
  run_bounded proot-version "$proot_path" --version
  if (( run_status == 0 )) \
    && grep -Eq ' v5\.4\.0(-bd5a5f63)?$' "$tempdir/proot-version.stdout"; then
    proot_installed=true
    proot_version_valid=true
    run_bounded proot-operation "$proot_path" -r / /bin/true
    if (( run_status == 0 )); then
      proot_operational=true
      proot_reason=operational
    else
      proot_reason=$(status_reason "$run_status")
    fi
  elif (( run_status == 124 || run_status == 137 )); then
    proot_reason=timeout
  else
    proot_reason=invalid-version
  fi
fi

python3 - "$architecture" "$runtime_kind" \
  "$bwrap_installed" "$bwrap_operational" "$bwrap_reason" "$bwrap_version_valid" \
  "$proot_installed" "$proot_operational" "$proot_reason" "$proot_version_valid" <<'PY'
import json
import sys

architecture, runtime_kind, *values = sys.argv[1:]

def backend(offset):
    installed, operational, reason, version_valid = values[offset:offset + 4]
    return {
        "installed": installed == "true",
        "operational": operational == "true",
        "reason": reason,
        "version_valid": version_valid == "true",
    }

print(json.dumps({
    "schema": "mkchad.host-bridge-backend-runtime/v1",
    "architecture": architecture,
    "runtime_kind": runtime_kind,
    "backends": {
        "bubblewrap": backend(0),
        "proot": backend(4),
    },
}, separators=(",", ":")))
PY
