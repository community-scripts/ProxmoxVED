#!/bin/bash

INPUT_FILE=".github/workflows/scripts/repos.txt"
OUTPUT_FILE="frontend/public/json/versions.json"
TMP_FILE="releases_tmp.json"

if [ -f "$OUTPUT_FILE" ]; then
  cp "$OUTPUT_FILE" "$TMP_FILE"
else
  echo "[]" > "$TMP_FILE"
fi

while IFS= read -r repo; do
  echo "Checking $repo..."

  response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/${repo}/releases/latest")
  tag=$(echo "$response" | jq -r .tag_name)
  date=$(echo "$response" | jq -r .published_at)

  if [[ "$tag" == "null" || "$date" == "null" ]]; then
    echo "No release found for $repo"
    continue
  fi

  existing_version=$(jq -r --arg name "$repo" '.[] | select(.name == $name) | .version' "$TMP_FILE")

  if [[ "$existing_version" != "$tag" ]]; then
    echo "New release for $repo: $tag"
    jq --arg name "$repo" 'del(.[] | select(.name == $name))' "$TMP_FILE" > "$TMP_FILE.tmp" && mv "$TMP_FILE.tmp" "$TMP_FILE"

    jq --arg name "$repo" --arg version "$tag" --arg date "$date" \
      '. += [{"name": $name, "version": $version, "date": $date}]' "$TMP_FILE" > "$TMP_FILE.tmp" && mv "$TMP_FILE.tmp" "$TMP_FILE"
  else
    echo "No change for $repo"
  fi

done < "$INPUT_FILE"

#mv "$TMP_FILE" "$OUTPUT_FILE"
