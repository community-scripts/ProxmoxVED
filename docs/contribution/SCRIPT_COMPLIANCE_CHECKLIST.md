# Shell Script Compliance Checklist

Use this checklist before opening a PR with changes in `ct/`, `install/`, `vm/`, `tools/`, or `misc/` shell/function files.

## Required (must pass)

- [ ] Bash syntax passes for changed files (`bash -n`)
- [ ] ShellCheck passes for changed files
- [ ] No insecure password usage (`sshpass -p`)
- [ ] No unsafe curl/wget pipe-to-shell patterns
- [ ] No broken `source`/`.` references in changed scripts
- [ ] No `chmod 777` in changed scripts

## Script quality

- [ ] Shebang present (`#!/usr/bin/env bash` or `#!/bin/bash`)
- [ ] Variables are quoted unless intentional word splitting is required
- [ ] Error paths use meaningful messages (`msg_error`, `msg_warn`, etc.)
- [ ] New logic reuses existing helper functions from `misc/*.func` where practical
- [ ] No unnecessary duplication of existing helper logic

## Behavior and safety

- [ ] Destructive operations require explicit confirmation/flag
- [ ] Script works in non-interactive execution flow where expected
- [ ] Update paths preserve user data/config where applicable

## Testing

- [ ] `tests/misc/run_core_func_tests.sh` passes locally
- [ ] New/changed shared helper behavior has at least one targeted test when feasible

## Documentation

- [ ] Contribution docs updated when contribution workflow or requirements changed
- [ ] App-specific docs updated when user-visible behavior changed
