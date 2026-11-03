#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# A temporary, unlocked keychain for match on a GitHub-hosted macOS runner.
#
# Fastfiles generated for native iOS call `setup_ci`, which does the same; a
# Flutter project bootstrapped for CodeBuild does not, and match would then
# import into the login keychain and hang on a UI prompt for its password.
# Exporting MATCH_KEYCHAIN_NAME / _PASSWORD makes every Fastfile work.
# =============================================================================

[ "$(uname)" = Darwin ] || { echo "ci-keychain.sh: macOS only" >&2; exit 1; }

kc="${RUNNER_TEMP:-/tmp}/idp-signing.keychain-db"
pw="$(openssl rand -hex 16)"
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$pw"

security delete-keychain "$kc" >/dev/null 2>&1 || true
security create-keychain -p "$pw" "$kc"
security set-keychain-settings -lut 21600 "$kc"
security unlock-keychain -p "$pw" "$kc"
# Search list = this keychain first, then whatever was there.
# shellcheck disable=SC2046
security list-keychains -d user -s "$kc" $(security list-keychains -d user | tr -d '"')
security default-keychain -s "$kc"

if [ -n "${GITHUB_ENV:-}" ]; then
  { echo "MATCH_KEYCHAIN_NAME=$kc"; echo "MATCH_KEYCHAIN_PASSWORD=$pw"; } >> "$GITHUB_ENV"
fi
echo "[ci-keychain] $kc ready"
