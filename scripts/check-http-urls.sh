#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Inspect URL literals as data; never make requests to discovered URLs.
# Exit 1 for an insecure external URL, 2 for invalid invocation.
set -euo pipefail
[[ $# -eq 2 ]] || { echo "Usage: $0 --source|--mixed-content ROOT" >&2; exit 2; }
mode="$1"
case "$mode" in --source|--mixed-content) ;; *) exit 2 ;; esac
root="$(cd -- "$2" && pwd)"
files="$(mktemp)"
trap 'rm -f -- "$files"' EXIT
if [[ "$mode" == --mixed-content ]]; then
    patterns=(-iname '*.html' -o -iname '*.htm')
else
    patterns=(-name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' -o -name '*.yaml' -o -name '*.yml')
fi
# Keep generated dependencies and VCS internals out of source-policy scans.
find "$root" -type d \( -name .git -o -name node_modules -o -name .zig-cache -o -name zig-out -o -name .cache \) -prune -o \
    -type f \( "${patterns[@]}" \) -print0 > "$files"
failed=0
while IFS= read -r -d '' file; do
    if ! LC_ALL=C awk -v mode="$mode" '
        {
            rest = $0
            while (1) {
                lower = tolower(rest)
                if (mode == "--mixed-content") {
                    found = match(lower, /(src|href)[[:space:]]*=[[:space:]]*[\042\047]http:\/\/[^[:space:]\042\047<>]+/)
                } else {
                    found = match(lower, /http:\/\/[^[:space:]\042\047<>]+/)
                }
                if (!found) break
                value = substr(lower, RSTART, RLENGTH)
                rest = substr(rest, RSTART + RLENGTH)
                sub(/^(src|href)[[:space:]]*=[[:space:]]*[\042\047]/, "", value)
                sub(/^http:\/\//, "", value)
                sub(/[\/?#].*$/, "", value)
                sub(/:[0-9]+$/, "", value)
                # Exact authorities only: localhost.evil and example.com.evil
                # are not exemptions; one safe URL never excuses another.
                if (value == "localhost" || value == "127.0.0.1" || value == "[::1]" || value == "example.com") continue
                printf "%s:%d: insecure external HTTP URL\n", FILENAME, FNR
                failed = 1
            }
        }
        END { exit failed }
    ' "$file"; then
        failed=1
    fi
done < "$files"
exit "$failed"
