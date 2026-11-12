#!/bin/bash
# ============================================================================
# deploy.sh -- put main everywhere book-guard runs, then check it took.
#
#   1. The gate daemon runs from ~/src/book-guard: fast-forward it (fails on
#      a dirty tree, never stashes kuhy's work).
#   2. The desktop app: scripts/install_desktop.sh (web build + wrapper).
#   3. The phone: a release APK through phone_deploy.sh (adb install -r,
#      never an uninstall: app data survives). A phone out of reach (exit 30)
#      or held by another session (exit 40) is reported and skipped; the
#      next deploy installs it.
#
# Idempotent. Exits non-zero unless the checkout matches origin/main and the
# desktop bundle and APK it built exist.
# ============================================================================

set -euo pipefail

readonly LIVE="${HOME}/src/book-guard"
readonly BUNDLE="${HOME}/.local/share/book-guard-desktop/bundle/web/index.html"
readonly PHONE_DEPLOY="${HOME}/.claude/scripts/phone_deploy.sh"
readonly APK="${HOME}/src/book-guard/app/build/app/outputs/flutter-apk/app-release.apk"

die() {
  echo "deploy: $*" >&2
  exit 1
}

git -C "${LIVE}" fetch --quiet origin
git -C "${LIVE}" pull --ff-only --quiet origin main
[[ "$(git -C "${LIVE}" rev-parse HEAD)" == "$(git -C "${LIVE}" rev-parse origin/main)" ]] ||
  die "${LIVE} is not at origin/main"

"${LIVE}/scripts/install_desktop.sh"
[[ -s "${BUNDLE}" ]] || die "desktop bundle missing: ${BUNDLE}"

status=0
"${PHONE_DEPLOY}" "${LIVE}/app" --release || status=$?
case "${status}" in
  0) echo "deploy: phone updated" ;;
  30 | 40) echo "deploy: phone out of reach or leased (${status}), APK not installed" ;;
  *) die "phone_deploy failed (${status})" ;;
esac
[[ "${status}" -ne 0 || -s "${APK}" ]] ||
  die "no release APK at ${APK}"
echo "deploy: ok at $(git -C "${LIVE}" rev-parse --short HEAD)"
