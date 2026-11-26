#!/usr/bin/env bash
set -euo pipefail

APK_PATH=""
CHANNEL="github"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXPECTED_CERTS_FILE="${REPO_ROOT}/android/signing/expected_certs.json"
EXPECTED_SHA256="${LIFEOS_EXPECTED_CERT_SHA256:-}"

usage() {
  cat <<'EOF'
Usage: verify_apk_signature.sh --apk <path> [--channel <github|play>] [--expected-certs <path>] [--expected-sha256 <hex>]
   or: verify_apk_signature.sh <apk_path> [github|play]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk)
      APK_PATH="${2:-}"
      shift 2
      ;;
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --expected-certs)
      EXPECTED_CERTS_FILE="${2:-}"
      shift 2
      ;;
    --expected-sha256)
      EXPECTED_SHA256="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$APK_PATH" ]]; then
        APK_PATH="$1"
      elif [[ "$CHANNEL" == "github" && ("$1" == "github" || "$1" == "play") ]]; then
        CHANNEL="$1"
      else
        echo "FAIL: Unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$APK_PATH" ]]; then
  echo "FAIL: Missing --apk path." >&2
  usage >&2
  exit 1
fi

if [[ "$CHANNEL" != "github" && "$CHANNEL" != "play" ]]; then
  echo "FAIL: Invalid channel '$CHANNEL'. Must be 'github' or 'play'." >&2
  exit 1
fi

if [[ ! -f "$APK_PATH" || ! -s "$APK_PATH" ]]; then
  echo "FAIL: APK file missing or empty: $APK_PATH" >&2
  exit 1
fi

resolve_apksigner() {
  if command -v apksigner >/dev/null 2>&1; then
    command -v apksigner
    return 0
  fi
  for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "${HOME}/Android/Sdk"; do
    if [[ -n "$sdk_root" && -d "$sdk_root/build-tools" ]]; then
      local found
      found=$(find "$sdk_root/build-tools" -maxdepth 2 \( -name apksigner -o -name apksigner.bat \) 2>/dev/null | sort -V | tail -n 1 || true)
      if [[ -n "$found" ]]; then
        echo "$found"
        return 0
      fi
    fi
  done
  return 1
}

APKSIGNER_BIN=$(resolve_apksigner || true)
if [[ -z "$APKSIGNER_BIN" ]]; then
  echo "FAIL: apksigner not found on PATH or inside ANDROID_HOME/ANDROID_SDK_ROOT/build-tools." >&2
  exit 1
fi

APK_SHA256=$(sha256sum "$APK_PATH" | awk '{print tolower($1)}')
GIT_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")

echo "=== LifeOS APK Signature Verification ==="
echo "APK Path        : $APK_PATH"
echo "Channel         : $CHANNEL"
echo "Git Commit      : $GIT_COMMIT"
echo "APK File SHA-256: $APK_SHA256"
echo "apksigner       : $APKSIGNER_BIN"

set +e
VERIFY_OUTPUT=$("$APKSIGNER_BIN" verify --verbose --print-certs "$APK_PATH" 2>&1)
VERIFY_EXIT=$?
set -e

echo "$VERIFY_OUTPUT"
if [[ $VERIFY_EXIT -ne 0 ]]; then
  echo "FAIL: apksigner verify failed with exit code $VERIFY_EXIT." >&2
  exit 1
fi

PYTHON_BIN=$(command -v python3 || command -v python || true)
if [[ -z "$PYTHON_BIN" ]]; then
  echo "FAIL: python3 or python is required to parse expected_certs.json." >&2
  exit 1
fi

"$PYTHON_BIN" - "$VERIFY_OUTPUT" "$CHANNEL" "$EXPECTED_CERTS_FILE" "$EXPECTED_SHA256" "$APK_SHA256" "$GIT_COMMIT" <<'PY'
import json
import os
import re
import sys

verify_output, channel, certs_file, expected_override, apk_sha256, git_commit = sys.argv[1:7]

def norm_hex(raw: str) -> str:
    cleaned = (raw or "").strip().lower()
    if cleaned.startswith("sha256:"):
        cleaned = cleaned[7:].strip()
    return re.sub(r"[:\s-]", "", cleaned)

