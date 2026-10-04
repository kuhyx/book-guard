#!/bin/bash

# ============================================================================
# Run only the tests related to files changed vs HEAD (staged, unstaged and
# untracked). Quiet: failures plus a one-line summary. Python (book_guard/,
# pytest from .venv, coverage gate off for the subset) and Flutter (app/).
# Each side falls back to its full suite when a change cannot be mapped.
# ============================================================================

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
CHANGED=()
while IFS= read -r f; do
    [[ -n "$f" && -e "$f" ]] && CHANGED+=("$f")
done < <({ git diff --name-only HEAD 2>/dev/null || true; git ls-files --others --exclude-standard; } | sort -u)

readonly PY=".venv/bin/python"
py_full=0 py_touched=0 app_full=0 app_touched=0
py_tests=() app_tests=()

# book_guard/_quiz.py -> book_guard/tests/test_core_quiz.py (or test_/test_flow_).
map_py() {
    local base="$1" cand t
    base="${base#_}"
    MAPPED=()
    for cand in "test_core_${base}.py" "test_${base}.py" "test_flow_${base}.py"; do
        t="book_guard/tests/$cand"
        [[ -f "$t" ]] && MAPPED+=("$t")
    done
}

for f in "${CHANGED[@]}"; do
    case "$f" in
        pyproject.toml | */conftest.py) py_full=1; py_touched=1 ;;
        book_guard/tests/test_*.py) py_touched=1; py_tests+=("$f") ;;
        book_guard/tests/*.py) py_full=1; py_touched=1 ;;
        book_guard/*.py)
            py_touched=1
            map_py "$(basename "$f" .py)"
            if [[ ${#MAPPED[@]} -gt 0 ]]; then py_tests+=("${MAPPED[@]}"); else py_full=1; fi
            ;;
        app/pubspec.* | app/analysis_options.yaml) app_full=1; app_touched=1 ;;
        app/test/*_test.dart) app_touched=1; app_tests+=("${f#app/}") ;;
        app/lib/*.dart | app/bin/*.dart) app_touched=1; app_full=1 ;;
    esac
done

if [[ $py_touched -eq 0 && $app_touched -eq 0 ]]; then
    echo "no python/app changes vs HEAD: nothing to test"; exit 0
fi

rc=0
if [[ $py_touched -eq 1 ]]; then
    if [[ $py_full -eq 1 ]]; then
        echo "python: running full suite"
        "$PY" -m pytest -q --tb=short || rc=1
    else
        mapfile -t uniq_py < <(printf '%s\n' "${py_tests[@]}" | sort -u)
        echo "python: ${#uniq_py[@]} test file(s)"
        "$PY" -m pytest -q --tb=short --no-cov "${uniq_py[@]}" || rc=1
    fi
fi
if [[ $app_touched -eq 1 ]]; then
    if [[ $app_full -eq 1 || ${#app_tests[@]} -eq 0 ]]; then
        echo "app: running full suite"
        (cd app && flutter test -j 1 --reporter=compact) || rc=1
    else
        mapfile -t uniq_app < <(printf '%s\n' "${app_tests[@]}" | sort -u)
        echo "app: ${#uniq_app[@]} test file(s)"
        (cd app && flutter test -j 1 --reporter=compact "${uniq_app[@]}") || rc=1
    fi
fi
[[ $rc -eq 0 ]] && echo "test-changed: pass" || echo "test-changed: FAIL"
exit $rc
