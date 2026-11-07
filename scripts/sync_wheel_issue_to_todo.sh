#!/bin/bash
# ============================================================================
# sync_wheel_issue_to_todo.sh -- the open onnxruntime-wheel issue -> one task.
#
# The weekly onnxruntime-wheel workflow opens a GitHub issue when onnxruntime
# ships a cp315 wheel. This (book-guard-wheel-todo.timer) adds a todo-app task
# for it, deduped by title, and adds nothing while unpin task 0ea3306e is
# still open. Needs gh (logged in) and the todo app checkout (dart).
# ============================================================================

set -euo pipefail

readonly REPO="kuhyx/book-guard"
readonly TITLE="onnxruntime ships a cp315 wheel: unpin fastembed on 3.15"
readonly UNPIN_TASK="0ea3306e"
readonly TODO_DIR="${TODO_DIR:-${HOME}/src/todo}"

log() { printf 'wheel-todo: %s\n' "$1" >&2; }

# The todo CLI; BOOK_GUARD_TODO_CLI swaps in a stub for the sandbox test.
todo() {
    if [[ -n "${BOOK_GUARD_TODO_CLI:-}" ]]; then
        "$BOOK_GUARD_TODO_CLI" "$@"
    else
        (cd "$TODO_DIR" && dart run bin/todo_note.dart "$@")
    fi
}

issue_open() {
    gh issue list -R "$REPO" --state open --search "in:title \"${TITLE}\"" \
        --json title --jq '.[].title' | grep -qxF -- "$TITLE"
}

# True while the unpin task is todo/in_progress: `todo --get` also finds a
# done or abandoned note, which must not block the new task.
unpin_task_open() {
    local detail
    detail="$(todo --get "$UNPIN_TASK" 2>/dev/null)" || return 1
    grep -qxE 'status: (todo|in_progress)' <<<"$detail"
}

main() {
    if ! issue_open; then
        log "no open issue"
        return 0
    fi
    if unpin_task_open; then
        log "task ${UNPIN_TASK} is open: reusing it"
        return 0
    fi
    if todo --search "$TITLE" | grep -qF -- "$TITLE"; then
        log "a task with this title exists"
        return 0
    fi
    todo --text "${TITLE}
drop the marker in \`pyproject.toml\` and the guard in \`_embed.py\`" \
        --repo "$REPO" --by claude >/dev/null
    log "added the todo task"
}

main "$@"
