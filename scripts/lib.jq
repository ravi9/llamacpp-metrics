# Shared jq library: backend classification, OpenVINO parsing, window bucketing.
# Single source of truth — used by classify-backend.sh, parse-openvino.sh and
# aggregate.sh. Pure functions, no I/O.

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

# Window cumulative sum for one backend's records relative to reference epoch $R.
def windows($recs; $R):
  { day: 86400, week: 604800, week2: 1209600, month: 2592000, month2: 5184000, m3: 7776000, m6: 15552000 } as $w
  | $w | map_values(. as $sec | [ $recs[] | select(($R - epoch(.published_at)) <= $sec) | .downloads ] | add // 0);
