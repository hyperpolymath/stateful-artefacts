#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
# Exercise the actual library build and C-ABI integration tests, not a template.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v zig >/dev/null || { echo 'Zig 0.15.2 is required.' >&2; exit 1; }
cd "$root/src/interface/ffi"
zig build --summary all
zig build test --summary all
bash "$root/tests/verisimdb-feed_test.sh"
bash "$root/tests/aspect_tests.sh"
