# Reflection — Lab 20 (Personal Report)

> This is my personal report for running the Day 20 model-serving lab on my own laptop. I focus on my setup, my measurements, and the bottlenecks I observed on this machine rather than comparing raw speed with other students.

---

**Ho Ten:** 2A202600075-Hoang Tuan Anh  
**Ngay submit:** 2026-05-06

---

## 1. Hardware spec (tu `00-setup/detect-hardware.py`)

- **OS:** Ubuntu on WSL2
- **CPU:** AMD Ryzen 7 5800H with Radeon Graphics
- **Cores:** 16 physical / 16 logical
- **CPU extensions:** AVX2
- **RAM visible to WSL:** 5.5 GB
- **Accelerator:** NVIDIA GeForce RTX 3060 Laptop GPU, 6144 MiB VRAM
- **llama.cpp backend da chon:** CUDA (`-DGGML_CUDA=on`)
- **Recommended model tier:** TinyLlama-1.1B (Q4_K_M)

**Setup story:** The hardware probe recommended the CUDA path and TinyLlama-1.1B because WSL only exposes about 5.5 GB RAM, even though the laptop has an RTX 3060 Laptop GPU with 6 GB VRAM. I used the lab virtualenv for Python scripts, but used the native `llama-server` binary from my CUDA build of `llama.cpp` for Track 02 because it exposed the OpenAI-compatible API and Prometheus metrics cleanly.

Important setup detail: `make bench` used `llama-cpp-python` with `n_gpu_layers=99`, but the earlier Python server path did not actually use the GPU until rebuilt with CUDA. For serving, I switched to the native CUDA `llama-server`, where the log confirmed:

```text
ggml_cuda_init: found 1 CUDA devices
offloaded 23/23 layers to GPU
server is listening on http://0.0.0.0:8080
```

---

## 2. Track 01 — Quickstart numbers (tu `benchmarks/01-quickstart-results.md`)

Settings: `n_threads=16`, `n_ctx=2048`, `n_batch=512`, `n_gpu_layers=99`.

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode rate (tok/s) |
|---|--:|--:|--:|--:|--:|
| tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf | 1106 | 292 / 331 | 86.4 / 94.0 | 5378 / 5969 / 6004 | 11.6 |
| tinyllama-1.1b-chat-v1.0.Q2_K.gguf | 145 | 272 / 348 | 69.8 / 84.5 | 4574 / 5458 / 5669 | 14.3 |

**Observation:** Q2_K loaded much faster and decoded faster (`14.3 tok/s` vs `11.6 tok/s`), but the improvement was not large enough for me to prefer it as the primary model. Q4_K_M is slower, but it is the better default for quality and still fits comfortably for this lab.

---

## 3. Track 02 — llama-server load test

Server command used for the main Track 02 run:

```bash
~/projects/llama.cpp/build/bin/llama-server \
  -m models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
  --host 0.0.0.0 --port 8080 \
  -t 16 \
  -ngl 99 \
  --parallel 4 \
  --cont-batching \
  --metrics
```

The server used CUDA and offloaded all 23/23 layers to the RTX 3060 Laptop GPU.

