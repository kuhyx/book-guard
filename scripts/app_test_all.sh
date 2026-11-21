#!/bin/bash
# ============================================================================
# app_test_all.sh -- the whole app suite as slices, one flutter run each.
#
# One `flutter test -j 1` over all ~100 files held a build slot for 62 s
# (2026-11-21, perf.heavybuild). -j 2 does not fit the 2 GiB capped scope
# and a single bundled entry point breaks test isolation (a widget binding
# mocks HTTP for the desktop wrapper tests), so the suite runs as slices of
# at most MAX_FILES files: each slice is its own `flutter test` process and
# holds the slot for about 20 s (30 s under a concurrent build).
#
# Usage: scripts/app_test_all.sh        every slice, one after another
#        scripts/app_test_all.sh K/N    slice K of N only (a call of its own)
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly APP_DIR="${REPO_DIR}/app"
readonly MAX_FILES=20

FLUTTER=(flutter)
command -v fvm >/dev/null && FLUTTER=(fvm flutter)
readonly FLUTTER

die() {
    echo "app_test_all: $*" >&2
    exit 2
}

# Runs slice $1 (1-based) of $2 over the sorted test files in TESTS:
# every file whose index is congruent to $1-1 mod $2.
run_slice() {
    local k="$1" n="$2" i
    local -a slice=()
    for ((i = k - 1; i < ${#TESTS[@]}; i += n)); do
        slice+=("${TESTS[i]}")
    done
    echo "app: slice ${k}/${n} (${#slice[@]} files)"
    "${FLUTTER[@]}" test -j 1 --reporter=compact "${slice[@]}"
}

main() {
    cd "$APP_DIR"
    mapfile -t TESTS < <(find test -name '*_test.dart' | LC_ALL=C sort)
    [[ ${#TESTS[@]} -gt 0 ]] || die "no test files under ${APP_DIR}/test"
    local n=$(((${#TESTS[@]} + MAX_FILES - 1) / MAX_FILES))
    if [[ $# -eq 1 ]]; then
        [[ "$1" =~ ^([0-9]+)/([0-9]+)$ ]] || die "usage: $0 [K/N]"
        local k="${BASH_REMATCH[1]}"
        n="${BASH_REMATCH[2]}"
        ((k >= 1 && k <= n)) || die "slice ${1} is out of range"
        ((${#TESTS[@]} <= n * MAX_FILES)) || die "N=${n} makes slices over ${MAX_FILES} files"
        run_slice "$k" "$n"
        return
    fi
    local k rc=0
    for ((k = 1; k <= n; k++)); do
        run_slice "$k" "$n" || rc=1
    done
    return "$rc"
}

main "$@"
