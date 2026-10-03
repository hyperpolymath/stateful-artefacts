#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
check="$root/scripts/check-no-md-in-docs.sh"
bash "$check" "$work"
mkdir -p "$work/docs/wiki" "$work/docs/wikis" "$work/docs/wikiish" "$work/docs/nested/wiki"
: > "$work/docs/wiki/Page.md"
: > "$work/docs/wikis/README.md"
: > "$work/docs/Guide.adoc"
bash "$check" "$work"
for file in docs/README.md docs/wikiish/Guide.md docs/nested/wiki/Guide.md; do
    : > "$work/$file"
    if bash "$check" "$work" > "$work/result" 2>&1; then
        echo "FAIL: accepted non-wiki Markdown: $file" >&2
        exit 1
    fi
    grep -Fq "$file" "$work/result"
    rm -- "$work/$file"
done
echo 'PASS: wiki exception does not spread to other documentation'
