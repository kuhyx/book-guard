#!/bin/bash
# ============================================================================
# deploy.sh -- put main everywhere book-guard runs, then check it took.
#
#   1. The gate daemon runs from ~/src/book-guard: fast-forward it (fails on
#      a dirty tree, never stashes kuhy's work).
#   1b. Reinstall it into the system python the units run (pinned
#      dependencies such as gatelock move with pyproject), then import the
#      CLI with that interpreter.
#   2. The desktop app: scripts/install_desktop.sh (web build + wrapper).
#   3. The phone: a release APK through phone_deploy.sh's stages (prep,
#      dart, kotlin, assemble, install; each well under 60 s -- one
#      `flutter build apk` held a build slot 57-64 s), then adb install -r,
#      never an uninstall: app data survives. A phone out of reach (exit 30)
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
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"
readonly APK="${HOME}/src/book-guard/app/build/app/outputs/flutter-apk/app-release.apk"

die() {
  echo "deploy: $*" >&2
  exit 1
}

git -C "${LIVE}" fetch --quiet origin
git -C "${LIVE}" pull --ff-only --quiet origin main
[[ "$(git -C "${LIVE}" rev-parse HEAD)" == "$(git -C "${LIVE}" rev-parse origin/main)" ]] ||
  die "${LIVE} is not at origin/main"

/usr/bin/python3 -m pip install --user --break-system-packages -q -e "${LIVE}" ||
  die "pip install into the system python failed"
/usr/bin/python3 -c 'import book_guard._cli' ||
  die "the units' python cannot import book_guard"
# The unit files ship with the code (a new one, like book-guard-grade, must
# exist before a pass starts it); enabling stays install.sh's job.
install -m 644 -t "${HOME}/.config/systemd/user" "${LIVE}"/book-guard*.service \
  "${LIVE}"/book-guard*.path "${LIVE}"/book-guard*.timer ||
  die "could not install the unit files"
systemctl --user daemon-reload || die "systemctl --user daemon-reload failed"

"${LIVE}/scripts/install_desktop.sh"
[[ -s "${BUNDLE}" ]] || die "desktop bundle missing: ${BUNDLE}"

# Every stage is its own phone_deploy process. Outside a claude session the
# phone lease would name each one pid:N, so install would wait on prep's own
# lease (exit 40): one owner for the whole run.
claim_lease_owner() {
  [[ -n "${PHONE_LEASE_OWNER:-}" ]] && return 0
  local owner
  owner="$(PYTHONPATH="${HOME}/src/testsAndMisc" python3 -m python_pkg.phone_lease whoami)"
  [[ "${owner}" == pid:* ]] && owner="book-guard-deploy:$$"
  export PHONE_LEASE_OWNER="${owner}"
}

# The staged build: gradle's up-to-date outputs carry each stage to the next.
# A rerun after a failed install reuses the build number, so gradle would
# leave the old APK and phone_deploy reads that as a killed build (exit 34):
# drop the build artifacts (gitignored) first.
phone_build_and_install() {
  local stage
  claim_lease_owner
  rm -f "${APK}" "${LIVE}/app/build/app/outputs/apk/release/app-release.apk"
  "${PHONE_DEPLOY}" "${LIVE}/app" --release --stage prep || return
  for stage in dart kotlin assemble; do
    CAP_MEM=4G "${CAPPED}" "${PHONE_DEPLOY}" "${LIVE}/app" --stage "${stage}" || return
  done
  "${PHONE_DEPLOY}" "${LIVE}/app" --stage install
}

status=0
phone_build_and_install || status=$?
case "${status}" in
  0) echo "deploy: phone updated" ;;
  30 | 40) echo "deploy: phone out of reach or leased (${status}), APK not installed" ;;
  *) die "phone_deploy failed (${status})" ;;
esac
[[ "${status}" -ne 0 || -s "${APK}" ]] ||
  die "no release APK at ${APK}"
echo "deploy: ok at $(git -C "${LIVE}" rev-parse --short HEAD)"
