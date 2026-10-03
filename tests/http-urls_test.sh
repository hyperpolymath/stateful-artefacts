#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/source with spaces"
source_dir="$work/source with spaces"
check="$root/scripts/check-http-urls.sh"
for mode in --source --mixed-content; do
    if [[ "$mode" == --source ]]; then file="$source_dir/code.ts"; else file="$source_dir/index.html"; fi
    for url in https://external.invalid/a http://localhost:8000/a http://127.0.0.1/a 'http://[::1]:8000/a' http://example.com/docs; do
        printf '<a href="%s">link</a>\n' "$url" > "$file"
        bash "$check" "$mode" "$source_dir"
    done
    for url in http://external.invalid/a http://localhost.evil/a http://example.com.evil/a http://localhost@external.invalid/a http://external.invalid/example http://external.invalid/path/http://localhost 'HTTP://EXTERNAL.INVALID/image'; do
        # Mixed safe/unsafe URLs on the same line must still fail. Single quotes
        # and uppercase HTML attributes/schemes must not hide mixed content.
        printf '<a href="http://localhost/a">safe</a><IMG SRC=\047%s\047>\n' "$url" > "$file"
        if bash "$check" "$mode" "$source_dir" > "$work/log"; then echo "FAIL: accepted $url"; exit 1; fi
        grep -Fq "$file:1:" "$work/log"
    done
    rm -- "$file"
done
mkdir -p "$source_dir/.git" "$source_dir/node_modules"
# Fixture URLs are data, not printf format strings or network commands.
unsafe_fixture='http://external.invalid/'
printf '%s\n' "$unsafe_fixture" > "$source_dir/.git/internal.ts"
printf '%s\n' "$unsafe_fixture" > "$source_dir/node_modules/vendor.ts"
bash "$check" --source "$source_dir"
if bash "$check" --unknown "$source_dir"; then echo 'FAIL: accepted unknown mode'; exit 1; fi
echo 'PASS: 24 URL cases, generated/VCS exclusions and invalid invocation'
