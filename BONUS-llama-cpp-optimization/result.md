# BONUS — llama.cpp Optimization Results
> 2A202600075 - Hoang Tuan Anh
This file summarizes the bonus optimization work completed on my own laptop. The two bonus directions I focused on were GPU offload and challenge C2 on KV-cache quantization.

## Setup

- Platform: Ubuntu on WSL2
- CPU: AMD Ryzen 7 5800H
- RAM visible to WSL: 5.5 GB
- GPU: NVIDIA GeForce RTX 3060 Laptop GPU, 6144 MiB VRAM
- llama.cpp backend: CUDA

## Result 1 — GPU offload mattered the most

Model used: `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf`

| -ngl | decode (tok/s) |
|--:|--:|
| 0 | 10.8 |
| 8 | 9.3 |
| 16 | 24.0 |
| 24 | 93.0 |
| 32 | 91.8 |
| 99 | 91.9 |

**Main takeaway:** Moving from CPU-only inference to GPU offload changed throughput dramatically. The model reached only `10.8 tok/s` at `-ngl 0`, but around `92-93 tok/s` once enough layers were offloaded to the GPU. On this machine, that was the biggest single optimization lever by far.

**Why it happened:** TinyLlama fits easily into 6 GB VRAM, so once enough layers are placed on the RTX 3060, the workload stops being limited by CPU memory bandwidth. The curve also flattened after `-ngl 24`, which shows that beyond the model's actual depth, larger `-ngl` values do not buy more speed.

## Result 2 — Challenge C2: KV-cache quantization

Model used: `mistral-7b-instruct-v0.1.Q4_K_M.gguf`

### Performance

| KV cache type | Prefill (t/s) | Decode (t/s) |
|---|--:|--:|
| f16 | 685.20 | 13.37 |
| q8_0 | 642.22 | 12.82 |
| q4_0 | 628.39 | 12.06 |

### Quality

| KV cache type | JSON extraction pass rate |
|---|--:|
| f16 | 7 / 7 |
| q8_0 | 7 / 7 |
| q4_0 | 7 / 7 |

**Main takeaway:** On this short structured-output task, KV-cache quantization did not improve speed and did not cause a measurable quality drop. `q8_0` and `q4_0` were both slightly slower than `f16` in decode throughput, but all three settings passed every prompt in the 7-prompt JSON extraction set.

**Why it matters:** This is still a useful negative result. It shows that an optimization can be technically valid without being the dominant performance lever in a small local setup. On my laptop, GPU offload was the high-impact decision, while KV-cache quantization looked more like a memory-oriented knob whose trade-offs would likely become more visible at longer context lengths or under tighter memory pressure.

## Final reflection

The most important lesson from the bonus track was that optimization needs to be matched to the actual bottleneck. On this laptop, CUDA offload produced a large practical gain immediately. KV-cache quantization, by contrast, was more subtle: it preserved quality on a short eval set, but it did not create an obvious latency win in the same way. That contrast made the bonus work useful, because it separated "interesting engine feature" from "change that matters most on my machine."
