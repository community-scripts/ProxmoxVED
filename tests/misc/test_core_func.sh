#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=misc/core.func
source "${REPO_ROOT}/misc/core.func"

FAILURES=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "[PASS] ${msg}"
  else
    echo "[FAIL] ${msg} (expected='${expected}', actual='${actual}')" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_true() {
  local msg="$1"
  shift
  if "$@"; then
    echo "[PASS] ${msg}"
  else
    echo "[FAIL] ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

assert_false() {
  local msg="$1"
  shift
  if "$@"; then
    echo "[FAIL] ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  else
    echo "[PASS] ${msg}"
  fi
}

test_is_unattended_modes() {
  MODE="default"
  assert_true "is_unattended=true for MODE=default" is_unattended

  MODE="mydefaults"
  assert_true "is_unattended=true for MODE=mydefaults" is_unattended

  MODE="appdefaults"
  assert_true "is_unattended=true for MODE=appdefaults" is_unattended

  MODE="advanced"
  # In CI there is no pveversion command, so advanced behaves unattended in-container.
  assert_true "is_unattended=true for MODE=advanced in non-Proxmox context" is_unattended
}

test_prompt_confirm_unattended_defaults() {
  MODE="default"
  assert_true "prompt_confirm returns success for default=y in unattended" prompt_confirm "Proceed?" "y" 1
  assert_false "prompt_confirm returns failure for default=n in unattended" prompt_confirm "Proceed?" "n" 1
}

test_prompt_input_unattended() {
  MODE="default"
  local value
  value="$(prompt_input "Enter value" "fallback" 1)"
  assert_eq "${value}" "fallback" "prompt_input returns default in unattended mode"
}

test_prompt_input_required_tracking() {
  MODE="default"
  unset var_api_token || true
  MISSING_REQUIRED_VALUES=()

  local tmp
  tmp="$(mktemp)"
  prompt_input_required "API token" "CHANGE_ME" 1 "var_api_token" >"${tmp}"
  local value
  value="$(cat "${tmp}")"
  rm -f "${tmp}"

  assert_eq "${value}" "CHANGE_ME" "prompt_input_required uses fallback in unattended mode"
  assert_eq "${#MISSING_REQUIRED_VALUES[@]}" "1" "prompt_input_required tracks missing required values"
  assert_eq "${MISSING_REQUIRED_VALUES[0]}" "var_api_token" "prompt_input_required records correct missing variable"
}

main() {
  test_is_unattended_modes
  test_prompt_confirm_unattended_defaults
  test_prompt_input_unattended
  test_prompt_input_required_tracking

  if [[ "${FAILURES}" -ne 0 ]]; then
    echo "test_core_func.sh: ${FAILURES} failure(s)" >&2
    exit 1
  fi

  echo "test_core_func.sh: all tests passed"
}

main "$@"
