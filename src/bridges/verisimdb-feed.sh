#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# verisimdb-feed.sh — PROVISIONAL local feed emitter.
#
# Writes an artefact-state-record's fields as a feed entry under
# verisimdb-data/feeds/ (gitignored). This is a LOCAL STUB: the upstream
# VeriSimDB "hexad" feed layout (hyperpolymath/nextgen-databases) is named but
# not yet specified, so this deliberately does NOT freeze a canonical six-tuple
# — it emits the v0 record fields plus a marker, to be reshaped when the real
# hexad schema lands. See docs/spec/ARTEFACT-STATE-RECORD.adoc and
# .machine_readable/integrations/verisimdb.a2ml.
#
# Usage:
#   verisimdb-feed.sh <id> <kind-code> <phase-code> <verification-code> [source-ref]
#
# Reads nothing from the network; the real sink is deferred to the re-transfer.

set -euo pipefail

if [ "$#" -lt 4 ]; then
    echo "usage: $0 <id> <kind> <phase> <verification> [source-ref]" >&2
    exit 2
fi

ID="$1"; KIND="$2"; PHASE="$3"; VERIF="$4"; SRC="${5:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FEED_DIR="${REPO_ROOT}/verisimdb-data/feeds"
mkdir -p "$FEED_DIR"

# Deterministic filename from the id (no timestamp — reproducible for tests).
SAFE_ID="$(printf '%s' "$ID" | tr -c 'A-Za-z0-9._-' '_')"
OUT="${FEED_DIR}/${SAFE_ID}.json"

# PROVISIONAL feed shape — not the canonical hexad. `feed-format` records that.
cat > "$OUT" <<JSON
{
  "feed-format": "provisional-v0",
  "record": {
    "schema-version": 1,
    "id": "${ID}",
    "kind": ${KIND},
    "phase": ${PHASE},
    "verification": ${VERIF},
    "source-ref": "${SRC}"
  },
  "note": "Local stub; reshape to the VeriSimDB hexad layout when specified upstream."
}
JSON

echo "wrote ${OUT}"
