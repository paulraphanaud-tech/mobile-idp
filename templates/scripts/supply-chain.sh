#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# Supply-chain steps for CI: SBOM generation and dependency vulnerability
# scanning. Called from buildspec.yaml (Linux) and buildspec_ios.yml (macOS).
#
#   supply-chain.sh install          Fetch syft + osv-scanner
#   supply-chain.sh sbom <platform>  Write an SBOM for this build
#   supply-chain.sh scan <platform>  Scan dependencies, enforce SC_FAIL_ON
#   supply-chain.sh upload <platform>  Copy the reports to S3
#
# Configuration (all overridable as CodeBuild environment variables):
#
#   SC_ENABLED        true|false  Master switch.                 default true
#   SC_FAIL_ON        none|low|moderate|high|critical|any
#                     Minimum severity that fails the build.     default none
#   SC_OUT_DIR        Where reports are written.          default build/supply-chain
#   SC_TOOL_DIR       Where tools are installed.          default $HOME/.sc-tools
#   ARTIFACTS_BUCKET  S3 bucket for uploads. Injected by Terraform.
#   SYFT_VERSION      Pin, e.g. v1.20.0. Empty = latest.         default empty
#   OSV_SCANNER_VERSION  Pin, e.g. v2.0.2. Empty = latest.       default empty
#
# SC_FAIL_ON defaults to `none` deliberately: this is a template other projects
# inherit, and a scanner that starts failing builds on day one because of a
# transitive advisory nobody has triaged gets switched off entirely. Turn it up
# once the baseline is clean.
# =============================================================================

SC_ENABLED="${SC_ENABLED:-true}"
SC_FAIL_ON="${SC_FAIL_ON:-none}"
SC_OUT_DIR="${SC_OUT_DIR:-build/supply-chain}"
SC_TOOL_DIR="${SC_TOOL_DIR:-$HOME/.sc-tools}"
SYFT_VERSION="${SYFT_VERSION:-}"
OSV_SCANNER_VERSION="${OSV_SCANNER_VERSION:-}"

export PATH="$SC_TOOL_DIR:$PATH"

log()  { echo "[supply-chain] $*"; }
warn() { echo "[supply-chain] WARNING: $*" >&2; }

# Whether a tool failure should fail the build. If the operator asked for
# enforcement, a scanner that could not run is a failure — silently shipping
# unscanned code is the one outcome enforcement is meant to prevent.
enforcing() { [ "$SC_FAIL_ON" != "none" ]; }

soft_fail() {
  if enforcing; then
    echo "[supply-chain] ERROR: $* (failing because SC_FAIL_ON=$SC_FAIL_ON)" >&2
    exit 1
  fi
  warn "$* — continuing because SC_FAIL_ON=none"
  exit 0
}

host_os()   { uname -s | tr '[:upper:]' '[:lower:]'; }   # linux | darwin
host_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    arm64|aarch64) echo arm64 ;;
    *) uname -m ;;
  esac
}

# -----------------------------------------------------------------------------
# install
# -----------------------------------------------------------------------------
cmd_install() {
  mkdir -p "$SC_TOOL_DIR"

  if command -v syft >/dev/null 2>&1; then
    log "syft already present: $(syft version 2>/dev/null | head -1)"
  else
    log "installing syft${SYFT_VERSION:+ $SYFT_VERSION}"
    if ! curl -sSfL https://get.anchore.io/syft \
         | sh -s -- -b "$SC_TOOL_DIR" ${SYFT_VERSION:+"$SYFT_VERSION"} >/dev/null 2>&1; then
      warn "syft install failed"
    fi
  fi

  if command -v osv-scanner >/dev/null 2>&1; then
    log "osv-scanner already present"
  else
    local os arch url
    os="$(host_os)"; arch="$(host_arch)"
    if [ -n "$OSV_SCANNER_VERSION" ]; then
      url="https://github.com/google/osv-scanner/releases/download/${OSV_SCANNER_VERSION}/osv-scanner_${os}_${arch}"
    else
      url="https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_${os}_${arch}"
    fi
    log "installing osv-scanner from $url"
    if curl -sSfL "$url" -o "$SC_TOOL_DIR/osv-scanner" 2>/dev/null; then
      chmod +x "$SC_TOOL_DIR/osv-scanner"
    else
      warn "osv-scanner download failed"
    fi
  fi

  command -v syft        >/dev/null 2>&1 || warn "syft unavailable — SBOM step will be skipped"
  command -v osv-scanner >/dev/null 2>&1 || warn "osv-scanner unavailable — scan step will be skipped"
}

