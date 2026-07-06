#!/usr/bin/env bash
# Enumerate llama.cpp releases via GitHub Releases API, filter to >= boundary,
# write data/raw/releases.json.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${LLAMA_REPO:-ggml-org/llama.cpp}"
BOUNDARY="2026-03-13"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
OUT="data/raw/releases.json"
mkdir -p data/raw

auth=()
[ -n "$TOKEN" ] && auth=(-H "Authorization: Bearer $TOKEN")

page=1; all="[]"
while :; do
  resp=$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases?per_page=100&page=$page")
  count=$(jq 'length' <<<"$resp")
  [ "$count" -eq 0 ] && break
  all=$(jq -s '.[0] + (.[1] | map({tag_name, published_at, assets: [.assets[] | {name, download_count}]}))' \
    <(printf '%s' "$all") <(printf '%s' "$resp"))
  # Stop once a page is entirely below the boundary (releases are newest-first).
  oldest=$(jq -r 'map(.published_at)|min[0:10]' <<<"$resp")
  [ "$oldest" \< "$BOUNDARY" ] && break
  page=$((page+1))
done

jq --arg b "$BOUNDARY" 'map(select(.published_at[0:10] >= $b))' <<<"$all" >"$OUT"
echo "collect: $(jq 'length' "$OUT") releases >= $BOUNDARY → $OUT"
