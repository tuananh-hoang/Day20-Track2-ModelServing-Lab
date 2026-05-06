# C2 — Quality Evaluation: JSON Extraction

| Prompt | Field yêu cầu | f16 | q8_0 | q4_0 |
|--------|--------------|-----|------|------|
| P1 | `name age city` | ✅ | ✅ | ✅ |
| P2 | `product price currency` | ✅ | ✅ | ✅ |
| P3 | `event date location` | ✅ | ✅ | ✅ |
| P4 | `company founded ceo` | ✅ | ✅ | ✅ |
| P5 | `title author year` | ✅ | ✅ | ✅ |
| P6 | `drug dosage frequency` | ✅ | ✅ | ✅ |
| P7 | `model parameters organization` | ✅ | ✅ | ✅ |

---

## Summary

| KV Cache Type | Pass / 7 | Pass rate (%) |
|---------------|--------------|---------------|
| f16 | 7 / 7 | 100.0% |
| q8_0 | 7 / 7 | 100.0% |
| q4_0 | 7 / 7 | 100.0% |

---

## Ghi chú chất lượng

> Điền thủ công sau khi quan sát output thô trong `quality_prompts/`
>
> - q8_0 thường không gây quality drop đo được trên tác vụ JSON extraction
>   (lý do: 8-bit là đủ để preserve attention pattern quan trọng)
> - q4_0 có thể gây fail ở các prompt dài hoặc có nhiều context cần nhớ
> - Nếu cả 3 cấu hình đều pass 7/7: thử tăng context lên 8192 và thêm
>   prompt yêu cầu trích xuất từ đoạn văn dài 400+ token để thấy degradation

