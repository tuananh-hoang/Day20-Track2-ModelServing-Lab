# Day 20 Lab — Numbers Scratchpad

> This is a working summary of the raw numbers collected during the lab. The graded writeup is in [`submission/REFLECTION.md`](../submission/REFLECTION.md).

## Hardware

- Platform: Ubuntu on WSL2
- CPU: AMD Ryzen 7 5800H with Radeon Graphics
- RAM (GB): 5.5 GB visible to WSL
- GPU/accelerator: NVIDIA GeForce RTX 3060 Laptop GPU, 6144 MiB VRAM
- llama.cpp build backend: CUDA (`-DGGML_CUDA=on`)

## Track 01 — Quickstart

Settings: `n_threads=16`, `n_ctx=2048`, `n_batch=512`, `n_gpu_layers=99`.

| Model | Load (ms) | TTFT P50/P95 (ms) | TPOT P50/P95 (ms) | E2E P50/P95/P99 (ms) | Decode rate (tok/s) |
|---|--:|--:|--:|--:|--:|
| tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf | 1106 | 292 / 331 | 86.4 / 94.0 | 5378 / 5969 / 6004 | 11.6 |
| tinyllama-1.1b-chat-v1.0.Q2_K.gguf | 145 | 272 / 348 | 69.8 / 84.5 | 4574 / 5458 / 5669 | 14.3 |

**One observation:** Q2_K was faster and much lighter to load, but I would still keep Q4_K_M as the better default because the speed gap was modest while quality was more reliable.

## Track 02 — llama-server load test

Server command used:

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

| Concurrency | RPS | TTFB P50 (ms) | E2E P95 (ms) | E2E P99 (ms) | Failures |
|--:|--:|--:|--:|--:|--:|
| 10 | 2.46 | 3000 | 4600 | 5200 | 0 |
| 50 | 2.72 | 17000 | 21000 | 21000 | 0 |

**KV-cache observation:** My native `llama-server` build did not expose `llamacpp:kv_cache_usage_ratio`, so I used queue depth and active slots instead. At concurrency 50, `llamacpp:requests_processing` stayed pinned at `4`, matching `--parallel 4`, while `llamacpp:requests_deferred` stayed high around `39-46`. That indicates the system was saturated and extra users mostly waited in queue rather than increasing useful throughput.

## Track 03 — Milestone Integration

- N16 piece used: localhost OpenAI-compatible serving endpoint on `http://localhost:8080/v1`
- N17 piece used: in-memory toy records in `TOY_DOCS`
- N18 piece used: stubbed; no external lakehouse connected
- N19 piece used: stubbed keyword-overlap retrieval; no production vector store or Feast

Latency summary:

| Query | Retrieved contexts | retrieve (ms) | llama-server (ms) | total (ms) |
|---|---|--:|--:|--:|
| Why is goodput more useful than throughput? | `n20-paged`, `n20-radix`, `n20-disagg` | 0.0 | 2479.8 | 2479.9 |
| What problem does PagedAttention actually solve? | `n20-paged`, `n20-radix`, `n20-disagg` | 0.0 | 1246.2 | 1246.3 |
| When should I think about disaggregated serving? | `n20-disagg`, `n20-paged`, `n20-radix` | 0.0 | 2280.3 | 2280.4 |

**Reflection:** Retrieval was effectively free in this toy pipeline. The main latency came from `llama-server`, which means the serving endpoint dominated end-to-end response time in this setup.

## Bonus — llama.cpp optimization

### GPU offload sweep

| -ngl | decode (tok/s) |
|--:|--:|
| 0 | 10.8 |
| 8 | 9.3 |
| 16 | 24.0 |
| 24 | 93.0 |
| 32 | 91.8 |
| 99 | 91.9 |

### KV-cache quantization

| KV cache type | Prefill (t/s) | Decode (t/s) | Quality pass rate |
|---|--:|--:|--:|
| f16 | 685.20 | 13.37 | 7 / 7 |
| q8_0 | 642.22 | 12.82 | 7 / 7 |
| q4_0 | 628.39 | 12.06 | 7 / 7 |

### The one change that mattered most

The biggest improvement came from GPU offload with the native CUDA build. In the sweep, CPU-only inference (`-ngl 0`) reached `10.8 tok/s`, while full or near-full GPU offload (`-ngl 24` to `-ngl 99`) reached about `92-93 tok/s`, an improvement of roughly `8.5x`. On this laptop, backend choice mattered more than smaller tuning knobs.

## Bonus — MLX (macOS only, optional)

Not applicable on this machine.

## Notes / pitfalls / things I'd do differently

- WSL and the Python path were initially misleading because `make bench` could run without clearly showing whether CUDA was actually active.
- The native `llama-server` binary was easier to validate because the startup log explicitly confirmed GPU detection and layer offload.
- If I repeated the KV-cache experiment, I would increase context length and use longer extraction prompts so quality differences have a better chance to appear.
