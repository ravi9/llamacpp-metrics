#!/usr/bin/env bash
# Classify every asset by ordered token scan; emit (backend, downloads,
# published_at, build|null) per asset to stdout. Exclusions precede CPU default.
# Reads data/raw/releases.json (or $1).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-data/raw/releases.json}"

jq -L scripts 'include "lib";
  to_records
  | map(. + { build: ( .name | [scan("(?:^|-)(b[0-9]+)-bin-")] | .[0][0] // null ) })
  | map({ backend, downloads, published_at, build })' "$SRC"
