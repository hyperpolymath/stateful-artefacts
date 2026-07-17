#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# retransfer-from-reposystem.sh — prepare the reposystem -> stateful-artefacts
# domain re-transfer. See docs/RE-TRANSFER-RUNBOOK.adoc.
#
# This script is MAINTAINER-RUN on a machine that has a reposystem clone; it is
# not run in CI (reposystem is unreachable there). It is DRY-RUN by default and
# never touches this repo's working tree unless DRY_RUN=0 is set explicitly.
#
# Inputs (environment variables):
#   REPOS_DIR   Directory containing the reposystem clone (expects $REPOS_DIR/reposystem).
#               Or set REPOSYSTEM_DIR to point straight at the clone.
#   SLICE       Space-separated list of reposystem paths to take (with history).
#               Default: the candidate slice from the runbook.
#   MODE        "history" (git filter-repo, default) or "copy" (plain file copy).
#   DRY_RUN     "1" (default) prints the plan; "0" executes.
#
# Example:
#   REPOS_DIR=~/repos SLICE="src/verisimdb.rs spec/DATA-MODEL.adoc" \
#     bash scripts/retransfer-from-reposystem.sh
#
# Exit codes: 0 ok / plan printed; 2 usage or environment error.

set -euo pipefail

# ---- Resolve inputs -------------------------------------------------------
if [ -n "${REPOSYSTEM_DIR:-}" ]; then
    :                                        # explicit clone path wins
elif [ -n "${REPOS_DIR:-}" ]; then
    REPOSYSTEM_DIR="${REPOS_DIR%/}/reposystem"
else
    REPOSYSTEM_DIR=""                        # triggers the usage error below
fi
MODE="${MODE:-history}"
DRY_RUN="${DRY_RUN:-1}"
SLICE="${SLICE:-src/verisimdb.rs src/graph.rs src/lib.rs spec/DATA-MODEL.adoc}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # this repo root
SCRATCH="${HERE}/.retransfer-scratch"                     # gitignored workspace
REMOTE_NAME="reposystem-slice"

say()  { printf '%s\n' "$*"; }
step() { printf '\n=== %s ===\n' "$*"; }

# ---- Preconditions --------------------------------------------------------
if [ -z "${REPOS_DIR:-}" ] && [ -z "${REPOSYSTEM_DIR:-}" ]; then
    say "ERROR: set REPOS_DIR (containing reposystem/) or REPOSYSTEM_DIR." >&2
    exit 2
fi
if [ ! -d "$REPOSYSTEM_DIR/.git" ]; then
    say "ERROR: no git repo at REPOSYSTEM_DIR=$REPOSYSTEM_DIR" >&2
    say "       Clone reposystem there first, or point REPOSYSTEM_DIR at it." >&2
    exit 2
fi
if [ "$MODE" = "history" ] && ! command -v git-filter-repo >/dev/null 2>&1 \
   && ! git filter-repo --help >/dev/null 2>&1; then
    say "ERROR: git-filter-repo not found (needed for MODE=history)." >&2
    say "       Install it (pipx install git-filter-repo) or use MODE=copy." >&2
    exit 2
fi

# ---- Warn about paths that do not exist in the source ---------------------
step "Slice check (against $REPOSYSTEM_DIR)"
MISSING=0
for p in $SLICE; do
    if [ -e "$REPOSYSTEM_DIR/$p" ]; then
        say "  present: $p"
    else
        say "  MISSING: $p   (confirm the path in reposystem's current tree)"
        MISSING=1
    fi
done
[ "$MISSING" = 1 ] && say "  note: reposystem's layout may have moved since its README; adjust SLICE."

# ---- The plan -------------------------------------------------------------
step "Plan (MODE=$MODE)"
say "  scratch workspace : $SCRATCH"
if [ "$MODE" = "history" ]; then
    say "  1. cp -r reposystem -> scratch, then in scratch:"
    say "       git filter-repo $(for p in $SLICE; do printf -- '--path %s ' "$p"; done)"
    say "  2. In this repo:"
    say "       git remote add $REMOTE_NAME $SCRATCH"
    say "       git fetch $REMOTE_NAME"
    say "       git merge --allow-unrelated-histories $REMOTE_NAME/<branch>"
else
    say "  copy (no history): rsync the SLICE paths from reposystem into this tree,"
    say "  then place per docs/RE-TRANSFER-RUNBOOK.adoc section 3."
fi
say "  3. Land + reconcile onto the v0 record (runbook section 3)."
say "  4. Update META/STATE/README/AFFIRMATION; run the verification gates (section 6)."

if [ "$DRY_RUN" != "0" ]; then
    step "DRY RUN"
    say "  No changes made. Re-run with DRY_RUN=0 to execute the extraction."
    exit 0
fi

# ---- Execute (DRY_RUN=0) --------------------------------------------------
step "Executing (DRY_RUN=0)"
rm -rf "$SCRATCH"
if [ "$MODE" = "history" ]; then
    cp -r "$REPOSYSTEM_DIR" "$SCRATCH"
    ( cd "$SCRATCH" && git filter-repo $(for p in $SLICE; do printf -- '--path %s ' "$p"; done) )
    git -C "$HERE" remote remove "$REMOTE_NAME" 2>/dev/null || true
    git -C "$HERE" remote add "$REMOTE_NAME" "$SCRATCH"
    git -C "$HERE" fetch "$REMOTE_NAME"
    say ""
    say "Filtered history fetched as remote '$REMOTE_NAME'. Now merge the branch:"
    say "  git merge --allow-unrelated-histories $REMOTE_NAME/main   # or the source branch"
    say "Then follow docs/RE-TRANSFER-RUNBOOK.adoc sections 3-6."
else
    mkdir -p "$SCRATCH"
    for p in $SLICE; do
        [ -e "$REPOSYSTEM_DIR/$p" ] || continue
        mkdir -p "$SCRATCH/$(dirname "$p")"
        cp -r "$REPOSYSTEM_DIR/$p" "$SCRATCH/$p"
    done
    say "Copied SLICE into $SCRATCH (no history). Place per the runbook, then verify."
fi
