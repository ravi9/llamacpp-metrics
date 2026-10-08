# Shared jq library: backend classification, OpenVINO parsing, window bucketing.
# Single source of truth for aggregate.sh. Pure functions, no I/O.

def boundary: "2026-03-13";

# Ordered token scan, first match wins.
# Exclusions MUST precede the CPU default so tokenless Ascend/openEuler binaries
# are dropped, not miscounted as CPU.
def classify($name):
  ($name | ascii_downcase) as $n
  | if   ($n | test("cuda"))          then "CUDA"
    elif ($n | test("vulkan"))        then "Vulkan"
    elif ($n | test("rocm|hip"))      then "ROCm/HIP"
    elif ($n | test("sycl"))          then "SYCL"
    elif ($n | test("openvino"))      then "OpenVINO"
    elif ($n | test("opencl-adreno")) then "Adreno"
    elif ($n | test("macos-arm64"))   then "Metal"
    elif ($n | test("opencl|adreno|openeuler|310p|910b|-ui\\.|-xcframework\\.")) then "EXCLUDE"
    else "CPU"
    end;

# OpenVINO asset regex. Returns {build,os,ov} or null on no match.
def parse_ov($name):
  ($name
   | [ scan("^llama-(b[0-9]+)-bin-(ubuntu|win)-openvino-([0-9.]+)-x64\\.(?:tar\\.gz|zip)$") ]
  ) as $m
  | if ($m | length) == 0 then null
    else { build: $m[0][0], os: (if $m[0][1] == "win" then "windows" else "ubuntu" end), ov: $m[0][2] }
    end;

def epoch($iso): ($iso | if test("T") then . else . + "T00:00:00Z" end | fromdateiso8601);

# Per-asset classified records, filtered to >= boundary. Input: releases array.
def to_records:
  [ .[]
    | .published_at as $pub
    | select($pub[0:10] >= boundary)
    | .assets[]
    | { name: .name,
        downloads: (.download_count // 0),
        published_at: $pub,
        backend: classify(.name) }
  ];

# Windows are N calendar days (UTC) ending on the compile date, inclusive: the same spans the
# dashboard labels show, and OV_WINDOW_DAYS in index.html. day = the compile date only.
def window_days: { day: 1, week: 7, week2: 14, month: 30, month2: 60, m3: 90, m6: 180 };

# First date (YYYY-MM-DD) inside an N-day window ending on $last's date.
def window_start($last; $n): (epoch($last[0:10]) - ($n - 1) * 86400) | todate[0:10];

# Window cumulative sum for one backend's records, anchored at compile time $last.
def windows($recs; $last):
  window_days | map_values(window_start($last; .) as $c
    | [ $recs[] | select(.published_at[0:10] >= $c) | .downloads ] | add // 0);
