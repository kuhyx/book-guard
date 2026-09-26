#!/bin/bash
# ============================================================================
# install.sh -- install book-guard for real use.
#
# Installs into the SYSTEM python's user site-packages, not a venv, because
# that is what the systemd units run; then verifies the imports with that
# exact interpreter. Idempotent. Safe to re-run after any change.
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR
readonly SYSTEM_PYTHON="/usr/bin/python3"
readonly UNIT_DIR="${HOME}/.config/systemd/user"
readonly HMAC_KEY="/etc/workout-locker/hmac.key"
readonly READING="${HOME}/data/cloud/Reading"
readonly CLAUDE_BIN="${HOME}/.local/bin/claude"
readonly UNITS=(
    book-guard.service
    book-guard.timer
    book-guard-inbox.service
    book-guard-inbox.path
    book-guard-inbox.timer
)

log() { printf 'install: %s\n' "$1" >&2; }
fail() { printf 'install: FAILED -- %s\n' "$1" >&2; exit 1; }

install_package() {
    log "installing into the system python's user site-packages"
    "$SYSTEM_PYTHON" -m pip install --user --break-system-packages -q -e "$REPO_DIR" \
        || fail "pip install"
}

install_converters() {
    # Book-file text extraction: calibre (ebook-convert: epub, mobi, azw3,
    # fb2, docx, ...), poppler (pdftotext) and djvulibre (djvutxt).
    local missing=()
    command -v ebook-convert >/dev/null || missing+=(calibre)
    command -v pdftotext >/dev/null || missing+=(poppler)
    command -v djvutxt >/dev/null || missing+=(djvulibre)
    if (( ${#missing[@]} )); then
        log "installing ${missing[*]}"
        sudo pacman -S --needed --noconfirm "${missing[@]}" || fail "pacman ${missing[*]}"
    fi
}

verify_runtime() {
    log "verifying imports with $SYSTEM_PYTHON"
    "$SYSTEM_PYTHON" -c "import book_guard, gatelock, freedays, PIL, fastembed; print('imports OK')" \
        || fail "a runtime dependency is missing from the system python"
    [[ -x "$CLAUDE_BIN" ]] || fail "no claude CLI at $CLAUDE_BIN (vision + grading need it)"
    [[ -r "$HMAC_KEY" ]] || fail "$HMAC_KEY unreadable -- the ledger cannot be signed"
}

install_units() {
    log "installing systemd user units into $UNIT_DIR"
    mkdir -p "$UNIT_DIR" "$READING"/{inbox,requests,responses,books}
    local unit
    for unit in "${UNITS[@]}"; do
        install -m 644 "$REPO_DIR/$unit" "$UNIT_DIR/"
    done
    systemctl --user daemon-reload
    systemctl --user enable --now book-guard-inbox.path book-guard-inbox.timer book-guard.timer
    # Enabled for login arming, not started: starting it now would run the
    # gate immediately, which is the timer's and the next login's job.
    systemctl --user enable book-guard.service
}

main() {
    install_converters
    install_package
    verify_runtime
    install_units
    log "done -- uploads: $READING ; status: python3 -m book_guard status"
}

main "$@"
