#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# RSR Standard Aspect Test Template
#
# Aspect tests validate cross-cutting architectural invariants that span
# the entire codebase. These are NOT functional tests — they verify that
# coding standards, safety rules, and structural contracts hold.
#
# Usage:
#   bash tests/aspect_tests.sh
#   just aspect
#
# Standard aspects (enable what applies to your project):
#   1. SPDX compliance — all source files have license headers
#   2. Dangerous patterns — no believe_me, assert_total, sorry, unsafeCoerce, etc.
#   3. ABI/FFI contract — declarations match exports
#   4. Thread safety — mutex in FFI modules
#   5. Error handling — no panic/unreachable in production paths

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
WARN=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

pass() { green "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { red "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { yellow "  WARN: $1"; WARN=$((WARN + 1)); }

echo "═══════════════════════════════════════════════════════════════"
echo "  STATEFUL_ARTEFACTS — Aspect Tests (Cross-Cutting Concerns)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════════════
# Aspect 1: SPDX License Headers
# ═══════════════════════════════════════════════════════════════════════
bold "Aspect 1: SPDX license headers"

MISSING_SPDX=0
while IFS= read -r -d '' f; do
    if ! head -5 "$f" | grep -q "SPDX-License-Identifier"; then
        warn "Missing SPDX header: $f"
        MISSING_SPDX=$((MISSING_SPDX + 1))
    fi
done < <(find src/ -type d \( -name '.zig-cache' -o -name 'zig-out' \) -prune -o -type f \( -name "*.rs" -o -name "*.zig" -o -name "*.res" -o -name "*.ex" -o -name "*.exs" -o -name "*.gleam" -o -name "*.idr" -o -name "*.sh" \) -print0 2>/dev/null)

if [ "$MISSING_SPDX" -eq 0 ]; then
    pass "All source files have SPDX headers"
else
    fail "$MISSING_SPDX files missing SPDX headers"
fi

# ═══════════════════════════════════════════════════════════════════════
# Aspect 2: Dangerous Patterns (BANNED)
# ═══════════════════════════════════════════════════════════════════════
bold "Aspect 2: Dangerous patterns"

# Idris2 dangerous patterns
DANGEROUS_IDRIS=$(grep -rn 'believe_me\|assert_total\|really_believe_me' src/interface/Abi/ 2>/dev/null | grep -v "^Binary" | grep -v "test" || true)
if [ -n "$DANGEROUS_IDRIS" ]; then
    fail "Dangerous Idris2 patterns found:"
    echo "$DANGEROUS_IDRIS" | head -5
else
    pass "No dangerous Idris2 patterns (believe_me, assert_total)"
fi

# Coq/Lean/Agda/Haskell dangerous patterns.
# Scan proof SOURCE files only (prose docs describe the ban and must not trip
# it). Match real proof-abandoning forms: Coq's `Admitted.` (the cautionary
# comment "NO Admitted allowed" has no trailing period), Lean/Agda `sorry`,
# `unsafeCoerce`, `Obj.magic`. Strip single-line comments (--, //, *, #).
DANGEROUS_PROOF=$(grep -rnE \
    --include='*.v' --include='*.lean' --include='*.agda' --include='*.idr' --include='*.hs' --include='*.ml' \
    'Admitted\.|\bsorry\b|\bunsafeCoerce\b|\bObj\.magic\b' \
    src/ verification/ 2>/dev/null \
    | grep -vE ':[0-9]+:[[:space:]]*(--|//|\*|#)' \
    | grep -v "test" || true)
if [ -n "$DANGEROUS_PROOF" ]; then
    fail "Dangerous proof patterns found:"
    echo "$DANGEROUS_PROOF" | head -5
else
    pass "No dangerous proof patterns (Admitted, sorry, unsafeCoerce)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Aspect 3: ABI/FFI Contract parity
# ═══════════════════════════════════════════════════════════════════════
bold "Aspect 3: ABI/FFI contract"
ABI_DIR="src/interface/Abi"
FFI_DIR="src/interface/ffi/src"
if [ -d "$ABI_DIR" ] && [ -d "$FFI_DIR" ]; then
    # Every %foreign binding on the Idris2 side must have a matching
    # `export fn stateful_artefacts_*` on the Zig side. We compare the
    # concrete C symbol names so drift (renames, prefix mismatch) fails here.
    ABI_SYMS=$(grep -rhoP '(?<=C:)stateful_artefacts_[a-z_]+' "$ABI_DIR" 2>/dev/null | sort -u)
    FFI_SYMS=$(grep -rhoP '(?<=export fn )stateful_artefacts_[a-z_]+' "$FFI_DIR" 2>/dev/null | sort -u)
    MISSING_EXPORTS=$(comm -23 <(echo "$ABI_SYMS") <(echo "$FFI_SYMS") | grep -v '^$' || true)
    if [ -z "$MISSING_EXPORTS" ] && [ -n "$ABI_SYMS" ]; then
        ABI_N=$(echo "$ABI_SYMS" | grep -c .)
        FFI_N=$(echo "$FFI_SYMS" | grep -c .)
        pass "ABI/FFI parity: all $ABI_N Idris2 %foreign symbols exported by Zig ($FFI_N exports total)"
    else
        fail "ABI/FFI drift: Idris2 binds symbols the Zig layer does not export:"
        echo "$MISSING_EXPORTS" | head -10
    fi
else
    pass "ABI/FFI not applicable (no $ABI_DIR or $FFI_DIR)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Aspect 4: Error Handling (no raw panic in production code)
# ═══════════════════════════════════════════════════════════════════════
# Uncomment for Rust projects:

# bold "Aspect 4: Error handling"
# UNWRAP_COUNT=$(grep -rn '\.unwrap()' src/ 2>/dev/null | grep -v "test" | grep -v "example" | wc -l)
# if [ "$UNWRAP_COUNT" -gt 20 ]; then
#     warn "$UNWRAP_COUNT .unwrap() calls in src/ — consider replacing with ? or expect()"
# else
#     pass "Acceptable unwrap count: $UNWRAP_COUNT"
# fi

# ═══════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
printf "  Results: "
green "PASS=$PASS" | tr -d '\n'
echo -n "  "
if [ "$FAIL" -gt 0 ]; then red "FAIL=$FAIL" | tr -d '\n'; else echo -n "FAIL=0"; fi
echo -n "  "
if [ "$WARN" -gt 0 ]; then yellow "WARN=$WARN"; else echo "WARN=0"; fi
echo ""
echo "═══════════════════════════════════════════════════════════════"

exit "$FAIL"
