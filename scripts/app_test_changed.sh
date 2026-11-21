#!/bin/bash
# ============================================================================
# app_test_changed.sh -- the commit gate's Flutter tests, under a minute.
#
# The full app suite runs past the 60 s action cap, so the
# pre-commit hook runs only what the commit touches: every changed test
# file, plus every test that imports a changed lib/ or bin/ file directly
# (or, for a lib file no test imports, the tests of the lib files that
# import it, up to 4 levels). A pubspec or analysis_options change, a bin/
# change, or a lib file no test reaches, runs the full suite. CI (.github/workflows/app.yml) always runs it all.
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
    local full=0 f rel found
    local -a tests=()
    for f in "$@"; do
        rel="${f#app/}"
        case "$f" in
            app/pubspec.* | app/analysis_options.yaml) full=1 ;;
            app/test/*_test.dart) [[ -e "$f" ]] && tests+=("$rel") ;;
            app/lib/*.dart)
                found="$(tests_for "${rel#lib/}")"
                if [[ -z "$found" ]]; then full=1; else mapfile -t -O "${#tests[@]}" tests <<<"$found"; fi
                ;;
            app/bin/*.dart) full=1 ;;
        esac
    done

    cd "$APP_DIR"
    if [[ $full -eq 1 ]]; then
        echo "app: full suite"
        exec "${REPO_DIR}/scripts/app_test_all.sh"
    fi
    if [[ ${#tests[@]} -eq 0 ]]; then
        echo "app: no tests touched"
        exit 0
    fi
    mapfile -t tests < <(printf '%s\n' "${tests[@]}" | sort -u)
    echo "app: ${#tests[@]} test file(s)"
    exec "${FLUTTER[@]}" test -j 1 --reporter=compact "${tests[@]}"
}

main "$@"
