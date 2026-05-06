# Bonus — GPU-offload sweep

Model: `tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf`  ·  threads: `16`

| -ngl | decode (tok/s) |
|--:|--:|
| 0 | 10.8 |
| 8 | 9.3 |
| 16 | 24.0 |
| 24 | 93.0 |
| 32 | 91.8 |
| 99 | 91.9 |

When the model fits in VRAM, `-ngl 99` (full offload) is fastest. When it doesn't, partial offload (`-ngl 16` or `-ngl 24`) keeps the most compute on the GPU while spilling weights to RAM — usually still beats CPU-only (`-ngl 0`). Watch for the curve flattening: after the layer count covers the model's actual depth, more `-ngl` does nothing.
