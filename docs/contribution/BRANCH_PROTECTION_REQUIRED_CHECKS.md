# Branch Protection: Required Checks Setup

This page is for maintainers who manage repository settings.

## Goal

Require the shell quality gate to pass before merging pull requests.

## Workflow/Check Names

- Workflow file: `.github/workflows/shell-quality.yml`
- Required status check (job): `shell-gates`

## GitHub Settings Steps

1. Open repository **Settings** → **Branches**
2. Edit the branch protection rule for `main` (or create one)
3. Enable **Require status checks to pass before merging**
4. Add required check:
   - `shell-gates`
5. (Recommended) Enable:
   - **Require branches to be up to date before merging**
   - **Require conversation resolution before merging**
   - **Do not allow bypassing the above settings** (for non-admin merge paths)

## Why this works reliably

`shell-quality.yml` now runs on **every pull request** (not only shell file changes), so `shell-gates` is always reported and can be safely required.
