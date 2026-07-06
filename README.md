# llama.cpp Download Metrics Dashboard

A static dashboard tracking [llama.cpp release-binary downloads](https://github.com/ggml-org/llama.cpp/releases), focused on the OpenVINO builds.

### 📊 Explore the Live Dashboard: https://ravi9.github.io/llamacpp-metrics/
* **Metrics Tracked:** Downloads by Backend; Downloads by OpenVINO Version; OpenVINO Downloads by Release Date; Downloads by Release Build

> **Note**: Additional downloads also occur via [Docker containers](https://github.com/ggml-org/llama.cpp/pkgs/container/llama.cpp/versions?filters%5Bversion_type%5D=tagged). Including Docker download metrics is work in progress.

---

## How it works

A daily GitHub Actions workflow enumerates llama.cpp releases via the GitHub API and aggregates them with `jq` into a flat `metrics.json`. The `index.html` file uses vanilla JS + Chart.js to render the final graphics. The client never computes the analytics directly.

---

## Run locally

```bash
git clone https://github.com/ravi9/llamacpp-metrics.git
cd llamacpp-metrics

# 1. collect releases (needs network)
scripts/collect-releases.sh
# GITHUB_TOKEN is optional — set it to raise the GitHub API rate limit (60→5000/hr):
# GITHUB_TOKEN=$YOUR_TOKEN scripts/collect-releases.sh

# 2. aggregate raw data → metrics.json
scripts/aggregate.sh

# 3. serve (any static server)
python3 -m http.server 8000   # then open http://localhost:8000
```

---

- [OpenVINO Docs](https://docs.openvino.ai/)
- [LlamaCPP OpenVINO Backend Docs](https://github.com/ggml-org/llama.cpp/blob/master/docs/backend/OPENVINO.md)
- [LlamaCPP OpenVINO Backend Developer Guide](https://github.com/ravi9/llamacpp-ov-dev-guide/tree/main)

---

## License

Licensed under the [Apache License 2.0](LICENSE).