#!/bin/bash
# ============================================================================
# install_desktop.sh -- the desktop app: Flutter web build + Dart wrapper.
#
# Builds the web app and the wrapper, installs both under
# ~/.local/share/book-guard-desktop/bundle (bin/ + lib/ + web/, the layout the
# wrapper resolves ../web against), and puts `book-guard-desktop` on PATH
# (~/.local/bin, which dmenu's stest cache sees) plus a .desktop entry whose
# StartupWMClass matches the --class the wrapper passes Chrome.
#
# `dart build cli`, not `dart compile exe`: the latter refuses any package
# whose graph has native build hooks (flutter_secure_storage pulls some in).
# Idempotent; heavy steps run under capped.sh.
# ============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly APP_DIR="${REPO_DIR}/app"
readonly DEST="${HOME}/.local/share/book-guard-desktop/bundle"
readonly BIN_LINK="${HOME}/.local/bin/book-guard-desktop"
readonly DESKTOP_FILE="${HOME}/.local/share/applications/book-guard.desktop"
readonly ICON_DIR="${HOME}/.local/share/icons/hicolor/512x512/apps"
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"

log() { printf 'install_desktop: %s\n' "$1" >&2; }
fail() { printf 'install_desktop: FAILED -- %s\n' "$1" >&2; exit 1; }

run_capped() {
    if [[ -x "$CAPPED" ]]; then
        CAP_MEM=4G CAP_CPU_PCT=20 "$CAPPED" "$@"
    else
        "$@"
    fi
}

build() {
    log "building the web app"
    (cd "$APP_DIR" && run_capped flutter build web --release) >/dev/null || fail "flutter build web"
    log "building the wrapper"
    (cd "$APP_DIR" && run_capped dart build cli -t bin/book_guard_desktop.dart -o build/cli) \
        >/dev/null || fail "dart build cli"
}

install_bundle() {
    local bundle="${APP_DIR}/build/cli/bundle"
    [[ -x "${bundle}/bin/book_guard_desktop" ]] || fail "no wrapper binary in ${bundle}/bin"
    log "installing into ${DEST}"
    rm -rf "${DEST}.new"
    mkdir -p "${DEST}.new"
    cp -r "${bundle}/." "${DEST}.new/"
    cp -r "${APP_DIR}/build/web" "${DEST}.new/web"
    rm -rf "$DEST"
    mv "${DEST}.new" "$DEST"
    mkdir -p "$(dirname "$BIN_LINK")"
    ln -sfn "${DEST}/bin/book_guard_desktop" "$BIN_LINK"
}

install_entry() {
    mkdir -p "$ICON_DIR" "$(dirname "$DESKTOP_FILE")"
    install -m 644 "${APP_DIR}/assets/icon/icon.png" "${ICON_DIR}/book-guard.png"
    cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Book Guard
Comment=Reading sessions, this month's book and summaries
Exec=${BIN_LINK}
Icon=book-guard
Terminal=false
Categories=Education;
StartupWMClass=book-guard
EOF
    log "desktop entry at ${DESKTOP_FILE}"
}

main() {
    build
    install_bundle
    install_entry
    log "done -- run: book-guard-desktop"
}

main "$@"
