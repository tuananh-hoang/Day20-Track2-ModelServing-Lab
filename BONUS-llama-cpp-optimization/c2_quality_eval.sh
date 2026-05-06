#!/bin/bash
# =============================================================================
# C2 — Quality Evaluation: JSON Extraction Task
# Dùng tập 7 prompt cố định, chấm tự động bằng Python JSON parser
# Chạy SAU c2_kv_bench.sh
# =============================================================================

set -euo pipefail

LLAMA_CLI="$HOME/projects/llama.cpp/build/bin/llama-cli"
MODEL="$HOME/models/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
OUTPUT_DIR="$HOME/VinUniProject/Day20-Track2-ModelServing-Lab/BONUS-llama-cpp-optimization/benchmarks"
QUALITY_FILE="$OUTPUT_DIR/bonus-kv-cache-quality.md"
PROMPTS_DIR="$OUTPUT_DIR/quality_prompts"

NGL=99
CONTEXT=2048
MAX_NEW_TOKENS=200
LLAMA_TIMEOUT=120
KV_CONFIGS=("f16" "q8_0" "q4_0")

mkdir -p "$PROMPTS_DIR"

if [[ ! -x "$LLAMA_CLI" ]]; then
    echo "ERROR: llama-cli not found or not executable: $LLAMA_CLI" >&2
    exit 1
fi

if [[ ! -f "$MODEL" ]]; then
    echo "ERROR: model file not found: $MODEL" >&2
    exit 1
fi

# =============================================================================
# 7 PROMPT JSON EXTRACTION — cố định, chấm tự động
# Mỗi prompt yêu cầu model trả về JSON với schema xác định trước
# =============================================================================

declare -a PROMPT_TEXTS
declare -a REQUIRED_KEYS   # các key bắt buộc phải có trong JSON output

# Prompt 1
PROMPT_TEXTS[0]='[INST] Extract the following fields from the text as a JSON object with keys: name, age, city.
Text: "Alice is 28 years old and lives in Paris."
Respond ONLY with a valid JSON object. No explanation. [/INST]'
REQUIRED_KEYS[0]="name age city"

# Prompt 2
PROMPT_TEXTS[1]='[INST] Extract the following fields from the text as a JSON object with keys: product, price, currency.
Text: "The MacBook Pro costs 1999 USD in the Apple store."
Respond ONLY with a valid JSON object. No explanation. [/INST]'
REQUIRED_KEYS[1]="product price currency"

# Prompt 3
PROMPT_TEXTS[2]='[INST] Extract the following fields from the text as a JSON object with keys: event, date, location.
Text: "The annual AI conference will be held on March 15, 2025 in San Francisco."
Respond ONLY with a valid JSON object. No explanation. [/INST]'
REQUIRED_KEYS[2]="event date location"

# Prompt 4
PROMPT_TEXTS[3]='[INST] Extract the following fields from the text as a JSON object with keys: company, founded, ceo.
Text: "OpenAI was founded in 2015. Sam Altman serves as its CEO."
Respond ONLY with a valid JSON object. No explanation. [/INST]'
REQUIRED_KEYS[3]="company founded ceo"

# Prompt 5
PROMPT_TEXTS[4]='[INST] Extract the following fields from the text as a JSON object with keys: title, author, year.
Text: "Attention is All You Need was authored by Vaswani et al. and published in 2017."
Respond ONLY with a valid JSON object. No explanation. [/INST]'
REQUIRED_KEYS[4]="title author year"

# Prompt 6
PROMPT_TEXTS[5]='[INST] Extract the following fields from the text as a JSON object with keys: drug, dosage, frequency.
Text: "The patient was prescribed Metformin 500mg to be taken twice daily."
Respond ONLY with a valid JSON object. No explanation. [/INST]'
REQUIRED_KEYS[5]="drug dosage frequency"

# Prompt 7
PROMPT_TEXTS[6]='[INST] Extract the following fields from the text as a JSON object with keys: model, parameters, organization.
Text: "Llama 3 is a large language model with 8 billion parameters released by Meta AI."
Respond ONLY with a valid JSON object. No explanation. [/INST]'
REQUIRED_KEYS[6]="model parameters organization"

# =============================================================================
# Hàm chấm tự động bằng Python
# Pass: output là valid JSON VÀ chứa tất cả required keys
# =============================================================================
grade_output() {
    local OUTPUT_TEXT="$1"
    local KEYS="$2"

    OUTPUT_TEXT="$OUTPUT_TEXT" REQUIRED_KEYS="$KEYS" python3 - << 'PYEOF'
import json
import os
import re
import sys

text = os.environ["OUTPUT_TEXT"]
keys = os.environ["REQUIRED_KEYS"].split()

# Tìm JSON block trong output (model có thể sinh thêm text xung quanh)
json_match = re.search(r'\{[^{}]*\}', text, re.DOTALL)
if not json_match:
    print("FAIL:no_json")
    sys.exit(0)

try:
    obj = json.loads(json_match.group())
except json.JSONDecodeError as e:
    print(f"FAIL:invalid_json:{e}")
    sys.exit(0)

missing = [k for k in keys if k not in obj]
if missing:
    print(f"FAIL:missing_keys:{','.join(missing)}")
else:
    print("PASS")
PYEOF
}

