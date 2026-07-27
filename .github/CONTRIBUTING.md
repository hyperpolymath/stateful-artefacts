<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Contributing to Stateful Artefacts

Stateful Artefacts is the state-carrying artefact layer of the
Reposystem/OPSM stack: one canonical, machine-readable *state record*
(identity, provenance, lifecycle phase, verification status), plus the
tooling to read, write, and validate those records via a formally-typed C
ABI (Idris2-proven layout, Zig implementation). See [README.adoc](../README.adoc)
for the full pitch and [EXPLAINME.adoc](../EXPLAINME.adoc) for the
engineering deep-dive.

## Getting Started

```bash
# Clone the repository
git clone https://github.com/hyperpolymath/stateful-artefacts.git
cd stateful-artefacts

# Using Guix (preferred, reproducible)
guix shell -D -f build/guix.scm

# Or using Nix (fallback)
nix develop

# Or install the pinned toolchain manually (see .tool-versions):
# Zig 0.15.2+, just 1.40.0+, Idris2 (optional, ABI typecheck only)

# Verify setup
just doctor   # self-diagnostic: checks required tools
just build    # build the FFI seam
just test     # run the Zig unit + integration tests
```

### Repository Structure

```
stateful-artefacts/
├── 0-AI-MANIFEST.a2ml        # Universal entry point for AI agents
├── src/core/                 # Domain core — the v0 artefact-state-record (record.zig)
├── src/definitions/          # Machine-readable schemas (artefact-state-record.a2ml)
├── src/bridges/              # Estate adapters (verisimdb-feed.sh)
├── src/interface/Abi/        # Idris2 ABI definitions and layout proofs
├── src/interface/ffi/        # Zig FFI bridge — the C ABI implementation
├── src/interface/generated/  # Generated C header (stateful_artefacts.h)
├── verification/proofs/      # Idris2/TLA+ lifecycle proofs (+ Agda/Coq/Lean4 scaffolding)
├── docs/                     # Spec, onboarding, status, governance, decisions
├── tests/, benches/          # Test suites and benchmarks
├── .machine_readable/        # Project metadata, policies, contractiles, AI configs
├── .github/                  # GitHub config
│   └── workflows/
├── CHANGELOG.md
├── LICENSE                   # MPL-2.0 (code)
├── LICENSES/                 # MPL-2.0.txt, CC-BY-SA-4.0.txt (docs)
├── README.adoc
├── .github/SECURITY.md
├── flake.nix                 # Nix flake — fallback
├── build/guix.scm            # Guix package — primary
└── Justfile                  # Task runner (`just` lists all recipes)
```

---

## How to Contribute

### Reporting Bugs

**Before reporting**:
1. Search existing issues
2. Check if it's already fixed on `main`

**When reporting**, please include:

- Clear, descriptive title
- Environment details (OS, Zig version, toolchain)
- Steps to reproduce
- Expected vs actual behaviour
- Relevant logs or `zig build test` output

There is currently no `.github/ISSUE_TEMPLATE/` directory, so just
[open a new issue](https://github.com/hyperpolymath/stateful-artefacts/issues/new)
with that information.

### Suggesting Features

Given the current [re-transfer status](../README.adoc#re-transfer-status) —
the reposystem domain content is still being re-extracted — please open an
issue describing the problem and proposed solution before starting
substantial work, so it can be reconciled against the v0 artefact-state-record
and the re-transfer plan in
[docs/RE-TRANSFER-RUNBOOK.adoc](../docs/RE-TRANSFER-RUNBOOK.adoc).

### Your First Contribution

Look for issues labelled:

- [`good first issue`](https://github.com/hyperpolymath/stateful-artefacts/labels/good%20first%20issue)
- [`help wanted`](https://github.com/hyperpolymath/stateful-artefacts/labels/help%20wanted)
- [`documentation`](https://github.com/hyperpolymath/stateful-artefacts/labels/documentation)

---

## Development Workflow

### Branch Naming
```
docs/short-description       # Documentation
test/what-added              # Test additions
feat/short-description       # New features
fix/issue-number-description # Bug fixes
refactor/what-changed        # Code improvements
security/what-fixed          # Security fixes
```

### Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):
```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

### Before Submitting a PR

```bash
just quality   # fmt-check + test
just fmt       # if quality found formatting issues
just aspect    # SPDX headers, dangerous-pattern scan, ABI/Zig symbol parity
just assail    # panic-attacker pre-commit scan
```

Then fill in the [PR template](pull_request_template.md) checklist — all
"Required" items must be checked before a PR can merge.

### Invariants that must never be violated

Read `.machine_readable/contractiles/` before making structural changes. In
particular:

- Every exported C symbol is prefixed `stateful_artefacts_` and declared on
  both the Zig side (`src/interface/ffi/`) and the Idris2 side
  (`src/interface/Abi/`).
- The Idris2 ABI layer stays `%default total` — no `believe_me` /
  `assert_total`.
- No TypeScript, npm, or bun anywhere in the repo (CI-enforced).
- Artefact state records remain backward-readable: schema changes are
  additive only.

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you agree to abide by its terms.

## License

By contributing, you agree that your contributions will be licensed under
the same terms as the project: MPL-2.0 for code, CC-BY-SA-4.0 for
documentation. See [LICENSE](../LICENSE).
