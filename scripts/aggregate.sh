#!/usr/bin/env bash
# Aggregate classified records + OpenVINO parse + container scrape into metrics.json.
# All aggregation in jq. Deterministic sorted-key output for idempotency. Reads
# data/raw/releases.json and data/raw/containers.json; writes metrics.json.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${RELEASES:-data/raw/releases.json}"
OUT="${OUT:-metrics.json}"
# Reference instant for rolling windows; overridable for deterministic tests.
LAST_COMPILED="${LAST_COMPILED:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

jq -L scripts -n --sort-keys \
  --arg last "$LAST_COMPILED" \
  --slurpfile rel "$SRC" \
  'include "lib";
  $rel[0]                                  as $releases
  | (epoch($last))                         as $R
  | ($releases | to_records)               as $recs
  | (["CUDA","Vulkan","CPU","ROCm/HIP","SYCL","OpenVINO","Metal","Adreno"]) as $names

  # --- Backend rollups: all six emitted even at zero ---
  | [ $names[] as $bn
      | { name: $bn, windows: windows([ $recs[] | select(.backend == $bn) ]; $R) } ]
                                           as $backends

  # --- OpenVINO parsed records ---
  | [ $releases[]
      | .published_at as $pub
      | select($pub[0:10] >= boundary)
      | .assets[]
      | (parse_ov(.name)) as $p
      | select($p != null)
      | { build: $p.build, os: $p.os, ov_version: $p.ov,
          downloads: (.download_count // 0), published_at: $pub } ]
                                           as $ov

  # View A: group by ov_version
  | [ $ov | group_by(.ov_version)[]
      | { ov_version: .[0].ov_version,
          by_os: ( reduce .[] as $r ({}; .[$r.os] = ((.[$r.os] // 0) + $r.downloads)) ),
          total: ( map(.downloads) | add ) } ]
                                           as $toolkit_versions

  # View B: group by build
  | [ $ov | group_by(.build)[]
      | { build: .[0].build,
          published_at: (.[0].published_at[0:10]),
          ov_version: .[0].ov_version,
          by_os: ( reduce .[] as $r ({}; .[$r.os] = ((.[$r.os] // 0) + $r.downloads)) ),
          total: ( map(.downloads) | add ) } ]
                                           as $builds

  # OpenVINO Trends: builds within last 60 days, grouped by (published_at-date, ov_version).
  # Cumulative lifetime downloads plotted at release date (NOT daily velocity — GitHub
  # exposes only cumulative download_count). linux = ubuntu assets, windows = windows assets.
  | ( $ov | map(select(($R - epoch(.published_at)) <= 5184000)) ) as $ov60
  | [ $ov60
      | group_by(.published_at[0:10] + "|" + .ov_version)[]
      | { date: (.[0].published_at[0:10]),
          ov_version: .[0].ov_version,
          linux:   ( map(select(.os == "ubuntu")  | .downloads) | add // 0 ),
          windows: ( map(select(.os == "windows") | .downloads) | add // 0 ),
          total:   ( map(.downloads) | add // 0 ) } ]
                                           as $trend

  # --- Headline summary, 6-month window ---
  | ( [ $backends[] | .windows.m6 ] | add // 0 ) as $tot6
  | ( $backends | max_by(.windows.m6) )           as $lead
  | ( $backends[] | select(.name == "OpenVINO") | .windows.m6 ) as $ov6

  | { schema_version: "1",
      last_compiled: $last,
      boundary_date: boundary,
      summary: {
        total_downloads: $tot6,
        leading_backend: $lead.name,
        leading_backend_share: (if $tot6 > 0 then (($lead.windows.m6 / $tot6) * 1000 | floor) / 10 else 0 end),
        openvino_downloads: $ov6
      },
      backends: $backends,
      openvino: {
        toolkit_versions: $toolkit_versions,
        builds: $builds,
        trend: $trend
      } }' >"$OUT"

echo "aggregate: $(jq '.backends|length' "$OUT") backends, $(jq '.openvino.builds|length' "$OUT") ov builds → $OUT"
