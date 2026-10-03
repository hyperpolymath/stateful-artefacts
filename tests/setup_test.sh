#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
# Exercise bootstrap failure paths without installing anything or networking.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
# Source only definitions, asserting that the final line remains the entrypoint.
[[ "$(tail -1 "$root/build/setup.sh")" == 'main "$@"' ]]
sed '$d' "$root/build/setup.sh" > "$scratch/definitions.sh"
mkdir "$scratch/bin"
export BOOTSTRAP_CALLS="$scratch/calls"
cat > "$scratch/bin/sudo" <<'MOCK'
#!/bin/sh
printf 'sudo %s\n' "$*" >> "$BOOTSTRAP_CALLS"
exit 1
MOCK
for tool in curl wget bash; do
    cat > "$scratch/bin/$tool" <<'MOCK'
#!/bin/sh
printf 'UNSAFE %s\n' "$0" >> "$BOOTSTRAP_CALLS"
exit 99
MOCK
done
chmod +x "$scratch/bin/"*
for manager in apt unknown; do
    if PATH="$scratch/bin" /bin/sh -c '. "$1"; PKG_MGR="$2"; install_just' sh "$scratch/definitions.sh" "$manager" > "$scratch/output" 2>&1; then
        echo "FAIL: $manager unexpectedly installed just" >&2
        exit 1
    fi
    grep -q 'rerun setup' "$scratch/output"
    if grep -q UNSAFE "$BOOTSTRAP_CALLS"; then
        echo 'FAIL: attempted an unverified installer' >&2; exit 1
    fi
    echo "PASS: $manager fails closed without remote execution"
done
cat > "$scratch/bin/just" <<'MOCK'
#!/bin/sh
printf 'just test-fixture\n'
MOCK
chmod +x "$scratch/bin/just"
ln -s "$(command -v head)" "$scratch/bin/head"
: > "$BOOTSTRAP_CALLS"
PATH="$scratch/bin" /bin/sh -c '. "$1"; install_just' sh "$scratch/definitions.sh" > "$scratch/output"
grep -q 'already installed' "$scratch/output"
[[ ! -s "$BOOTSTRAP_CALLS" ]]
echo 'PASS: existing just is reused without installation'
