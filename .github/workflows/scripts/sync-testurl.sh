#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# sync-testurl.sh — put var_testurl into the ct/ script an issue belongs to
#
# A script under test asks its users for feedback, and var_testurl is where that
# feedback goes. Setting it by hand means remembering to, for every script, so
# this derives it from the issue instead.
#
# Usage:
#   sync-testurl.sh <issue-number> <issue-title>   one issue
#   sync-testurl.sh --all                          every open Ready For Testing
#
# Matching is on APP= in the script against the issue title, compared with
# everything but letters and digits removed -- the two disagree often enough
# ("Rocky Linux" vs "RockyLinux", "llama-cpp" vs "llama.cpp") that an exact
# comparison misses real pairs. A title that matches no script, or more than
# one, is skipped and reported rather than guessed at.
#
# Writes nothing when the variable is already there, so it is safe to re-run.
# ------------------------------------------------------------------------------
set -euo pipefail

REPO="${REPO:-community-scripts/ProxmoxVED}"
ISSUE_BASE="https://github.com/${REPO}/issues"

norm() { printf '%s' "${1,,}" | tr -cd 'a-z0-9'; }

# app_key -> path, built once. Only ct/ scripts: an addon or VM script creates
# no container, so it has neither a MOTD nor a description to carry the request.
declare -A SCRIPT_BY_KEY=()
declare -A SCRIPT_DUPES=()
build_index() {
  local f app key
  while IFS= read -r f; do
    app=$(sed -n 's/^APP="\([^"]*\)".*/\1/p' "$f" | head -1)
    [[ -z "$app" ]] && continue
    key=$(norm "$app")
    [[ -z "$key" ]] && continue
    if [[ -n "${SCRIPT_BY_KEY[$key]:-}" ]]; then
      SCRIPT_DUPES[$key]="${SCRIPT_BY_KEY[$key]} $f"
    else
      SCRIPT_BY_KEY[$key]="$f"
    fi
  done < <(find ct -name '*.sh' -type f | sort)
}

# Insert after the last var_* declaration so it stays in that block, commented
# lines included -- var_arm64 is conventionally left commented out and would
# otherwise end up below the new line.
insert_line() {
  local file="$1" line="$2" last
  last=$(grep -n '^[[:space:]]*#\?[[:space:]]*var_[a-z0-9_]*=' "$file" | tail -1 | cut -d: -f1)
  if [[ -z "$last" ]]; then
    echo "    no var_* block found, skipping"
    return 1
  fi
  awk -v n="$last" -v ins="$line" 'NR==n{print; print ins; next} {print}' "$file" >"${file}.tmp" &&
    mv "${file}.tmp" "$file"
}

apply_one() {
  local number="$1" title="$2" key file
  key=$(norm "$title")

  if [[ -n "${SCRIPT_DUPES[$key]:-}" ]]; then
    echo "  #${number} ${title}: matches more than one script (${SCRIPT_DUPES[$key]}), skipped"
    return 0
  fi
  file="${SCRIPT_BY_KEY[$key]:-}"
  if [[ -z "$file" ]]; then
    echo "  #${number} ${title}: no ct/ script with a matching APP=, skipped"
    return 0
  fi
  if grep -q '^[[:space:]]*var_testurl=' "$file"; then
    echo "  #${number} ${title}: ${file} already has var_testurl, left alone"
    return 0
  fi

  insert_line "$file" "var_testurl=\"\${var_testurl:-${ISSUE_BASE}/${number}}\"" || return 0
  echo "  #${number} ${title}: added to ${file}"
  CHANGED=$((CHANGED + 1))
}

CHANGED=0
build_index

if [[ "${1:-}" == "--all" ]]; then
  echo "Indexed ${#SCRIPT_BY_KEY[@]} ct/ scripts"
  while IFS=$'\t' read -r number title; do
    [[ -z "$number" ]] && continue
    apply_one "$number" "$title"
  done < <(gh issue list -R "$REPO" --state open --label "Ready For Testing" \
    --limit 500 --json number,title --jq '.[] | [.number, .title] | @tsv')
else
  apply_one "${1:?issue number}" "${2:?issue title}"
fi

echo "changed=${CHANGED}" >>"${GITHUB_OUTPUT:-/dev/stdout}"
