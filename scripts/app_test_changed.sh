#!/bin/bash
# ============================================================================
# app_test_changed.sh -- the commit gate's Flutter tests, under a minute.
#
# The whole pre-commit run must end under 60 s and holds one build slot; each
# flutter run warms the VM in ~1.3 s per file (CI app.yml runs everything),
# so at most GATE_MAX test files are ever started by this hook regardless of
# what the commit touches.
#
# Selection order: every changed test file first, then importer-selected tests
# (lib importers up to 4 levels deep), deduped keeping first occurrence. A
# pubspec, analysis_options, bin/, or an unreachable lib triggers an even
# spread of GATE_MAX over the full suite instead of `full`. CI (.github/workflows/app.yml)
# always runs the whole suite.
#
# Usage: scripts/app_test_changed.sh FILE... (paths from the repo root, as
# pre-commit passes them).
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly APP_DIR="${REPO_DIR}/app"

FLUTTER=(flutter)
command -v fvm >/dev/null && FLUTTER=(fvm flutter)
readonly FLUTTER

# At most this many test files in a single run: the whole pre-commit run takes
# ~45 s without app-test, so 12-13 s remain; ~1.3 s per file warm keeps us under.
# CI (.github/workflows/app.yml) runs every file regardless.
GATE_MAX=6
readonly GATE_MAX

# Test files (relative to app/) that import package:book_guard_app/<lib path>.
importers() {
    local lib_path="$1"
    grep -rlF --include='*_test.dart' "package:book_guard_app/${lib_path}'" \
        "${APP_DIR}/test" | sed "s|^${APP_DIR}/||" || true
}

# Lib files (relative to lib/) that import package:book_guard_app/<lib path>.
lib_importers() {
    local lib_path="$1"
    grep -rlF --include='*.dart' "package:book_guard_app/${lib_path}'" \
        "${APP_DIR}/lib" | sed "s|^${APP_DIR}/lib/||" || true
}

# Tests for a lib file: its direct importers, else (a widget no test pumps
# alone) the tests of the lib files that import it, up to 4 levels. Empty
# when none is found: the caller then runs the full suite.
tests_for() {
    local -a level=("$1") next=()
    local -A seen=(["$1"]=1)
    local depth p found up
    for depth in 1 2 3 4; do
        found=""
        for p in "${level[@]}"; do
            found+="$(importers "$p")"$'\n'
        done
        if [[ -n "${found//[[:space:]]/}" ]]; then
            printf '%s' "$found" | sed '/^$/d'
            return 0
        fi
        next=()
        for p in "${level[@]}"; do
            while IFS= read -r up; do
                [[ -z "$up" || -n "${seen[$up]:-}" ]] && continue
                seen["$up"]=1
                next+=("$up")
            done < <(lib_importers "$p")
        done
        [[ ${#next[@]} -eq 0 ]] && return 0
        level=("${next[@]}")
        : "$depth"
    done
}

main() {
    local full=0 f rel found i idx total=0
    local -a changed=() mapped=()
    for f in "$@"; do
        rel="${f#app/}"
        case "$f" in
            app/pubspec.* | app/analysis_options.yaml) full=1 ;;
            app/test/*_test.dart) [[ -e "$f" ]] && changed+=("$rel") ;;
            app/lib/*.dart)
                found="$(tests_for "${rel#lib/}")"
                if [[ -z "$found" ]]; then full=1; else mapfile -t -O "${#mapped[@]}" mapped <<<"$found"; fi
                ;;
            app/bin/*.dart) full=1 ;;
        esac
    done

    cd "$APP_DIR"
    local -a tests=()
    # Changed test files first (deduped, keep first occurrence)
    local -A seen=()
    for rel in "${changed[@]}"; do
        [[ -n "${seen[$rel]:-}" ]] && continue
        seen[$rel]=1
        tests+=("$rel")
    done
    for rel in "${mapped[@]}"; do
        [[ -n "${seen[$rel]:-}" ]] && continue
        seen[$rel]=1
        tests+=("$rel")
    done

    if [[ $full -eq 1 ]]; then
        # Even spread over all test files
        local -a all=()
        mapfile -t all < <(find test -name '*_test.dart' | LC_ALL=C sort)
        local total=${#all[@]}
        for ((i = 0; i < GATE_MAX && i < total; i++)); do
            idx=$((i * total / GATE_MAX))
            rel="${all[idx]}"
            [[ -n "${seen[$rel]:-}" ]] && continue
            seen[$rel]=1
            tests+=("$rel")
        done
    fi

    if [[ ${#tests[@]} -eq 0 ]]; then
        echo "app: no tests touched"
        exit 0
    fi

    if [[ ${#tests[@]} -gt GATE_MAX ]]; then
        echo "app: ${GATE_MAX} of ${#tests[@]} test file(s); CI (app.yml) runs the whole suite"
        tests=("${tests[@]:0:GATE_MAX}")
    else
        echo "app: ${#tests[@]} test file(s)"
    fi
    exec "${FLUTTER[@]}" test -j 1 --reporter=compact "${tests[@]}"
}

main "$@"
