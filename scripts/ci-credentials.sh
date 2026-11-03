#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Resolve CI credentials for the GitHub Actions distribution workflows
#
# Two sources, chosen per run:
#
#   aws     The job assumed the IDP's OIDC role and read
#           <env>/fastlane/credentials into IDPCREDS_* variables (the repo has
#           an AWS_ROLE_ARN variable). Same secret CodeBuild uses.
#   github  Everything else: GitHub *environment* secrets, which the workflow
#           passes in as GH_* variables. Needs no AWS account and no computer
#           — every value can be pasted in from a phone.
#
# Writes the canonical names fastlane reads to $GITHUB_ENV (multi-line safe),
# masks them, and fails listing every missing secret by *name* at once, so a
# first run tells the user exactly what to add. Never prints a value.
#
# Usage: ci-credentials.sh NEED[,NEED...]
#   ios        App Store Connect API key + match (password, signing repo)
#   firebase   Firebase service account (or CLI token)
#   signing    signing repo + MATCH_PASSWORD only (Android key fetch/create)
#
# Inputs (environment):
#   GH_MATCH_PASSWORD, GH_SIGNING_REPO_TOKEN, GH_SIGNING_REPO (variable),
#   GH_ASC_KEY_ID, GH_ASC_ISSUER_ID, GH_ASC_KEY, GH_FIREBASE_SERVICE_ACCOUNT,
#   GH_FIREBASE_CLI_TOKEN, and IDPCREDS_* from aws-secretsmanager-get-secrets.
# =============================================================================

needs="${1:?usage: ci-credentials.sh ios,firebase,signing}"
out="${GITHUB_ENV:-/dev/stdout}"
tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
missing=()

has() { case ",$needs," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# Multi-line safe GITHUB_ENV write: NAME<<DELIM ... DELIM.
emit() {
  local name="$1" value="$2" delim
  [ -n "$value" ] || return 0
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # Mask each line: GitHub masks per line, so a PEM key or JSON blob
    # would otherwise leak its inner lines if anything printed it.
    while IFS= read -r line; do
      [ ${#line} -ge 4 ] && echo "::add-mask::$line"
    done <<< "$value"
  fi
  delim="EOF_$(openssl rand -hex 8)"
  printf '%s<<%s\n%s\n%s\n' "$name" "$delim" "$value" "$delim" >> "$out"
}

if [ -n "${IDPCREDS_MATCH_PASSWORD:-}" ]; then
  mode=aws
else
  mode=github
fi
echo "[ci-credentials] source: $mode (needs: $needs)"

# pick <NAME> <aws value> <github value> <github secret name>
# Not via $(...): a subshell would lose the missing+= below.
pick() {
  if [ "$mode" = aws ]; then emit "$1" "$2"; else
    [ -n "$3" ] || missing+=("$4")
    emit "$1" "$3"
  fi
}

if has ios || has signing; then
  pick MATCH_PASSWORD "${IDPCREDS_MATCH_PASSWORD:-}" "${GH_MATCH_PASSWORD:-}" "secret MATCH_PASSWORD"
fi

if has ios; then
  pick APP_STORE_CONNECT_API_KEY_KEY_ID    "${IDPCREDS_APP_STORE_CONNECT_KEY_ID:-}"      "${GH_ASC_KEY_ID:-}"    "secret APP_STORE_CONNECT_API_KEY_ID"
  pick APP_STORE_CONNECT_API_KEY_ISSUER_ID "${IDPCREDS_APP_STORE_CONNECT_ISSUER_ID:-}"  "${GH_ASC_ISSUER_ID:-}" "secret APP_STORE_CONNECT_ISSUER_ID"
  pick APP_STORE_CONNECT_API_KEY_KEY       "${IDPCREDS_APP_STORE_CONNECT_KEY_CONTENT:-}" "${GH_ASC_KEY:-}"       "secret APP_STORE_CONNECT_API_KEY"
  if [ "$mode" = aws ]; then
    # Match storage comes from fastlane/env.<env>; pass the git credential
    # through when the stack uses git storage.
    emit MATCH_GIT_BASIC_AUTHORIZATION "${IDPCREDS_MATCH_GIT_BASIC_AUTHORIZATION:-}"
    emit MATCH_GIT_PRIVATE_KEY "${IDPCREDS_MATCH_GIT_PRIVATE_KEY:-}"
  fi
fi

if [ "$mode" = github ] && { has ios || has signing; }; then
  repo="${GH_SIGNING_REPO:-}"
  [ -n "$repo" ] || missing+=("variable SIGNING_REPO (owner/name of the private signing repository)")
  [ -n "${GH_SIGNING_REPO_TOKEN:-}" ] || missing+=("secret SIGNING_REPO_TOKEN")
  if [ -n "$repo" ]; then
    case "$repo" in */*) ;; *) missing+=("variable SIGNING_REPO must be owner/name (got '$repo')") ;; esac
    # IDP_* so fastlane/env.<env> cannot override them (see modules/fastlane/match).
    emit IDP_MATCH_STORAGE_MODE git
    emit IDP_MATCH_GIT_URL "https://github.com/${repo}.git"
    emit SIGNING_REPO "$repo"
  fi
  if [ -n "${GH_SIGNING_REPO_TOKEN:-}" ]; then
    emit SIGNING_REPO_TOKEN "$GH_SIGNING_REPO_TOKEN"
    emit MATCH_GIT_BASIC_AUTHORIZATION "$(printf 'x-access-token:%s' "$GH_SIGNING_REPO_TOKEN" | base64 | tr -d '\n')"
  fi
fi

if has firebase; then
  sa="${GH_FIREBASE_SERVICE_ACCOUNT:-}"
  token="${IDPCREDS_FIREBASE_CLI_TOKEN:-${GH_FIREBASE_CLI_TOKEN:-}}"
  if [ -n "$sa" ]; then
    file="$tmp/firebase-service-account.json"
    ( umask 077; printf '%s' "$sa" > "$file" )
    ruby -rjson -e 'j = JSON.parse(File.read(ARGV[0])); abort unless j["type"] == "service_account"' "$file" 2>/dev/null \
      || missing+=("secret FIREBASE_SERVICE_ACCOUNT must be the service account's JSON key file contents")
    emit FIREBASE_SERVICE_CREDENTIALS_FILE "$file"
  elif [ -n "$token" ]; then
    emit FIREBASE_CLI_TOKEN "$token"
  else
    missing+=("secret FIREBASE_SERVICE_ACCOUNT (JSON key of a service account with the Firebase App Distribution Admin role)")
  fi
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "::error::Missing in this repository's GitHub environment '${GITHUB_ENVIRONMENT_NAME:-<env>}' (Settings → Environments):"
  for m in "${missing[@]}"; do echo "::error::  - $m"; done
  echo "See docs/github-distribution.md in mobile-idp for where each value comes from."
  exit 1
fi
echo "[ci-credentials] ok"
