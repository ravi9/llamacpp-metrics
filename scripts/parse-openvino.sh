#!/usr/bin/env bash
# Parse OpenVINO assets via the asset regex; emit (build, os, ov_version,
# downloads, published_at) records to stdout. Non-matching / missing-Windows
# assets silently skipped. Reads data/raw/releases.json (or $1).
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-data/raw/releases.json}"

jq -L scripts 'include "lib";
  [ .[]
    | .published_at as $pub
    | select($pub[0:10] >= boundary)
    | .assets[]
    | (parse_ov(.name)) as $p
    | select($p != null)
    | { build: $p.build, os: $p.os, ov_version: $p.ov,
        downloads: (.download_count // 0), published_at: $pub }
  ]' "$SRC"