# =============================================================================
# Chạy đánh giá
# =============================================================================
echo "============================================================"
echo "  C2 Quality Evaluation — $(date)"
echo "============================================================"

cat > "$QUALITY_FILE" << 'EOF'
# C2 — Quality Evaluation: JSON Extraction

| Prompt | Field yêu cầu | f16 | q8_0 | q4_0 |
|--------|--------------|-----|------|------|
EOF

declare -A PASS_COUNT
for KV in "${KV_CONFIGS[@]}"; do PASS_COUNT[$KV]=0; done

for i in "${!PROMPT_TEXTS[@]}"; do
    PROMPT="${PROMPT_TEXTS[$i]}"
    KEYS="${REQUIRED_KEYS[$i]}"
    PROMPT_NUM=$((i + 1))

    echo ""
    echo "--- Prompt $PROMPT_NUM / ${#PROMPT_TEXTS[@]} ---"
    echo "    Required keys: $KEYS"

    # Lưu prompt ra file tạm (tránh shell escaping issue)
    PROMPT_FILE="$PROMPTS_DIR/prompt_${i}.txt"
    printf '%s' "$PROMPT" > "$PROMPT_FILE"

    ROW="| P${PROMPT_NUM} | \`${KEYS}\` |"

    for KV in "${KV_CONFIGS[@]}"; do
        RAW_OUTPUT_FILE="$PROMPTS_DIR/output_p${i}_kv${KV}.raw.txt"
        CLEAN_OUTPUT_FILE="$PROMPTS_DIR/output_p${i}_kv${KV}.txt"
        
        set +e
        timeout "${LLAMA_TIMEOUT}s" "$LLAMA_CLI" \
            -m "$MODEL" \
            -ngl "$NGL" \
            -c "$CONTEXT" \
            -n "$MAX_NEW_TOKENS" \
            -ctk "$KV" \
            -ctv "$KV" \
            -fa on \
            --temp 0.0 \
            -f "$PROMPT_FILE" \
            -st \
            --simple-io \
            --no-warmup \
            --no-display-prompt \
            --no-show-timings \
            --log-disable \
            > "$RAW_OUTPUT_FILE" 2>&1 < /dev/null
        RUN_STATUS=$?
        set -e

        OUTPUT=$(grep -v -E '^(build|model|modali|avail|Loading|main:|sampler chain:|generate:|common_params:|system_info:|ggml_|available commands:|please use llama-completion instead|--no-conversation is not supported by llama-cli|>|<\|im_end\|>)|^[[:space:]]*/|^[▄█]' "$RAW_OUTPUT_FILE" | tail -50 || true)

        # Lưu output thô
        printf '%s\n' "$OUTPUT" > "$CLEAN_OUTPUT_FILE"

        if [[ "$RUN_STATUS" -eq 124 ]]; then
            GRADE="FAIL:timeout"
        elif [[ "$RUN_STATUS" -ne 0 ]]; then
            GRADE="FAIL:command_error_${RUN_STATUS}"
        else
            GRADE=$(grade_output "$OUTPUT" "$KEYS")
        fi

        echo "    [$KV] → $GRADE"

        if [[ "$GRADE" == "PASS" ]]; then
            PASS_COUNT[$KV]=$((PASS_COUNT[$KV] + 1))
            ROW="${ROW} ✅ |"
        else
            FAIL_REASON=$(echo "$GRADE" | cut -d: -f2-)
            ROW="${ROW} ❌ (${FAIL_REASON}) |"
        fi
    done

    echo "$ROW" >> "$QUALITY_FILE"
done

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL=${#PROMPT_TEXTS[@]}

cat >> "$QUALITY_FILE" << EOF

---

## Summary

| KV Cache Type | Pass / $TOTAL | Pass rate (%) |
|---------------|--------------|---------------|
EOF

echo ""
echo "============================================================"
echo "  SUMMARY:"
for KV in "${KV_CONFIGS[@]}"; do
    PASS="${PASS_COUNT[$KV]}"
    RATE=$(python3 -c "print(f'{$PASS/$TOTAL*100:.1f}')")
    echo "    [$KV] → $PASS / $TOTAL passed ($RATE%)"
    echo "| $KV | $PASS / $TOTAL | $RATE% |" >> "$QUALITY_FILE"
done

cat >> "$QUALITY_FILE" << 'EOF'

---

## Ghi chú chất lượng

> Điền thủ công sau khi quan sát output thô trong `quality_prompts/`
>
> - q8_0 thường không gây quality drop đo được trên tác vụ JSON extraction
>   (lý do: 8-bit là đủ để preserve attention pattern quan trọng)
> - q4_0 có thể gây fail ở các prompt dài hoặc có nhiều context cần nhớ
> - Nếu cả 3 cấu hình đều pass 7/7: thử tăng context lên 8192 và thêm
>   prompt yêu cầu trích xuất từ đoạn văn dài 400+ token để thấy degradation

EOF

echo "============================================================"
echo "  Quality eval hoàn thành."
echo "  Kết quả: $QUALITY_FILE"
echo "  Raw outputs: $PROMPTS_DIR/"
echo "============================================================"