def is_placeholder_or_invalid(raw: str) -> bool:
    if not raw or not raw.strip():
        return True
    up = raw.strip().upper()
    if "REPLACE_WITH" in up or "PLACEHOLDER" in up or "CHANGE_ME" in up:
        return True
    return re.fullmatch(r"[0-9a-f]{64}", norm_hex(raw)) is None

dns = []
digests = []
for line in verify_output.splitlines():
    m_dn = re.search(r"Signer\s+(?:#\d+|\([^)]+\))\s+certificate DN:\s*(.+)$", line)
    if m_dn:
        dns.append(m_dn.group(1).strip())
    m_sha = re.search(r"Signer\s+(?:#\d+|\([^)]+\))\s+certificate SHA-256 digest:\s*([0-9a-fA-F:]+)\s*$", line)
    if m_sha:
        digests.append(norm_hex(m_sha.group(1)))

if not digests:
    print("FAIL: Could not extract any signer certificate SHA-256 digest from apksigner output.", file=sys.stderr)
    sys.exit(1)

failures = []
rejected_dns = ["CN=Android Debug"]
rejected_sha256s = {"3c1738043f4ed47e6f5f5724ab3e9fd0b24e89fde667af43670cb630e4d5176b"}
allowed_lineage = set()
expected_raw = expected_override

if os.path.isfile(certs_file):
    with open(certs_file, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    if cfg.get("rejected_signer_dn_substrings"):
        rejected_dns = list(cfg["rejected_signer_dn_substrings"])
    if cfg.get("rejected_cert_sha256s"):
        rejected_sha256s = {norm_hex(x) for x in cfg["rejected_cert_sha256s"]}
    ch_cfg = (cfg.get("channels") or {}).get(channel)
    if not ch_cfg:
        failures.append(f"Channel '{channel}' missing from {certs_file}.")
    elif not expected_raw.strip():
        expected_raw = str(ch_cfg.get("cert_sha256") or "")
        for lin in ch_cfg.get("lineage_cert_sha256s") or []:
            if is_placeholder_or_invalid(str(lin)):
                failures.append(f"Placeholder or invalid SHA-256 in {certs_file} ({channel}.lineage_cert_sha256s): {lin}")
            else:
                allowed_lineage.add(norm_hex(str(lin)))
elif not expected_raw.strip():
    failures.append(f"Expected certs file not found ({certs_file}) and no --expected-sha256 provided.")

for dn in dns:
    for blocked in rejected_dns:
        if blocked.lower() in dn.lower():
            failures.append(f"REJECTED: APK carries forbidden debug/rejected signer DN '{dn}' (matched '{blocked}').")

for d in digests:
    if d in rejected_sha256s:
        failures.append(f"REJECTED: APK signer SHA-256 '{d}' is explicitly blocked (Android Debug certificate).")

if is_placeholder_or_invalid(expected_raw):
    failures.append(
        f"REJECTED: Expected certificate SHA-256 for channel '{channel}' is still a placeholder or invalid hex: '{expected_raw}'. "
        f"Update {certs_file} or pass --expected-sha256 / LIFEOS_EXPECTED_CERT_SHA256."
    )
else:
    expected_norm = norm_hex(expected_raw)
    print(f"Expected Cert   : {expected_norm}")
    active_signer = digests[-1]
    if active_signer != expected_norm:
        failures.append(
            f"REJECTED: APK active signer SHA-256 '{active_signer}' does NOT match expected '{expected_norm}' for channel '{channel}'."
        )
    for d in digests:
        if d != expected_norm and d not in allowed_lineage:
            failures.append(
                f"REJECTED: APK signer SHA-256 '{d}' is neither expected '{expected_norm}' nor an approved lineage cert for channel '{channel}'."
            )

if failures:
    for msg in failures:
        print(msg, file=sys.stderr)
    sys.exit(1)

print(f"PASS: APK signature verified for channel '{channel}' (commit {git_commit}, file SHA-256 {apk_sha256}).")
PY
