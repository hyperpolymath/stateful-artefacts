#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# verisimdb-feed.sh — PROVISIONAL local feed emitter.
#
# Writes a local provisional-v0 record under verisimdb-data/feeds/ (gitignored).
# This is not an upstream VeriSimDB API payload: no record-to-modality-profile
# mapping, agreed adapter contract, or network sink exists yet. Current upstream
# docs name its eight-modality contract Octad; see
# https://github.com/hyperpolymath/verisimdb, issue #68,
# docs/spec/ARTEFACT-STATE-RECORD.adoc, and docs/RE-TRANSFER-RUNBOOK.adoc.
#
# Usage:
#   verisimdb-feed.sh <id> <kind-code> <phase-code> <verification-code> [source-ref]
#
# Requires iconv (UTF-8 validation), jq (JSON string escaping), and sha256sum
# or shasum (collision-resistant local filenames). It reads nothing from the network.

set -euo pipefail
export LC_ALL=C

usage() {
    echo "usage: $0 <id> <kind> <phase> <verification> [source-ref]" >&2
    exit 2
}

fail_input() {
    printf 'error: %s\n' "$1" >&2
    exit 2
}

if [[ "$#" -lt 4 || "$#" -gt 5 ]]; then
    usage
fi

ID="$1"
KIND="$2"
PHASE="$3"
VERIF="$4"
SRC="${5:-}"

# Match the v0 record's 255-byte string limit. LC_ALL=C makes Bash count bytes,
# as the Zig BStr implementation does. Control characters remain valid input;
# jq escapes them when it writes JSON.
if [[ -z "$ID" ]]; then
    fail_input "id must not be empty"
fi
if (( ${#ID} > 255 )); then
    fail_input "id must be at most 255 bytes"
fi
if (( ${#SRC} > 255 )); then
    fail_input "source-ref must be at most 255 bytes"
fi
if ! command -v iconv >/dev/null 2>&1; then
    echo "error: iconv is required to validate UTF-8 JSON string inputs" >&2
    exit 127
fi
if ! printf '%s' "$ID" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    fail_input "id must be valid UTF-8"
fi
if ! printf '%s' "$SRC" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    fail_input "source-ref must be valid UTF-8"
fi

# These are the stable enum codes from docs/spec/ARTEFACT-STATE-RECORD.adoc.
# Exact-string whitelists avoid arithmetic evaluation or JSON-number injection.
case "$KIND" in
    0|1|2|3|4) ;;
    *) fail_input "kind must be one of 0, 1, 2, 3, or 4" ;;
esac
case "$PHASE" in
    0|1|2|3|4) ;;
    *) fail_input "phase must be one of 0, 1, 2, 3, or 4" ;;
esac
case "$VERIF" in
    0|1|2) ;;
    *) fail_input "verification must be one of 0, 1, or 2" ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required to serialize the provisional feed safely" >&2
    exit 127
fi
if command -v sha256sum >/dev/null 2>&1; then
    ID_HASH="$(printf '%s' "$ID" | sha256sum)"
elif command -v shasum >/dev/null 2>&1; then
    ID_HASH="$(printf '%s' "$ID" | shasum -a 256)"
else
    echo "error: sha256sum or shasum is required to derive a safe deterministic filename" >&2
    exit 127
fi
ID_HASH="${ID_HASH%% *}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FEED_DIR="${REPO_ROOT}/verisimdb-data/feeds"

# Keep a short readable prefix, then hash the full id so sanitization and
# truncation cannot make distinct IDs overwrite each other's local records.
SAFE_ID="$(printf '%s' "$ID" | tr -c 'A-Za-z0-9._-' '_')"
SAFE_ID="${SAFE_ID:0:64}"
OUT="${FEED_DIR}/${SAFE_ID}-${ID_HASH}.json"

mkdir -p "$FEED_DIR"
TMP="$(mktemp "${FEED_DIR}/.feed.XXXXXX")"
trap 'rm -f -- "$TMP"' EXIT

# String values are passed as jq arguments, never interpolated into JSON source.
# The numeric arguments have already passed exact enum-code validation above.
if ! jq -n \
    --arg id "$ID" \
    --arg source_ref "$SRC" \
    --argjson kind "$KIND" \
    --argjson phase "$PHASE" \
    --argjson verification "$VERIF" \
    '{
      "feed-format": "provisional-v0",
      "record": {
        "schema-version": 1,
        "id": $id,
        "kind": $kind,
        "phase": $phase,
        "verification": $verification,
        "source-ref": $source_ref
      },
      "note": "Provisional local record only; no upstream modality-profile mapping or network sink."
    }' > "$TMP"; then
    echo "error: jq could not serialize the provisional record" >&2
    exit 1
fi

mv -f -- "$TMP" "$OUT"
echo "wrote ${OUT}"
