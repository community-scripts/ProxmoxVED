#!/usr/bin/env bash
set -euo pipefail

API="https://discord.com/api/v10"
NAME_LIMIT=100
CONTENT_LIMIT=1990

RESPONSE=""
HTTP_CODE=""

: "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN is required}"
: "${DISCORD_CHANNEL_ID:?DISCORD_CHANNEL_ID is required}"

request() {
  local method=$1 path=$2 body=${3:-}
  local attempt out wait
  local args=(
    --silent --show-error
    --write-out $'\n%{http_code}'
    --request "$method" "$API$path"
    --header "Authorization: Bot $DISCORD_BOT_TOKEN"
    --header "Content-Type: application/json"
  )
  if [[ -n $body ]]; then
    args+=(--data "$body")
  fi

  for attempt in 1 2 3; do
    if ! out=$(curl "${args[@]}"); then
      HTTP_CODE="000"
      RESPONSE=""
      continue
    fi
    HTTP_CODE=${out##*$'\n'}
    RESPONSE=${out%$'\n'*}

    if [[ $HTTP_CODE == 2* ]]; then
      return 0
    fi
    if [[ $HTTP_CODE != 429 && $HTTP_CODE != 5* ]]; then
      break
    fi
    wait=$(jq -r '.retry_after // empty' <<<"$RESPONSE" 2>/dev/null || true)
    wait=${wait%.*}
    if ! [[ $wait =~ ^[0-9]+$ ]]; then
      wait=2
    fi
    sleep "$wait"
  done

  if [[ ${QUIET:-0} != 1 ]]; then
    echo "::error::Discord $method $path -> HTTP $HTTP_CODE: $RESPONSE" >&2
  fi
  return 1
}

# Probe variant for lookups where a miss is an expected answer, not a failure.
try_request() {
  local QUIET=1
  request "$@"
}

tag_id() {
  local name=$1
  if [[ -z $name ]]; then
    return 0
  fi
  if ! try_request GET "/channels/$DISCORD_CHANNEL_ID"; then
    return 0
  fi
  jq -r --arg n "$name" \
    'first(.available_tags[]? | select((.name | ascii_downcase) == ($n | ascii_downcase)) | .id) // empty' \
    <<<"$RESPONSE"
}

with_tag() {
  local payload=$1 name=$2 id
  id=$(tag_id "$name")
  if [[ -z $id ]]; then
    if [[ -n $name ]]; then
      echo "::notice::Forum tag '$name' not found, leaving tags untouched" >&2
    fi
    printf '%s' "$payload"
    return 0
  fi
  jq --arg id "$id" '.applied_tags = [$id]' <<<"$payload"
}

content_json() {
  local file=$1
  jq -n --rawfile raw "$file" --argjson limit "$CONTENT_LIMIT" \
    '$raw | if (length > $limit) then .[0:$limit] + "\n…" else . end'
}

thread_exists() {
  try_request GET "/channels/$1" >/dev/null
}

find_active() {
  local name=$1
  if [[ -z ${DISCORD_GUILD_ID:-} ]]; then
    return 0
  fi
  if ! try_request GET "/guilds/$DISCORD_GUILD_ID/threads/active"; then
    return 0
  fi
  jq -r --arg n "$name" --arg p "$DISCORD_CHANNEL_ID" \
    'first(.threads[]? | select(.parent_id == $p and .name == $n) | .id) // empty' \
    <<<"$RESPONSE"
}

find_archived() {
  local name=$1 before="" path id page
  for page in 1 2 3 4 5; do
    path="/channels/$DISCORD_CHANNEL_ID/threads/archived/public?limit=100"
    if [[ -n $before ]]; then
      path="$path&before=${before//+/%2B}"
    fi
    if ! try_request GET "$path"; then
      return 0
    fi
    id=$(jq -r --arg n "$name" 'first(.threads[]? | select(.name == $n) | .id) // empty' <<<"$RESPONSE")
    if [[ -n $id ]]; then
      printf '%s' "$id"
      return 0
    fi
    if [[ $(jq -r '.has_more // false' <<<"$RESPONSE") != true ]]; then
      return 0
    fi
    before=$(jq -r '.threads[-1].thread_metadata.archive_timestamp // empty' <<<"$RESPONSE")
    if [[ -z $before ]]; then
      return 0
    fi
  done
}

find_marker() {
  local issue=$1
  gh issue view "$issue" --repo "$GITHUB_REPOSITORY" --json comments \
    --jq '[.comments[].body // "" | scan("discord-thread-id: ([0-9]+)")[]] | last // empty' 2>/dev/null || true
}

# resolve <issue-number> <thread-name>
# The marker comment is authoritative and survives renames and archiving; the
# name lookups only exist for threads created before markers were written.
cmd_resolve() {
  local issue=$1 name=$2 id
  id=$(find_marker "$issue")
  if [[ -n $id ]] && thread_exists "$id"; then
    printf '%s' "$id"
    return 0
  fi
  id=$(find_active "$name")
  if [[ -n $id ]]; then
    printf '%s' "$id"
    return 0
  fi
  find_archived "$name"
}

# create <thread-name> <content-file> [tag-name]
cmd_create() {
  local name=$1 file=$2 tag=${3:-} payload
  payload=$(jq -n --arg name "${name:0:$NAME_LIMIT}" --argjson content "$(content_json "$file")" \
    '{name: $name, message: {content: $content}, applied_tags: []}')
  payload=$(with_tag "$payload" "$tag")
  request POST "/channels/$DISCORD_CHANNEL_ID/threads" "$payload"
  jq -r '.id' <<<"$RESPONSE"
}

# post <thread-id> <content-file>
# A forum post that auto-archived rejects new messages, so unarchive first and
# let the caller re-apply the target state afterwards.
cmd_post() {
  local thread=$1 file=$2 payload
  request PATCH "/channels/$thread" '{"archived": false, "locked": false}' >/dev/null
  payload=$(jq -n --argjson content "$(content_json "$file")" '{content: $content}')
  request POST "/channels/$thread/messages" "$payload" >/dev/null
}

# state <thread-id> <locked:true|false> <archived:true|false> [tag-name]
cmd_state() {
  local thread=$1 locked=$2 archived=$3 tag=${4:-} payload
  payload=$(jq -n --argjson locked "$locked" --argjson archived "$archived" \
    '{locked: $locked, archived: $archived}')
  payload=$(with_tag "$payload" "$tag")
  request PATCH "/channels/$thread" "$payload" >/dev/null
}

# locked <thread-id>
cmd_locked() {
  if try_request GET "/channels/$1"; then
    jq -r '.thread_metadata.locked // false' <<<"$RESPONSE"
  else
    printf 'false'
  fi
}

# delete <thread-id>
cmd_delete() {
  request DELETE "/channels/$1" >/dev/null
}

command=${1:?usage: discord-thread.sh <resolve|create|post|state|locked|delete> ...}
shift
case "$command" in
  resolve) cmd_resolve "$@" ;;
  create) cmd_create "$@" ;;
  post) cmd_post "$@" ;;
  state) cmd_state "$@" ;;
  locked) cmd_locked "$@" ;;
  delete) cmd_delete "$@" ;;
  *) echo "::error::unknown command: $command" >&2; exit 1 ;;
esac
