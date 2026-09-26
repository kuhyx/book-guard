#!/bin/bash
# ============================================================================
# setup_mcp.sh -- the dedicated venv Claude Code spawns book-guard's MCP from,
# and its user-scope registration (so /book-check works from any directory).
#
# The mcp SDK is an optional extra, kept out of the system-python path the
# systemd units run. Idempotent.
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly VENV_DIR="${HOME}/.venvs/book-guard-mcp"
readonly CLAUDE_BIN="${HOME}/.local/bin/claude"

log() { printf 'setup_mcp: %s\n' "$1" >&2; }

main() {
    if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
        log "creating ${VENV_DIR}"
        python3 -m venv "${VENV_DIR}"
    fi
    log "installing book-guard[mcp] into the venv"
    "${VENV_DIR}/bin/python" -m pip install --quiet --upgrade pip
    "${VENV_DIR}/bin/python" -m pip install --quiet -e "${REPO_DIR}[mcp]"
    # The server module itself, not the package root -- a missing transitive
    # import only ever shows up in the client as "Connection closed".
    "${VENV_DIR}/bin/python" -c "import mcp, book_guard._mcp; print('book_guard._mcp imports OK')"
    if ! "$CLAUDE_BIN" mcp get book-guard >/dev/null 2>&1; then
        log "registering the book-guard MCP server at user scope"
        "$CLAUDE_BIN" mcp add --scope user book-guard -- \
            "${VENV_DIR}/bin/python" -m book_guard._mcp
    fi
    log "done"
}

main "$@"
