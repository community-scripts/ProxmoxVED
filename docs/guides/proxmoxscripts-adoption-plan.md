# ProxmoxScripts-Inspired Adoption Plan for ProxmoxVED

This guide captures practical improvements we can adopt from `coelacant1/ProxmoxScripts` **without changing ProxmoxVED's core mission** (app-focused CT/VM provisioning).

## Scope and Intent

- Keep ProxmoxVED focused on CT/install/vm automation.
- Adopt high-value engineering practices (QA, security, consistency).
- Avoid copying external scripts/features that target different use-cases (cluster day-2 ops).

## Why This Matters

ProxmoxVED already has a large script surface and excellent docs. The main leverage now is:

1. Better automated safety nets
2. Stronger security defaults
3. More uniform script quality across `ct/`, `install/`, `vm/`, `tools/`

## Priority Roadmap

## Phase 1 — Quick Wins (1-2 weeks)

### 1) Baseline script checks in CI

Implement lightweight checks first:

- `bash -n` syntax checks for all `*.sh`
- `shellcheck` for touched scripts (or all scripts if runtime is acceptable)
- basic executable-bit consistency for shell scripts

Success criteria:

- PRs fail on syntax errors and major shellcheck issues
- No silent breakages from malformed scripts

### 2) Source/include dependency verification

Add a small checker to detect common problems:

- utility functions used without required includes
- stale includes that are never used

Success criteria:

- Missing include errors are caught before merge
- Utility usage becomes more consistent

### 3) Security lint pass (targeted)

Introduce grep-based policy checks for risky patterns:

- discourage unsafe `eval` usage
- detect secret leakage patterns in command args/logging

Success criteria:

- New high-risk patterns blocked in CI
- Existing violations tracked with remediation issues

---

## Phase 2 — Standardization (2-4 weeks)

### 4) Script compliance checklist for ProxmoxVED

Create a concise checklist tailored to this repo:

- required header fields
- argument parsing expectations
- error handling expectations
- non-interactive behavior expectations

Recommended location:

- `docs/contribution/SCRIPT_COMPLIANCE_CHECKLIST.md`

### 5) Definition-of-done for shell scripts

Document mandatory pre-merge validations:

- syntax + shellcheck pass
- local functional smoke test
- docs updates when behavior changes

Recommended location:

- `docs/contribution/README.md`

---

## Phase 3 — Reliability Expansion (4-8 weeks)

### 6) Focused tests for core function libraries

Start with highest-impact libs under `misc/`:

- parsing/config helpers
- networking helpers
- release/deploy helper functions

Goal:

- prevent regressions in shared building blocks used by many scripts

### 7) Changelog quality and security callouts

Encourage explicit sections in release notes:

- Security
- Fixed
- Changed
- Added

This improves operator confidence and auditability.

---

## What Not to Adopt 1:1

Do **not** prioritize direct expansion into external repo domains unless requested by community roadmap:

- large cluster day-2 operations suites
- infra-heavy firewall/HA management catalogs
- third-party remote desktop integration automation

These are valuable, but orthogonal to current ProxmoxVED strengths.

## Implementation Backlog (Actionable)

- [ ] Create CI workflow for syntax + shellcheck baseline
- [ ] Add include/dependency checker under `tools/` or `.github/workflows/scripts/`
- [ ] Add security policy checks for risky shell patterns
- [ ] Publish `SCRIPT_COMPLIANCE_CHECKLIST.md`
- [ ] Update contribution docs with shell-script DoD
- [ ] Add first test pack for one high-impact `misc/` function library

## Ownership Suggestion

- CI + checks: maintainers familiar with `.github/workflows/`
- checklist + docs: contributor-guides maintainers
- tests: function-library maintainers (`misc/*`)

## Review Cadence

- Weekly progress check until Phase 1 complete
- Biweekly thereafter
- Re-prioritize based on PR failure data and recurring bug classes
