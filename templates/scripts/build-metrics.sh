#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Build instrumentation.
#
#   build-metrics.sh start
#   build-metrics.sh finish <platform>
#
# Emits two things per build:
#
#   BuildDurationSeconds  wall-clock time of the build
#   LeadTimeSeconds       commit timestamp -> build finish, i.e. how long a
#                         merged change waits before it exists as a
#                         distributable artifact
#
# Both go to stdout (so CloudWatch Logs Insights can read them without any
# extra setup) and to a CloudWatch custom metric (so they can be graphed and
# alarmed on). See docs/metrics.md.
#
# Configuration:
#   METRICS_ENABLED    true|false                       default true
#   METRICS_NAMESPACE  CloudWatch namespace             default MobileIDP
#   ENVIRONMENT        dimension value; injected by Terraform   default unknown
#   AWS_REGION / FL_AWS_REGION
#
# Never fails a build. An instrumentation problem must not become a delivery
# problem — every failure path here warns and exits 0.
# =============================================================================

METRICS_ENABLED="${METRICS_ENABLED:-true}"
METRICS_NAMESPACE="${METRICS_NAMESPACE:-MobileIDP}"
STATE_FILE="${METRICS_STATE_FILE:-/tmp/.build-metrics-start}"

log()  { echo "[metrics] $*"; }
warn() { echo "[metrics] WARNING: $*" >&2; }

[ "$METRICS_ENABLED" = "true" ] || { log "disabled"; exit 0; }

# CODEBUILD_BUILD_ID looks like "project:uuid"; the part before the colon is
# the project name, which is the closest thing to a stable series name.
project_name() {
  if [ -n "${PROJECT_NAME:-}" ]; then echo "$PROJECT_NAME"; return; fi
  echo "${CODEBUILD_BUILD_ID:-local}" | cut -d: -f1
}

put_metric() {
  local name="$1" value="$2" unit="$3" platform="$4" status="$5"
  local region="${AWS_REGION:-${FL_AWS_REGION:-eu-west-1}}"

  command -v aws >/dev/null 2>&1 || { warn "aws CLI not found, metric not sent"; return 0; }

  aws cloudwatch put-metric-data \
    --namespace "$METRICS_NAMESPACE" \
    --region "$region" \
    --metric-data "$(cat <<JSON
[{"MetricName":"$name","Value":$value,"Unit":"$unit","Dimensions":[
  {"Name":"Project","Value":"$(project_name)"},
  {"Name":"Platform","Value":"$platform"},
  {"Name":"Environment","Value":"${ENVIRONMENT:-unknown}"},
  {"Name":"Status","Value":"$status"}]}]
JSON
)" 2>/dev/null \
    || warn "could not publish $name (needs cloudwatch:PutMetricData on namespace $METRICS_NAMESPACE)"
}

cmd_start() {
  date +%s > "$STATE_FILE"
  log "build started at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

cmd_finish() {
  local platform="${1:-unknown}"
  local end; end="$(date +%s)"

  # CODEBUILD_BUILD_SUCCEEDING is 1 while the build is still healthy, 0 once a
  # phase has failed. post_build runs either way, so this distinguishes them.
  local status="success"
  [ "${CODEBUILD_BUILD_SUCCEEDING:-1}" = "1" ] || status="failure"

  log "build finished at $(date -u '+%Y-%m-%dT%H:%M:%SZ') (status=$status)"

  if [ -r "$STATE_FILE" ]; then
    local start duration
    start="$(cat "$STATE_FILE")"
    duration=$(( end - start ))
    log "BuildDurationSeconds=$duration platform=$platform status=$status"
    put_metric BuildDurationSeconds "$duration" Seconds "$platform" "$status"
  else
    warn "no start marker — run 'build-metrics.sh start' in the install phase"
  fi

  # Lead time: when the commit being built was authored, to now. On a
  # merge-triggered pipeline that is merge-to-artifact. Needs real git history;
  # CodeBuild clones with depth 1, which still carries HEAD's own timestamp.
  if git rev-parse --git-dir >/dev/null 2>&1; then
    local commit_ts lead
    commit_ts="$(git show -s --format=%ct HEAD 2>/dev/null || echo "")"
    if [ -n "$commit_ts" ]; then
      lead=$(( end - commit_ts ))
      if [ "$lead" -ge 0 ]; then
        log "LeadTimeSeconds=$lead (commit $(git rev-parse --short HEAD 2>/dev/null))"
        put_metric LeadTimeSeconds "$lead" Seconds "$platform" "$status"
      fi
    fi
  fi
}

case "${1:-}" in
  start)  cmd_start ;;
  finish) cmd_finish "${2:-}" ;;
  *) echo "Usage: $0 {start|finish <platform>}"; exit 1 ;;
esac