# -----------------------------------------------------------------------------
# sbom
# -----------------------------------------------------------------------------
cmd_sbom() {
  local platform="${1:?usage: supply-chain.sh sbom <android|ios>}"
  mkdir -p "$SC_OUT_DIR"

  command -v syft >/dev/null 2>&1 || soft_fail "syft not installed, no SBOM produced"

  local out="$SC_OUT_DIR/${platform}-sbom.cdx.json"
  log "generating CycloneDX SBOM -> $out"

  # Scanning the source tree (not the built artifact) is what catches the
  # dependency tree: syft reads pubspec.lock, Gemfile.lock, Podfile.lock and
  # the Gradle/Pod caches. An APK or IPA would only show what survived
  # shrinking.
  if ! syft scan "dir:." -o "cyclonedx-json=$out" -q; then
    soft_fail "syft failed to produce an SBOM"
  fi

  syft scan "dir:." -o table -q > "$SC_OUT_DIR/${platform}-sbom.txt" 2>/dev/null || true

  local n
  n="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1])).get('components',[])))" "$out" 2>/dev/null || echo "?")"
  log "SBOM written: $out ($n components)"
}

# -----------------------------------------------------------------------------
# scan
# -----------------------------------------------------------------------------
cmd_scan() {
  local platform="${1:?usage: supply-chain.sh scan <android|ios>}"
  mkdir -p "$SC_OUT_DIR"

  command -v osv-scanner >/dev/null 2>&1 || soft_fail "osv-scanner not installed, dependencies unscanned"

  local out="$SC_OUT_DIR/${platform}-vulns.json"
  log "scanning dependencies -> $out"

  # osv-scanner exits non-zero when it finds anything; that is data, not an
  # error, so the threshold check below decides the build's fate.
  osv-scanner --recursive --format json --output "$out" . >/dev/null 2>&1 || true

  if [ ! -s "$out" ]; then
    soft_fail "osv-scanner produced no report"
  fi

  osv-scanner --recursive --format table . > "$SC_OUT_DIR/${platform}-vulns.txt" 2>&1 || true

  python3 - "$out" "$SC_FAIL_ON" <<'PY'
import json, sys, collections

report_path, fail_on = sys.argv[1], sys.argv[2].lower()

# OSV severity lives in two places depending on the source database: GitHub
# advisories carry a word in database_specific.severity, while others carry a
# CVSS vector. Parsing a full CVSS vector is out of scope, so a numeric
# CVSS_V3 score is bucketed by the standard bands and anything else is
# reported as unknown rather than silently treated as harmless.
BANDS = ["unknown", "low", "moderate", "high", "critical"]

def cvss_band(score):
    if score >= 9.0: return "critical"
    if score >= 7.0: return "high"
    if score >= 4.0: return "moderate"
    if score > 0.0:  return "low"
    return "unknown"

def severity_of(vuln):
    db = (vuln.get("database_specific") or {}).get("severity")
    if isinstance(db, str):
        s = db.lower()
        if s in ("medium",): return "moderate"
        if s in BANDS: return s
    for sev in vuln.get("severity") or []:
        score = sev.get("score")
        try:
            return cvss_band(float(score))
        except (TypeError, ValueError):
            continue
    return "unknown"

try:
    report = json.load(open(report_path))
except Exception as exc:
    print(f"[supply-chain] could not parse the scan report: {exc}")
    sys.exit(0 if fail_on == "none" else 1)

counts = collections.Counter()
findings = []
for result in report.get("results", []):
    source = (result.get("source") or {}).get("path", "?")
    for pkg in result.get("packages", []):
        info = pkg.get("package", {})
        for vuln in pkg.get("vulnerabilities", []):
            band = severity_of(vuln)
            counts[band] += 1
            findings.append((band, info.get("name", "?"),
                             info.get("version", "?"),
                             vuln.get("id", "?"), source))

total = sum(counts.values())
if total == 0:
    print("[supply-chain] no known vulnerabilities found")
    sys.exit(0)

print(f"[supply-chain] {total} known vulnerabilities:")
for band in reversed(BANDS):
    if counts[band]:
        print(f"    {band:9} {counts[band]}")

order = {b: i for i, b in enumerate(BANDS)}
for band, name, version, vid, source in sorted(
        findings, key=lambda f: -order[f[0]])[:25]:
    print(f"    [{band}] {name} {version} — {vid}  ({source})")
if len(findings) > 25:
    print(f"    ... and {len(findings) - 25} more; see the JSON report")

if fail_on == "none":
    print("[supply-chain] SC_FAIL_ON=none — reporting only, not failing the build")
    sys.exit(0)

if fail_on == "any":
    print("[supply-chain] SC_FAIL_ON=any — failing")
    sys.exit(1)

if fail_on not in order:
    print(f"[supply-chain] SC_FAIL_ON='{fail_on}' is not a known severity "
          f"(expected one of: none, any, {', '.join(BANDS[1:])}) — failing "
          f"rather than guessing")
    sys.exit(1)

threshold = order[fail_on]
breaching = sum(c for b, c in counts.items() if order[b] >= threshold)
if breaching:
    print(f"[supply-chain] {breaching} finding(s) at or above '{fail_on}' — failing")
    sys.exit(1)

print(f"[supply-chain] nothing at or above '{fail_on}'")
if counts["unknown"]:
    print(f"[supply-chain] note: {counts['unknown']} finding(s) have no parsable "
          f"severity and were not counted against the threshold")
sys.exit(0)
PY
  local rc=$?
  [ "$rc" -eq 0 ] || exit "$rc"
}

