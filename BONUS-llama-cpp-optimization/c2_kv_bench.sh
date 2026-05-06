#!/bin/bash
# =============================================================================
# C2 — KV-cache Quantization Benchmark (STABLE)
# =============================================================================

set -uo pipefail

# ── Cấu hình ────────────────────────────────────────────────────────────────
LLAMA_BENCH="$HOME/projects/llama.cpp/build/bin/llama-bench"
MODEL="$HOME/models/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
OUTPUT_DIR="$HOME/VinUniProject/Day20-Track2-ModelServing-Lab/BONUS-llama-cpp-optimization/benchmarks"
RESULTS_FILE="$OUTPUT_DIR/bonus-kv-cache-quant.md"

# Tham số
NGL=99
PROMPT_TOKENS=512
GEN_TOKENS=256
REPETITIONS=2
KV_CONFIGS=("f16" "q8_0" "q4_0")

mkdir -p "$OUTPUT_DIR"

echo "============================================================"
echo "  C2 KV-cache Quantization Benchmark (Stable Version)"
echo "  GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"
echo "============================================================"

# Khởi tạo file kết quả
echo "# C2 — KV-cache Quantization Results" > "$RESULTS_FILE"
echo "| KV Type | Prefill (t/s) | Decode (t/s) |" >> "$RESULTS_FILE"
echo "|---------|---------------|--------------|" >> "$RESULTS_FILE"

for KV in "${KV_CONFIGS[@]}"; do
    echo -e "\n>>> Testing KV Cache: $KV..."
    
    # Chạy llama-bench
    RAW_OUTPUT=$("$LLAMA_BENCH" -m "$MODEL" -ngl $NGL -p $PROMPT_TOKENS -n $GEN_TOKENS -r $REPETITIONS -ctk "$KV" -ctv "$KV" -fa 1 -o md 2>&1)
    
    # Parse kết quả
    PP_TPS=$(echo "$RAW_OUTPUT" | grep "pp${PROMPT_TOKENS}" | awk -F'|' '{print $(NF-1)}' | sed 's/±.*//' | xargs)
    TG_TPS=$(echo "$RAW_OUTPUT" | grep "tg${GEN_TOKENS}"    | awk -F'|' '{print $(NF-1)}' | sed 's/±.*//' | xargs)
    
    echo "    Speed: Prefill ${PP_TPS:-N/A} t/s | Decode ${TG_TPS:-N/A} t/s"
    echo "| $KV | ${PP_TPS:-N/A} | ${TG_TPS:-N/A} |" >> "$RESULTS_FILE"
    
    # Lưu log thô
    echo "$RAW_OUTPUT" > "$OUTPUT_DIR/raw_kv_${KV}.txt"
done

echo -e "\nDone! Results saved to: $RESULTS_FILE"