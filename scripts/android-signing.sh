#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Android signing key, kept in the private signing repository
#
# Without a computer there is nowhere to run `keytool` and nowhere to keep the
# resulting .jks — yet every build must be signed with the *same* key, or a
# tester's phone refuses to install a new build over the previous one. This
# keeps the key in the same private git repository Fastlane Match uses for the
# iOS certificates, encrypted with the same MATCH_PASSWORD, so one secret set
# covers both platforms.
#
#   create   generate a key and commit it, encrypted. Refuses to replace an
#            existing one: once testers (or Google Play) have a build signed
#            with it, a new key breaks every update. Run once, from the
#            signing-setup workflow.
#   fetch    decrypt it for a build. In GitHub Actions it exports
#            ANDROID_KEYSTORE_PATH / _PASSWORD / ANDROID_KEY_ALIAS /
#            ANDROID_KEY_PASSWORD through $GITHUB_ENV (passwords masked),
#            which modules/fastlane/android_build re-signs the APK with.
#
# Environment:
#   SIGNING_REPO         owner/name of the private signing repository
#   SIGNING_REPO_TOKEN   token with Contents read (fetch) or read/write (create)
#   SIGNING_REPO_URL     overrides the https URL built from SIGNING_REPO (tests)
#   SIGNING_BRANCH       default: main (the Match branch)
#   MATCH_PASSWORD       encryption passphrase, shared with Match
#   KEY_ID               which app's key: the path under android/ in the repo
#   KEY_DNAME            certificate subject; default "CN=<KEY_ID>"
#   OUT_DIR              fetch: where to decrypt; default $RUNNER_TEMP or /tmp
#
# Nothing is ever printed that contains key material or a password.
# =============================================================================

usage() { sed -n '3,35p' "$0"; }
log()   { echo "[android-signing] $*"; }
fail()  { echo "[android-signing] ERROR: $*" >&2; exit 1; }

cmd="${1:-}"
case "$cmd" in create|fetch) ;; -h|--help) usage; exit 0 ;; *) usage >&2; exit 2 ;; esac

: "${MATCH_PASSWORD:?MATCH_PASSWORD is required}"
: "${KEY_ID:?KEY_ID is required (e.g. the app identifier)}"
case "$KEY_ID" in *[!A-Za-z0-9._-]*|.*) fail "KEY_ID must be letters, digits, '.', '_' or '-' (got '$KEY_ID')" ;; esac

BRANCH="${SIGNING_BRANCH:-main}"
if [ -n "${SIGNING_REPO_URL:-}" ]; then
  URL="$SIGNING_REPO_URL"
else
  : "${SIGNING_REPO:?SIGNING_REPO (owner/name) is required}"
  URL="https://github.com/${SIGNING_REPO}.git"
fi

REL="android/${KEY_ID}/upload-keystore.tar.enc"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The token goes in an http header, not the URL, so it never lands in
# .git/config or in an error message that echoes the remote.
git_auth=()
if [ -n "${SIGNING_REPO_TOKEN:-}" ]; then
  basic="$(printf 'x-access-token:%s' "$SIGNING_REPO_TOKEN" | base64 | tr -d '\n')"
  [ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$basic"
  git_auth=(-c "http.extraheader=Authorization: Basic $basic")
fi
g() { git "${git_auth[@]}" -C "$WORK/repo" "$@"; }

mkdir -p "$WORK/repo"
git -C "$WORK/repo" init -q
git -C "$WORK/repo" remote add origin "$URL"
if g fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then
  g checkout -q -B "$BRANCH" FETCH_HEAD
  has_branch=1
else
  has_branch=0
  # Empty repository, or the branch does not exist yet. Tell the two apart from
  # "cannot reach it at all", which must not be mistaken for "no key yet".
  g ls-remote origin >/dev/null 2>&1 || fail "cannot read $URL — check SIGNING_REPO and that SIGNING_REPO_TOKEN has access to it"
  g checkout -q -b "$BRANCH"
fi

enc() { openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass env:MATCH_PASSWORD "$@"; }

if [ "$cmd" = "fetch" ]; then
  [ "$has_branch" = 1 ] && [ -f "$WORK/repo/$REL" ] \
    || fail "no Android key at $REL on '$BRANCH' — run the 'Signing setup' workflow once with android enabled"
  out="${OUT_DIR:-${RUNNER_TEMP:-/tmp}}/android-signing"
  rm -rf "$out"; mkdir -p "$out"; chmod 700 "$out"
  enc -d -in "$WORK/repo/$REL" | tar -x -C "$out" \
    || fail "could not decrypt $REL — is MATCH_PASSWORD the one used to create it?"
  # shellcheck disable=SC1091
  . "$out/keystore.properties"
  [ -f "$out/upload-keystore.jks" ] && [ -n "${storePassword:-}" ] && [ -n "${keyAlias:-}" ] \
    || fail "$REL decrypted but is incomplete"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "::add-mask::$storePassword"
    {
      echo "ANDROID_KEYSTORE_PATH=$out/upload-keystore.jks"
      echo "ANDROID_KEYSTORE_PASSWORD=$storePassword"
      echo "ANDROID_KEY_ALIAS=$keyAlias"
      echo "ANDROID_KEY_PASSWORD=$storePassword"
    } >> "$GITHUB_ENV"
  fi
  log "key for $KEY_ID ready at $out/upload-keystore.jks"
  exit 0
fi

# create
if [ -f "$WORK/repo/$REL" ]; then
  log "a key for $KEY_ID already exists at $REL — leaving it alone (replacing it would break updates for every tester)"
  exit 0
fi
command -v keytool >/dev/null || fail "keytool not found (install a JDK)"

stage="$WORK/stage"; mkdir -p "$stage"; chmod 700 "$stage"
pass="$(openssl rand -hex 24)"
[ -n "${GITHUB_ACTIONS:-}" ] && echo "::add-mask::$pass"
alias_name="upload"
# PKCS12 (keytool's default) uses one password for the store and the key.
# The password reaches keytool through the environment, not argv.
KS_PASS="$pass" keytool -genkeypair -keystore "$stage/upload-keystore.jks" -storetype PKCS12 \
  -alias "$alias_name" -keyalg RSA -keysize 4096 -validity 10000 \
  -storepass:env KS_PASS -dname "${KEY_DNAME:-CN=$KEY_ID}" >/dev/null 2>&1 \
  || fail "keytool failed"
printf 'storePassword=%s\nkeyAlias=%s\n' "$pass" "$alias_name" > "$stage/keystore.properties"

mkdir -p "$(dirname "$WORK/repo/$REL")"
tar -c -C "$stage" upload-keystore.jks keystore.properties | enc -out "$WORK/repo/$REL"
rm -rf "$stage"

g add "$REL"
g -c user.name="mobile-idp" -c user.email="mobile-idp@users.noreply.github.com" \
  commit -q -m "Android upload key for $KEY_ID"
g push -q origin "HEAD:$BRANCH" || fail "push to $URL failed — SIGNING_REPO_TOKEN needs Contents: read and write"
log "created and committed $REL (encrypted with MATCH_PASSWORD)"