# -----------------------------------------------------------------------------
# upload
# -----------------------------------------------------------------------------
cmd_upload() {
  local platform="${1:?usage: supply-chain.sh upload <android|ios>}"

  if [ -z "${ARTIFACTS_BUCKET:-}" ]; then
    warn "ARTIFACTS_BUCKET is not set — reports stay in $SC_OUT_DIR only"
    return 0
  fi
  [ -d "$SC_OUT_DIR" ] || { warn "no reports to upload"; return 0; }

  # Keyed by build id so a report can always be traced back to its build, and
  # so reports are never overwritten.
  local build_id="${CODEBUILD_BUILD_ID:-local-$(date +%Y%m%dT%H%M%S)}"
  local dest="s3://${ARTIFACTS_BUCKET}/supply-chain/${platform}/${build_id//:/_}/"

  log "uploading reports -> $dest"
  aws s3 cp "$SC_OUT_DIR" "$dest" --recursive --only-show-errors \
    || warn "upload failed — reports remain in $SC_OUT_DIR"
  log "reports at $dest"
}

# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
if [ "$SC_ENABLED" != "true" ]; then
  log "SC_ENABLED=$SC_ENABLED — skipping supply-chain step '${1:-}'"
  exit 0
fi

case "${1:-}" in
  install) cmd_install ;;
  sbom)    cmd_sbom "${2:-}" ;;
  scan)    cmd_scan "${2:-}" ;;
  upload)  cmd_upload "${2:-}" ;;
  *)
    echo "Usage: $0 {install|sbom <platform>|scan <platform>|upload <platform>}"
    exit 1
    ;;
esac
