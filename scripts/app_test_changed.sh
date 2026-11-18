#!/bin/bash
# ============================================================================
# app_test_changed.sh -- the commit gate's Flutter tests, under a minute.
#
# The full app suite runs past the 60 s action cap, so the
# pre-commit hook runs only what the commit touches: every changed test
# file, plus every test that imports a changed lib/ or bin/ file directly.
# A pubspec or analysis_options change, or a changed file no test imports,
# runs the full suite. CI (.github/workflows/app.yml) always runs it all.
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

main() {
    local full=0 f rel found
    local -a tests=()
    for f in "$@"; do
        rel="${f#app/}"
        case "$f" in
            app/pubspec.* | app/analysis_options.yaml) full=1 ;;
            app/test/*_test.dart) [[ -e "$f" ]] && tests+=("$rel") ;;
            app/lib/*.dart)
                found="$(importers "${rel#lib/}")"
                if [[ -z "$found" ]]; then full=1; else mapfile -t -O "${#tests[@]}" tests <<<"$found"; fi
                ;;
            app/bin/*.dart) full=1 ;;
        esac
    done

    cd "$APP_DIR"
    if [[ $full -eq 1 ]]; then
        echo "app: full suite"
        exec "${FLUTTER[@]}" test -j 1 --reporter=compact
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
