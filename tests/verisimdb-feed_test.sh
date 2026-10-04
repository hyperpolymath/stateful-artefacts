#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# Exercise only the local provisional-v0 emitter. This is deliberately not an
# upstream contract test; no v0-to-modality-profile mapping has been agreed.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
fixture="$work/repo"
script="$fixture/src/bridges/verisimdb-feed.sh"
mkdir -p "$fixture/src/bridges"
cp "$root/src/bridges/verisimdb-feed.sh" "$script"
chmod +x "$script"

for tool in iconv jq tr; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "FAIL: $tool is required for the provisional-feed test" >&2
        exit 1
    }
done
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "FAIL: sha256sum or shasum is required for the provisional-feed test" >&2
    exit 1
fi

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

feed_path_for() {
    local id="$1" safe_id id_hash
    safe_id="$(printf '%s' "$id" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
    safe_id="${safe_id:0:64}"
    if command -v sha256sum >/dev/null 2>&1; then
        id_hash="$(printf '%s' "$id" | sha256sum)"
    else
        id_hash="$(printf '%s' "$id" | shasum -a 256)"
    fi
    id_hash="${id_hash%% *}"
    printf '%s/verisimdb-data/feeds/%s-%s.json' "$fixture" "$safe_id" "$id_hash"
}

# A normal record keeps strings as strings and enum codes as JSON numbers.
normal_id='artifact-1'
normal_source='repo://example/project@abc123'
normal_output="$("$script" "$normal_id" 2 1 0 "$normal_source")"
normal_file="${normal_output#wrote }"
[[ "$normal_output" == "wrote "* && -f "$normal_file" ]] || fail "normal invocation did not write a record"
jq -e \
    --arg id "$normal_id" \
    --arg source "$normal_source" \
    '."feed-format" == "provisional-v0"
     and .record["schema-version"] == 1
     and .record.id == $id
     and .record.kind == 2 and (.record.kind | type) == "number"
     and .record.phase == 1 and (.record.phase | type) == "number"
     and .record.verification == 0 and (.record.verification | type) == "number"
     and .record["source-ref"] == $source
     and (.record | keys | sort) == ["id", "kind", "phase", "schema-version", "source-ref", "verification"]' \
    "$normal_file" >/dev/null || fail "normal provisional-v0 JSON contract is wrong"
pass "normal fields are valid JSON with the expected local provisional-v0 types"

# Quotes, backslashes, newlines, tabs, and C0/DEL controls round-trip exactly.
special_id=$'artifact-"quoted"-\\path\nnext-line\ttab-ctrl:\001-del:\177'
special_source=$'repo://example/"quoted"/\\path\nnext\tctrl:\002'
special_output="$("$script" "$special_id" 4 4 2 "$special_source")"
special_file="${special_output#wrote }"
[[ "$special_output" == "wrote "* && -f "$special_file" ]] || fail "special-character invocation did not write a record"
jq -e \
    --arg id "$special_id" \
    --arg source "$special_source" \
    '.record.id == $id and .record["source-ref"] == $source' \
    "$special_file" >/dev/null || fail "special-character fields did not round-trip exactly"
pass "quotes, backslashes, whitespace, and control characters are safely escaped and preserved"

# IDs that sanitize to the same readable filename prefix must not collide.
collision_a='same prefix/one'
collision_b='same prefix?one'
[[ "$(feed_path_for "$collision_a")" != "$(feed_path_for "$collision_b")" ]] || fail "test IDs unexpectedly have the same path"
"$script" "$collision_a" 0 0 0 >/dev/null
"$script" "$collision_b" 0 0 0 >/dev/null
file_a="$(feed_path_for "$collision_a")"
file_b="$(feed_path_for "$collision_b")"
[[ -f "$file_a" && -f "$file_b" ]] || fail "sanitized IDs overwrote one another"
jq -e --arg id "$collision_a" '.record.id == $id' "$file_a" >/dev/null || fail "first colliding-prefix ID was overwritten"
jq -e --arg id "$collision_b" '.record.id == $id' "$file_b" >/dev/null || fail "second colliding-prefix ID was overwritten"
pass "deterministic filenames remain distinct when ID sanitization collides"

# The full 255-byte v0 limit remains usable despite filesystem component limits.
max_id="$(printf '%0255d' 0)"
max_output="$("$script" "$max_id" 4 4 2)"
max_file="${max_output#wrote }"
[[ "$max_output" == "wrote "* && -f "$max_file" ]] || fail "255-byte ID did not produce a record"
jq -e --arg id "$max_id" '.record.id == $id' "$max_file" >/dev/null || fail "255-byte ID did not round-trip"
pass "the 255-byte v0 identifier limit fits the local filename safely"

expect_rejection() {
    local label="$1"
    shift
    if "$@" >"$work/stdout" 2>"$work/stderr"; then
        fail "accepted invalid input: $label"
    fi
    [[ ! -s "$work/stdout" ]] || fail "invalid input emitted a success message: $label"
}

expect_rejection "empty ID" "$script" '' 0 0 0
expect_rejection "non-UTF-8 ID" "$script" $'invalid-\377' 0 0 0
expect_rejection "ID over 255 bytes" "$script" "$(printf '%0256d' 0)" 0 0 0
expect_rejection "source-ref over 255 bytes" "$script" valid-id 0 0 0 "$(printf '%0256d' 0)"
expect_rejection "invalid kind code" "$script" bad-kind 5 0 0
expect_rejection "non-numeric kind injection" "$script" injected '0,\"extra\":true' 0 0
expect_rejection "invalid phase code" "$script" bad-phase 0 -1 0
expect_rejection "non-canonical numeric code" "$script" leading-zero 00 0 0
expect_rejection "invalid verification code" "$script" bad-verification 0 0 3
expect_rejection "extra arguments" "$script" too-many 0 0 0 source-ref extra
for invalid_id in bad-kind injected bad-phase leading-zero; do
    [[ ! -e "$(feed_path_for "$invalid_id")" ]] || fail "invalid input left an output file: $invalid_id"
done
pass "empty/overlong strings, invalid enums, JSON injection, and extra arguments fail closed"

printf 'PASS: local provisional serializer safety tests complete\n'
