#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Install the app's fastlane gems on a GitHub-hosted runner.
#
# A Gemfile.lock written on a Mac often lists only darwin platforms, and
# `bundle install` then refuses to run on the Linux runner ("Your bundle only
# supports platforms ..."). Adding the runner's platform to the lock *in CI
# only* (nothing is committed) makes the same lock work on both. Gems go
# outside the repo so they are never picked up by a later `git add -A`.
# =============================================================================

[ -f Gemfile ] || { echo "::error::No Gemfile in $(pwd). Bootstrap the app with mobile-idp first (scripts/bootstrap-flutter-github.sh or scripts/bootstrap-ios-native.sh)."; exit 1; }

bundle config set --local path "${RUNNER_TEMP:-$HOME}/idp-bundle"
if [ -f Gemfile.lock ]; then
  platform="$(ruby -e 'print Gem::Platform.local.to_s')"
  bundle lock --add-platform "$platform" >/dev/null 2>&1 || true
fi
bundle install --jobs 4 --retry 3
