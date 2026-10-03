#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Build and test a native Linux package without publishing anything.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: $0 OUTPUT_DIRECTORY" >&2; exit 2; }
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -sm)" == 'Linux x86_64' ]] || {
    echo 'Only Linux x86_64 release packages are currently supported.' >&2; exit 1;
}
[[ "$(zig version)" == 0.15.2 ]] || { echo 'Zig 0.15.2 is required.' >&2; exit 1; }
version="$(sed -n 's/^const VERSION = "\([^"]*\)";$/\1/p' "$root/src/interface/ffi/src/main.zig")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid library version.' >&2; exit 1; }
if [[ "${GITHUB_REF_TYPE:-}" == tag ]]; then
    tag="${GITHUB_REF_NAME:-}"
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9]+([.-][A-Za-z0-9]+)*)?$ ]] || {
        echo 'Release tag must be vMAJOR.MINOR.PATCH with an optional prerelease.' >&2; exit 1;
    }
    [[ "$tag" == v"$version" || "$tag" == v"$version"-* ]] || {
        echo "Tag $tag does not match library version $version." >&2; exit 1;
    }
    version="${tag#v}"
fi
mkdir -p -- "$1"
out="$(cd -- "$1" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
name="stateful-artefacts-$version-linux-x86_64"
stage="$work/$name"
mkdir -p "$stage/include"
(
    cd "$root/src/interface/ffi"
    zig build -Doptimize=ReleaseSafe --prefix "$stage" --summary all
    zig build test -Doptimize=ReleaseSafe --summary all
)
bash "$root/tests/aspect_tests.sh"
cp "$root/src/interface/generated/abi/stateful_artefacts.h" "$stage/include/"
cp "$root/LICENSE" "$root/README.adoc" "$stage/"
cp -R "$root/LICENSES" "$stage/"
for file in lib/libstateful_artefacts.a lib/libstateful_artefacts.so include/stateful_artefacts.h LICENSE README.adoc; do
    [[ -s "$stage/$file" ]] || { echo "Missing package member: $file" >&2; exit 1; }
done
# Normalize archive metadata; do not claim reproducibility of compiler outputs.
epoch="$(git -C "$root" show -s --format=%ct HEAD)"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner -C "$work" -cf - "$name" |
    gzip -n > "$out/$name.tar.gz"
(
    cd "$out"
    sha256sum "$name.tar.gz" > SHA256SUMS
    sha256sum --check SHA256SUMS
)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        printf 'version=%s\n' "$version"
        printf 'archive=%s.tar.gz\n' "$name"
        printf 'hashes=%s\n' "$(base64 -w0 < "$out/SHA256SUMS")"
    } >> "$GITHUB_OUTPUT"
fi
printf 'Built and verified %s/%s.tar.gz (not published).\n' "$out" "$name"
