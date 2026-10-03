#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ ! -e .machine_readable/6a2 ]]
for name in STATE META ECOSYSTEM PLAYBOOK AGENTIC NEUROSYM CLADE; do
    [[ -s ".machine_readable/descriptiles/$name.a2ml" ]]
    grep -Fq "descriptiles/$name.a2ml" .machine_readable/0.1-AI-MANIFEST.a2ml
done
[[ -s .machine_readable/descriptiles/anchors/ANCHOR.a2ml ]]
# Machine consumers must agree with the human-facing manifest.
for consumer in Justfile build/just/validate.just build/just/assess.just build/just/groove.just .github/workflows/openssf-compliance.yml .machine_readable/contractiles/Mustfile.a2ml; do
    grep -Fq '.machine_readable/descriptiles/STATE.a2ml' "$consumer"
    if grep -Fq '.machine_readable/6a2' "$consumer"; then
        echo "FAIL: retired metadata path in $consumer" >&2; exit 1
    fi
done
echo 'PASS: canonical metadata tree and build/CI/agent consumers agree'
