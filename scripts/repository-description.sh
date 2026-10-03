#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
# D183 / issue #66: the README opening sentence is the approved description.
set -euo pipefail

usage() {
    echo "Usage: $0 --print | --check OWNER/REPO | --apply OWNER/REPO" >&2
    exit 2
}

mode="${1:---print}"
case "$mode" in
    --print) [[ $# -le 1 ]] || usage ;;
    --check|--apply)
        [[ $# -eq 2 && "$2" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage
        ;;
    *) usage ;;
esac

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Explicit AsciiDoc comment boundaries avoid mistaking badges, headings or
# admonitions for prose. Reject malformed/duplicate blocks instead of guessing.
description="$(awk '
    $0 == "// repository-description-begin" { starts++; inside = 1; next }
    $0 == "// repository-description-end" {
        ends++; if (!inside) bad = 1; inside = 0; next
    }
    inside {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        if ($0 == "") { bad = 1; next }
        text = text (text == "" ? "" : " ") $0
    }
    END {
        if (starts != 1 || ends != 1 || inside || bad || text == "") exit 1
        print text
    }
' "$root/README.adoc")" || {
    echo 'ERROR: README.adoc must contain exactly one nonempty repository-description block.' >&2
    exit 1
}
if [[ ${#description} -gt 350 ]] || printf '%s' "$description" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo 'ERROR: repository description must be one plain-text line of at most 350 characters.' >&2
    exit 1
fi

if [[ "$mode" == --print ]]; then
    printf '%s\n' "$description"
    exit 0
fi

repo="$2"
if [[ "$mode" == --apply ]]; then
    # Deliberately opt-in: ordinary CI/PRs never receive Administration write.
    # gh passes the description as data; README content is never shell-evaluated.
    gh repo edit "$repo" --description "$description"
fi
actual="$(gh api "repos/$repo" --jq '.description // ""')"
if [[ "$actual" != "$description" ]]; then
    printf 'ERROR: %s description differs from the approved README sentence.\n' "$repo" >&2
    printf 'Expected: %s\nActual:   %s\n' "$description" "$actual" >&2
    printf 'After review, run: bash scripts/repository-description.sh --apply %s\n' "$repo" >&2
    exit 1
fi
printf 'PASS: %s description matches README.adoc.\n' "$repo"