| Concurrency | Total RPS | TTFB/E2E P50 (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|
| 10 | 2.46 | 3000 | 4600 | 5200 | 0 |
| 50 | 2.72 | 17000 | 21000 | 21000 | 0 |

**Load-test observation:** Increasing concurrency from 10 to 50 users did not significantly improve throughput (`2.46 req/s` to `2.72 req/s`), but it increased tail latency sharply. P95 went from `4.6s` to `21.0s`, and P99 went from `5.2s` to `21.0s`. This is a good example of why goodput at an SLO matters more than raw throughput: after saturation, extra users mostly wait in queue.

**Metrics / KV-cache observation:** During the 50-user run, `record-metrics.py` showed `llamacpp:requests_processing` pinned at `4`, which matches `--parallel 4`. `llamacpp:requests_deferred` stayed high, mostly around `39-46`, then decreased as the queue drained near the end. `llamacpp:tokens_predicted_total` increased from `68984` to `82805` during the metrics window, so the model was continuously generating tokens.

My native `llama-server` build did not expose a direct `llamacpp:kv_cache_usage_ratio` metric under `/metrics`, so the patched recorder reports `kv_ratio=n/a` instead of a misleading zero. I used slot saturation (`requests_processing=4`) and deferred queue depth (`requests_deferred` around `39-46`) as the practical observability signal for concurrency and cache pressure.

---

## 4. Track 03 — Milestone integration

- **N16 (Cloud/IaC):** stub: localhost-only serving endpoint on `http://localhost:8080/v1`
- **N17 (Data pipeline):** stub: in-memory toy records inside `TOY_DOCS`
- **N18 (Lakehouse):** stub: no external lakehouse table connected for this lab run
- **N19 (Vector + Feature Store):** stub: keyword-overlap retrieval over `TOY_DOCS`; no real vector store or Feast online store connected yet

The pipeline ran end-to-end with three example queries:

| Query | Retrieved contexts | retrieve (ms) | llama-server (ms) | total (ms) |
|---|---|--:|--:|--:|
| Why is goodput more useful than throughput? | `n20-paged`, `n20-radix`, `n20-disagg` | 0.0 | 2479.8 | 2479.9 |
| What problem does PagedAttention actually solve? | `n20-paged`, `n20-radix`, `n20-disagg` | 0.0 | 1246.2 | 1246.3 |
| When should I think about disaggregated serving? | `n20-disagg`, `n20-paged`, `n20-radix` | 0.0 | 2280.3 | 2280.4 |

**Reflection:** The bottleneck was clearly the local `llama-server` call, not retrieval. Retrieval was a toy in-memory stub and effectively measured as `0.0 ms`, while generation took about `1.2-2.5s` per query. This matched my expectation: in this minimal integration, the serving endpoint dominates latency.

The answer quality was mixed because TinyLlama is small and the retrieval corpus is only a toy set of documents. The important integration result is that the local server speaks the OpenAI-compatible `/v1/chat/completions` API and can be called from a RAG-style pipeline with context provenance.

---

## 5. Bonus — The single change that mattered most

**Change:** Use GPU layer offload with the native CUDA `llama.cpp` build. In the sweep, I compared CPU-only inference (`-ngl 0`) against full GPU offload (`-ngl 99`) on the same TinyLlama Q4_K_M model.

**Before vs after:**

```text
before: -ngl 0  -> 7.5 tok/s
after:  -ngl 99 -> 91.8 tok/s
speedup: ~12.2x
```

The full sweep was written to `benchmarks/bonus-gpu-offload-sweep.md`. The best point in that run was `-ngl 16` at `93.1 tok/s`, while `-ngl 99` was very close at `91.8 tok/s`. Since TinyLlama has only 23 layers and fits easily in the 6 GB RTX 3060 Laptop GPU VRAM, partial and full offload both reached the fast plateau once enough layers were on the GPU.

**Why it worked:** The biggest improvement came from using the GPU-backed native `llama.cpp` build, where the server log confirmed CUDA was available and all model layers could be offloaded (`offloaded 23/23 layers to GPU`). TinyLlama is small enough to fit easily in 6 GB VRAM, so moving the model weights and most compute onto the RTX 3060 avoided the CPU memory-bandwidth bottleneck that made `-ngl 0` slow.

The curve also explains why "more offload" is not always linearly better. Once enough layers were offloaded, the sweep flattened around `90-93 tok/s`; `-ngl 16`, `-ngl 24`, `-ngl 32`, and `-ngl 99` were all close. The main lesson is that backend selection mattered more than small serving knobs for this machine: moving from CPU-only to CUDA offload changed decode throughput by about `12x`, while increasing user concurrency mainly increased queueing and tail latency.

---

## 6. Dieu ngac nhien nhat

The most surprising result was that 50 users did not produce much more throughput than 10 users. It mostly increased queueing and tail latency. This made the deck's warning about goodput at SLO feel very concrete: after saturation, "more concurrent users" is not the same thing as a better serving system.

---

## 7. Self-graded checklist

- [x] `hardware.json` da commit
- [x] `models/active.json` da commit
- [x] `benchmarks/01-quickstart-results.md` da commit
- [x] `benchmarks/02-server-metrics.csv` da commit
- [x] `benchmarks/bonus-*.md` da commit (`benchmarks/bonus-gpu-offload-sweep.md`)
- [x] It nhat 6 screenshots trong `submission/screenshots/` (can chup va them vao folder nay)
- [x] `make verify` exit 0 (can chay lai sau khi them screenshots)
- [x] Repo tren GitHub o che do public
- [x] Da paste public repo URL vao VinUni LMS

---
