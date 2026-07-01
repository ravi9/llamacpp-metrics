#!/usr/bin/env bash
# Run aggregate over the fixture, assert classification + windowing + invariants.
# Deterministic via fixed LAST_COMPILED.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
M="$TMP/metrics.json"

# Reference instant just after the b9835 release so all post-boundary assets land in m6.
RELEASES=test/fixtures/sample-release.json \
CONTAINERS=/dev/null \
OUT="$M" \
LAST_COMPILED="2026-06-29T00:00:00Z" \
  scripts/aggregate.sh >/dev/null

pass=0; fail=0
check() { # desc, jq-filter
  if jq -e "$2" "$M" >/dev/null; then pass=$((pass+1)); echo "ok: $1";
  else fail=$((fail+1)); echo "FAIL: $1"; fi
}

check "8 backends present"                 '.backends | length == 8'
check "boundary date"                      '.boundary_date == "2026-03-13"'

# Classification (m6 totals). CUDA = 5000+6000+300(cudart)+2000 = 13300
check "CUDA = 12.4+13.3+cudart"            '(.backends[]|select(.name=="CUDA").windows.m6) == 13300'
# ROCm/HIP = rocm-7.2(400)+hip-radeon(150)+rocm-7.2 win(90) = 640
check "ROCm/HIP = rocm + hip-radeon"      '(.backends[]|select(.name=="ROCm/HIP").windows.m6) == 640'
# SYCL = fp16(250)+fp32(250)+ubuntu fp16(180) = 680
check "SYCL = fp16 + fp32"                '(.backends[]|select(.name=="SYCL").windows.m6) == 680'
# Vulkan = 700+100+600+100 = 1500
check "Vulkan x64 + arm64"                '(.backends[]|select(.name=="Vulkan").windows.m6) == 1500'
# CPU = ubuntu(1000)+win(800) b9835 + b9700 ubuntu(300) = 2100 (macos-arm64 now Metal)
check "CPU tokenless binaries"            '(.backends[]|select(.name=="CPU").windows.m6) == 2100'
# Metal = macos-arm64 b9835 (200)
check "Metal = macos-arm64"               '(.backends[]|select(.name=="Metal").windows.m6) == 200'
# Adreno = opencl-adreno b9835 (30) — promoted from excluded, before opencl exclude
check "Adreno = opencl-adreno"            '(.backends[]|select(.name=="Adreno").windows.m6) == 30'
# OpenVINO = 100+50 (b9835) + 70 (b9700) = 220
check "OpenVINO total"                     '(.backends[]|select(.name=="OpenVINO").windows.m6) == 220'

# New windows present and monotonic (14d >= 7d, 60d >= 30d, 60d <= 6mo) for OpenVINO.
check "week2 (14d) window present"         '(.backends[]|select(.name=="OpenVINO").windows|has("week2"))'
check "month2 (60d) window present"        '(.backends[]|select(.name=="OpenVINO").windows|has("month2"))'
check "14d >= 7d"                          '(.backends[]|select(.name=="OpenVINO")|.windows.week2 >= .windows.week)'
check "60d >= 30d"                         '(.backends[]|select(.name=="OpenVINO")|.windows.month2 >= .windows.month)'
check "60d <= 6mo"                         '(.backends[]|select(.name=="OpenVINO")|.windows.month2 <= .windows.m6)'

# Exclusions NOT in CPU: 310p(10),910b(12),openeuler-910b(8),ui(20),xcframework(5) = 55
# (opencl-adreno(30) now promoted to Adreno backend, macos-arm64(200) to Metal)
check "excluded not counted in CPU"        '(.backends[]|select(.name=="CPU").windows.m6) == 2100'

# Sum of 8 backend m6 totals + excluded == all post-boundary asset downloads.
# 8-backend sum = 13300+640+680+1500+2100+220+200+30 = 18670; excluded = 55; total = 18725.
check "no double-count / no drop"          '([.backends[].windows.m6]|add) == 18670'

# Toolkit invariant: total == sum(by_os)
check "toolkit total == sum(by_os)"        '.openvino.toolkit_versions | all(.total == ([.by_os[]]|add))'
# Two ov_versions post-boundary: 2026.2.1 and 2026.1.0 (2025.9.0 is pre-boundary)
check "post-boundary toolkit versions"     '(.openvino.toolkit_versions|length) == 2'
# Ubuntu-only OpenVINO build counted (b9700 has no windows asset)
check "ubuntu-only OV build counted"       '.openvino.builds[]|select(.build=="b9700")|.by_os.ubuntu == 70'
check "ubuntu-only build no windows key"   '.openvino.builds[]|select(.build=="b9700")|(.by_os|has("windows")|not)'
# Pre-boundary excluded entirely (b8000 / 2025.9.0 absent)
check "pre-boundary excluded"              '(.openvino.builds|map(.build)|index("b8000")) == null'
check "pre-boundary toolkit excluded"      '([.openvino.toolkit_versions[].ov_version]|index("2025.9.0")) == null'

# Trend: array exists; each row total == linux + windows; only last-60-day dates; nonneg.
check "trend array present"                '.openvino|has("trend")'
check "trend total == linux + windows"     '.openvino.trend | all(.total == (.linux + .windows))'
check "trend rows nonneg"                  '.openvino.trend | all(.linux >= 0 and .windows >= 0 and .total >= 0)'
check "trend has rows"                     '(.openvino.trend | length) >= 1'
check "trend dates within 60d"             '.openvino.trend | all(.date >= "2026-04-30")'

echo "---"
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
