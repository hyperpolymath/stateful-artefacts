#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/scripts" "$scratch/bin"
cp "$root/scripts/repository-description.sh" "$scratch/scripts/"
script="$scratch/scripts/repository-description.sh"
export PATH="$scratch/bin:$PATH" GH_CALLS="$scratch/calls" GH_DESCRIPTION_FILE="$scratch/description"
cat > "$scratch/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
[[ "${GH_FAIL:-false}" != true ]] || exit 7
case "$1 $2" in
    'repo edit')
        [[ "$3" == owner/repo && "$4" == --description && $# -eq 5 ]]
        printf '%s\n' "$5" > "$GH_DESCRIPTION_FILE"
        ;;
    'api repos/owner/repo') cat "$GH_DESCRIPTION_FILE" ;;
    *) exit 8 ;;
esac
MOCK
chmod +x "$scratch/bin/gh"
count=0
pass() { count=$((count + 1)); printf 'PASS: %s\n' "$1"; }
reject() {
    if bash "$script" "$@" > "$scratch/out" 2>&1; then
        echo "FAIL: unexpectedly accepted $*" >&2; exit 1
    fi
}
fixture() {
    cat > "$scratch/README.adoc" <<'README'
// Licence and metadata are not descriptions.
= Project
:toc:
image:https://example.org/badge.svg[badge]
// repository-description-begin
The approved sentence, with identity,
provenance and verification.
// repository-description-end
== Details
Not part of the description.
README
}
fixture
expected='The approved sentence, with identity, provenance and verification.'
[[ "$(cd / && bash "$script" --print)" == "$expected" ]]
[[ ! -e "$GH_CALLS" ]]
pass 'wrapped prose extracted independently of cwd; print is offline'
printf '%s\n' "$expected" > "$GH_DESCRIPTION_FILE"
bash "$script" --check owner/repo
[[ "$(wc -l < "$GH_CALLS")" -eq 1 ]]
pass 'matching metadata succeeds without mutation'
for actual in '' 'Stale description'; do
    printf '%s\n' "$actual" > "$GH_DESCRIPTION_FILE"
    reject --check owner/repo
 done
pass 'empty and stale metadata fail'
GH_FAIL=true reject --check owner/repo
GH_FAIL=true reject --apply owner/repo
pass 'API read and write failures propagate'
bash "$script" --apply owner/repo
[[ "$(cat "$GH_DESCRIPTION_FILE")" == "$expected" ]]
[[ "$(tail -1 "$GH_CALLS")" == 'api repos/owner/repo --jq .description // ""' ]]
pass 'explicit apply writes exact text and reads back'
reject --apply
reject --check /repo
reject --apply owner/repo extra
reject --unknown
pass 'invalid invocation rejected'
for case_name in missing duplicate reversed empty blank unclosed; do
    fixture
    case "$case_name" in
        missing) sed -i '/repository-description-/d' "$scratch/README.adoc" ;;
        duplicate) cat "$scratch/README.adoc" > "$scratch/copy"; cat "$scratch/copy" >> "$scratch/README.adoc" ;;
        reversed) printf '// repository-description-end\n// repository-description-begin\ntext\n' > "$scratch/README.adoc" ;;
        empty) sed -i '/^The approved/d; /^provenance/d' "$scratch/README.adoc" ;;
        blank) sed -i '/^provenance/i\ ' "$scratch/README.adoc" ;;
        unclosed) sed -i '/repository-description-end/d' "$scratch/README.adoc" ;;
        *) echo "Unknown fixture: $case_name" >&2; exit 1 ;;
    esac
    reject --print
    pass "malformed block rejected: $case_name"
done
fixture
sed -i "s/^The approved.*/$(printf '%0351d' 0)/" "$scratch/README.adoc"
reject --print
pass 'overlong description rejected'
fixture
sed -i 's/^The approved.*/Text\twith control character/' "$scratch/README.adoc"
reject --print
pass 'control characters rejected'
fixture
# Deliberately test literal shell syntax.
# shellcheck disable=SC2016
sed -i 's/^The approved.*/Literal $(touch SHOULD_NOT_EXIST) `uname` "quoted";/' "$scratch/README.adoc"
(cd "$scratch" && bash "$script" --apply owner/repo)
[[ ! -e "$scratch/SHOULD_NOT_EXIST" ]]
# Assert the unevaluated literal.
# shellcheck disable=SC2016
grep -Fq '$(touch SHOULD_NOT_EXIST) `uname` "quoted";' "$GH_DESCRIPTION_FILE"
pass 'shell metacharacters remain data'
# The real source remains valid as well.
bash "$root/scripts/repository-description.sh" --print > /dev/null
pass 'repository README contract'
printf '%s tests passed.\n' "$count"
