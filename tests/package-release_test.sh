#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Hermetic contract tests; real Zig packaging is a separate CI step.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
fixture="$work/repo"
mkdir -p "$fixture/LICENSES" "$work/bin" "$fixture/scripts" "$fixture/tests" "$fixture/src/interface/ffi/src" "$fixture/src/interface/generated/abi"
cp "$root/scripts/package-release.sh" "$fixture/scripts/"
printf 'const VERSION = "1.2.3";\n' > "$fixture/src/interface/ffi/src/main.zig"
printf 'test header\n' > "$fixture/src/interface/generated/abi/stateful_artefacts.h"
printf 'test licence\n' > "$fixture/LICENSE"
printf 'test documentation licence\n' > "$fixture/LICENSES/CC-BY-SA-4.0.txt"
printf 'test readme\n' > "$fixture/README.adoc"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture/tests/aspect_tests.sh"
cat > "$work/bin/zig" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == version ]]; then
    if [[ "${MODE:-}" == wrong-version ]]; then echo 0.14.0; else echo 0.15.2; fi
    exit 0
fi
[[ "${MODE:-}" != build-failure ]] || exit 42
if [[ "${2:-}" == test ]]; then
    [[ "${MODE:-}" != test-failure ]]
    exit
fi
while [[ $# -gt 0 ]]; do
    if [[ "$1" == --prefix ]]; then
        [[ "${MODE:-}" != missing-libraries ]] || exit 0
        mkdir -p "$2/lib"
        printf 'test static library\n' > "$2/lib/libstateful_artefacts.a"
        printf 'test shared library\n' > "$2/lib/libstateful_artefacts.so"
        exit 0
    fi
    shift
done
exit 2
MOCK
cat > "$work/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 6 && "$1" == -C && "$3" == show && "$5" == --format=%ct ]] || exit 2
printf '1700000000\n'
MOCK
cat > "$work/bin/uname" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${PLATFORM:-Linux x86_64}"
MOCK
chmod +x "$work/bin/"*
export PATH="$work/bin:$PATH" GITHUB_REF_TYPE=branch GITHUB_REF_NAME=test
export GITHUB_OUTPUT="$work/outputs"
package="$fixture/scripts/package-release.sh"
expect_failure() {
    if "$@" > "$work/log" 2>&1; then
        echo "FAIL: accepted invalid invocation: $*" >&2
        exit 1
    fi
}
expect_failure bash "$package"
expect_failure bash "$package" "$work/out" extra
expect_failure env MODE=wrong-version bash "$package" "$work/out"
expect_failure env PLATFORM='Darwin arm64' bash "$package" "$work/out"
expect_failure env GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v9.9.9 bash "$package" "$work/out"
expect_failure env GITHUB_REF_TYPE=tag GITHUB_REF_NAME='v1.2.3/unsafe' bash "$package" "$work/out"
expect_failure env MODE=build-failure bash "$package" "$work/out"
expect_failure env MODE=test-failure bash "$package" "$work/out"
expect_failure env MODE=missing-libraries bash "$package" "$work/out"
[[ ! -e "$work/out/SHA256SUMS" ]] || { echo 'FAIL: failed build published checksums'; exit 1; }
bash "$package" "$work/out"
(cd "$work/out" && sha256sum --check SHA256SUMS)
tar -tzf "$work/out/stateful-artefacts-1.2.3-linux-x86_64.tar.gz" > "$work/members"
for member in lib/libstateful_artefacts.a lib/libstateful_artefacts.so include/stateful_artefacts.h LICENSE README.adoc LICENSES/CC-BY-SA-4.0.txt; do
    grep -Fxq "stateful-artefacts-1.2.3-linux-x86_64/$member" "$work/members"
done
sed -n 's/^hashes=//p' "$work/outputs" | base64 -d > "$work/decoded"
cmp "$work/decoded" "$work/out/SHA256SUMS"
: > "$work/outputs"
GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.2.3-rc.1 bash "$package" "$work/prerelease"
grep -Fxq 'version=1.2.3-rc.1' "$work/outputs"
echo 'PASS: 9 fail-closed cases, archive contents, integrity, provenance subjects and prerelease version'
