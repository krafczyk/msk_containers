#!/usr/bin/env bash
# Deterministic selected-root evidence for the parent integration boundary.
#
# This harness validates the finalized child runtime-evidence protocol instead
# of reimplementing its report or cleanup rules. Its fake mode proves only the
# parent admission and dispatch boundary; it cannot support a native claim.
# shellcheck disable=SC2016
set -euo pipefail

readonly schema='container-tools.runtime-evidence/v1'
readonly work_root='/tmp/mkchad-v1/container-tools-selected-root-runtime'
script_dir=$(dirname "$(realpath "$0")")
parent_root=$(realpath "$script_dir/..")
child_root=$(realpath "$parent_root/container_tools")
child_runtime_test="$child_root/tests/container_tools_runtime_test.sh"

usage() {
  printf '%s\n' 'usage: container_tools_selected_root_runtime_test.sh --self-test'
  printf '%s\n' '       container_tools_selected_root_runtime_test.sh --validate-report REPORT --host-release HOST.json --container-release CONTAINER.json --image-digest SHA256 [--probe ABSOLUTE_PATH]'
  printf '%s\n' '       container_tools_selected_root_runtime_test.sh --run-native --backend docker|podman|singularity|apptainer --image CANDIDATE --runtime ABSOLUTE_PATH --host-release HOST.json --container-release CONTAINER.json'
}

unavailable() {
  printf 'selected-root runtime evidence unavailable: %s\n' "$1" >&2
  return 77
}

release_valid() {
  jq -e '
    type == "object" and (keys | sort) == ["digest", "product_major", "source_commit"] and
    (.digest | type == "string" and test("^[0-9a-f]{64}$")) and
    (.product_major | type == "number" and floor == . and . >= 1) and
    (.source_commit | type == "string" and test("^[0-9a-f]{40}$"))
  ' "$1" >/dev/null 2>&1
}

require_same_major() {
  local host_release=$1 container_release=$2
  local host_major container_major

  if ! release_valid "$host_release" || ! release_valid "$container_release"; then
    printf '%s\n' 'selected-root runtime evidence requires closed package release identities' >&2
    return 2
  fi
  host_major=$(jq -r '.product_major' "$host_release")
  container_major=$(jq -r '.product_major' "$container_release")
  if [[ $host_major != "$container_major" ]]; then
    printf 'selected-root runtime evidence refused host major %s with container major %s before runtime probing\n' \
      "$host_major" "$container_major" >&2
    return 1
  fi
}

validate_report() {
  local report=$1 host_release=$2 container_release=$3 image_digest=$4 probe=${5:-}

  require_same_major "$host_release" "$container_release" || return $?
  [[ $image_digest =~ ^[0-9a-f]{64}$ ]] || return 2
  if [[ -n $probe ]]; then
    [[ $probe == /* && -x $probe ]] || return 2
    "$probe"
  fi
  bash "$child_runtime_test" --validate-report "$report" || return $?
  jq -e --slurpfile host "$host_release" --slurpfile container "$container_release" --arg image_digest "$image_digest" '
    .schema == "container-tools.runtime-evidence/v1" and
    .evidence_kind == "fixture" and
    .image == {digest:$image_digest,id:("sha256:" + $image_digest),role:"fixture"} and
    .package.host == $host[0] and .package.container == $container[0] and
    .operations == {outer_launch:1,manifest_publish:1,nested_dispatch:1,payload:1}
  ' "$report" >/dev/null
}

run_native() {
  local backend=$1 image=$2 runtime=$3 host_release=$4 container_release=$5

  require_same_major "$host_release" "$container_release" || return $?
  [[ $runtime == /* && -x $runtime ]] || {
    unavailable 'native runtime executable is missing'
    return $?
  }
  case $backend in
    docker|podman)
      "$runtime" image inspect "$image" >/dev/null 2>&1 || {
        unavailable "native $backend image candidate is missing"
        return $?
      }
      ;;
    singularity|apptainer)
      [[ -f $image ]] || {
        unavailable "native $backend image candidate is missing"
        return $?
      }
      ;;
    *) return 2 ;;
  esac
  unavailable 'the finalized child requires a retained image and release-specific selected-root runner'
  return $?
}

make_fixture_report() {
  local report=$1 host_release=$2 container_release=$3 image_digest=$4
  local source_commit source_manifest

  source_commit=$(git -C "$child_root" rev-parse HEAD)
  source_manifest=$(bash "$child_root/tests/host_projection_runtime_test.sh" --source-manifest)
  jq -n --arg schema "$schema" --arg commit "$source_commit" --arg manifest "$source_manifest" \
    --arg image_digest "$image_digest" --slurpfile host "$host_release" --slurpfile container "$container_release" '
      {schema:$schema,evidence_kind:"fixture",overall:"passed",backend:"docker",architecture:"x86_64",
       source_commit:$commit,source_manifest:$manifest,
       image:{digest:$image_digest,id:("sha256:" + $image_digest),role:"fixture"},
       runtime:{executable_digest:"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",version:"fixture"},
       package:{archive_digest:"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",host:$host[0],container:$container[0]},
       baseline:{status:"not-applicable",report_digest:"unavailable",image_digest:"unavailable"},
       manifest_digest:"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
       operations:{outer_launch:1,manifest_publish:1,nested_dispatch:1,payload:1},
       semantic_outcomes:{outer:"pass",manifest:"pass",nested:"pass",persistent:"pass",selected_root:"pass",status:"pass"},
       selected_root:{default:"pass",alternate:"pass"},signals:{payload_exit:0,signal:"none"},
       cleanup:{status:"exact",owned_residue:0}}
    ' > "$report"
}

self_test() {
  local work="$work_root/self-test"
  local host_release="$work/host.json" container_release="$work/container.json"
  local cross_major_release="$work/cross-major.json" report="$work/report.json" mutated="$work/mutated.json"
  local log="$work/runtime.log" fake_runtime="$work/fake-docker" repair="$work/alternate-root/repair"
  local image_digest='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' status child_commit

  rm -rf -- "$work"
  mkdir -p -- "$work/alternate-root"
  child_commit=$(git -C "$child_root" rev-parse HEAD)
  jq -n --arg commit "$child_commit" '{digest:"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",product_major:1,source_commit:$commit}' > "$host_release"
  jq -n --arg commit "$child_commit" '{digest:"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",product_major:1,source_commit:$commit}' > "$container_release"
  jq -n --arg commit "$child_commit" '{digest:"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",product_major:2,source_commit:$commit}' > "$cross_major_release"
  make_fixture_report "$report" "$host_release" "$container_release" "$image_digest"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$*" >> "$SELECTED_ROOT_RUNTIME_LOG"' \
    'case "${1:-}" in' \
    '  repair) printf repaired > "$SELECTED_ROOT_REPAIR" ;;' \
    '  image) [[ ${2:-} == inspect && ${3:-} == present-image ]] ;;' \
    'esac' > "$fake_runtime"
  chmod +x "$fake_runtime"

  # One default-root outer dispatch, one alternate-root nested dispatch, and
  # one alternate-root repair exercise the parent integration boundary.
  SELECTED_ROOT_RUNTIME_LOG=$log SELECTED_ROOT_REPAIR=$repair "$fake_runtime" outer /host cargo
  SELECTED_ROOT_RUNTIME_LOG=$log SELECTED_ROOT_REPAIR=$repair "$fake_runtime" nested /alternate-root slurm
  SELECTED_ROOT_RUNTIME_LOG=$log SELECTED_ROOT_REPAIR=$repair "$fake_runtime" repair /alternate-root cargo-repair
  [[ $(<"$repair") == repaired ]] || return 1
  [[ $(grep -c '^outer /host cargo$' "$log") == 1 ]] || return 1
  [[ $(grep -c '^nested /alternate-root slurm$' "$log") == 1 ]] || return 1
  [[ $(grep -c '^repair /alternate-root cargo-repair$' "$log") == 1 ]] || return 1

  : > "$log"
  SELECTED_ROOT_RUNTIME_LOG=$log SELECTED_ROOT_REPAIR=$repair \
    validate_report "$report" "$host_release" "$container_release" "$image_digest" "$fake_runtime"
  [[ $(grep -c '^$' "$log") == 1 ]] || return 1

  : > "$log"
  set +e
  SELECTED_ROOT_RUNTIME_LOG=$log SELECTED_ROOT_REPAIR=$repair \
    validate_report "$report" "$host_release" "$cross_major_release" "$image_digest" "$fake_runtime"
  status=$?
  set -e
  [[ $status == 1 && ! -s $log ]] || return 1

  jq '.package.host.digest = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$report" > "$mutated"
  if validate_report "$mutated" "$host_release" "$container_release" "$image_digest"; then return 1; fi
  jq '.image.digest = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" | .image.id = "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"' "$report" > "$mutated"
  if validate_report "$mutated" "$host_release" "$container_release" "$image_digest"; then return 1; fi
  jq '.source_commit = "0000000000000000000000000000000000000000"' "$report" > "$mutated"
  if validate_report "$mutated" "$host_release" "$container_release" "$image_digest"; then return 1; fi
  jq '.cleanup.owned_residue = 1' "$report" > "$mutated"
  if validate_report "$mutated" "$host_release" "$container_release" "$image_digest"; then return 1; fi
  jq '.leak = "/private/selected-root-secret"' "$report" > "$mutated"
  if validate_report "$mutated" "$host_release" "$container_release" "$image_digest"; then return 1; fi
  if grep -Fq '/private/selected-root-secret' "$report"; then return 1; fi

  set +e
  run_native docker missing-image "$fake_runtime" "$host_release" "$container_release"
  status=$?
  set -e
  [[ $status == 77 ]] || return 1
  set +e
  run_native docker fake-image "$work/missing-runtime" "$host_release" "$container_release"
  status=$?
  set -e
  [[ $status == 77 ]] || return 1

  rm -rf -- "$work"
  [[ ! -e $work ]] || return 1
  printf '%s\n' 'container-tools selected-root runtime fixture tests passed'
}

mode=
report=
host_release=
container_release=
image_digest=
probe=
backend=
image=
runtime=
while (($#)); do
  case $1 in
    --self-test|--run-native) [[ -z $mode ]] || { usage >&2; exit 2; }; mode=${1#--}; shift ;;
    --validate-report) [[ -z $mode && $# -ge 2 ]] || { usage >&2; exit 2; }; mode=validate; report=$2; shift 2 ;;
    --host-release|--container-release|--image-digest|--probe|--backend|--image|--runtime)
      (($# >= 2)) || { usage >&2; exit 2; }
      case $1 in
        --host-release) host_release=$2 ;;
        --container-release) container_release=$2 ;;
        --image-digest) image_digest=$2 ;;
        --probe) probe=$2 ;;
        --backend) backend=$2 ;;
        --image) image=$2 ;;
        --runtime) runtime=$2 ;;
      esac
      shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { unavailable 'jq is required for deterministic report validation'; exit $?; }
[[ -f $child_runtime_test ]] || { unavailable 'finalized container-tools runtime validator is missing'; exit $?; }
case $mode in
  self-test) [[ -z $host_release && -z $container_release && -z $image_digest && -z $probe && -z $backend && -z $image && -z $runtime ]] || { usage >&2; exit 2; }; self_test ;;
  validate) [[ -n $report && -n $host_release && -n $container_release && -n $image_digest && -z $backend && -z $image && -z $runtime ]] || { usage >&2; exit 2; }; validate_report "$report" "$host_release" "$container_release" "$image_digest" "$probe" ;;
  run-native) [[ -n $backend && -n $image && -n $runtime && -n $host_release && -n $container_release && -z $report && -z $image_digest && -z $probe ]] || { usage >&2; exit 2; }; run_native "$backend" "$image" "$runtime" "$host_release" "$container_release" ;;
  *) usage >&2; exit 2 ;;
esac
