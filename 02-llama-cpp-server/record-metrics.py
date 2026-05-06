#!/usr/bin/env python3
"""Poll llama-server's /metrics every N seconds during a load run, write CSV.

Usage:
    # In one terminal: start llama-server.
    # In another:      start locust.
    # In a third:      python 02-llama-cpp-server/record-metrics.py --duration 60
"""
from __future__ import annotations

import argparse
import csv
import re
import sys
import time
from pathlib import Path
from typing import Callable

import httpx

INTERESTING = {
    "llamacpp:n_decode_total",
    "llamacpp:n_busy_slots_per_decode",
    "llamacpp:tokens_predicted_total",
    "llamacpp:prompt_tokens_total",
    "llamacpp:requests_processing",
    "llamacpp:requests_deferred",
}

KV_RATIO_CANDIDATES = [
    "llamacpp:kv_cache_usage_ratio",
    "llamacpp:kv_cache_ratio",
    "llamacpp:cache_usage_ratio",
    "llamacpp:slot_kv_cache_usage_ratio",
]

KV_TOKEN_CANDIDATES = [
    "llamacpp:kv_cache_tokens",
    "llamacpp:kv_tokens",
    "llamacpp:cache_tokens",
    "llamacpp:slot_kv_cache_tokens",
]

LINE = re.compile(r"^([a-z_:]+)(?:\{[^}]*\})?\s+([0-9eE.+-]+)$")


def pick_metric(
    metrics: dict[str, float],
    candidates: list[str],
    predicate: Callable[[str], bool] | None = None,
) -> tuple[str | None, float | None]:
    for name in candidates:
        if name in metrics:
            return name, metrics[name]
    if predicate is not None:
        for name, value in metrics.items():
            if predicate(name):
                return name, value
    return None, None


def scrape(url: str) -> dict[str, float | str]:
    parsed: dict[str, float] = {}
    try:
        text = httpx.get(url, timeout=3.0).text
    except httpx.HTTPError:
        return {}
    for raw in text.splitlines():
        if raw.startswith("#"):
            continue
        m = LINE.match(raw.strip())
        if not m:
            continue
        name, val = m.group(1), m.group(2)
        try:
            parsed[name] = float(val)
        except ValueError:
            pass

    out: dict[str, float | str] = {
        name: parsed[name] for name in INTERESTING if name in parsed
    }

    kv_ratio_name, kv_ratio_value = pick_metric(
        parsed,
        KV_RATIO_CANDIDATES,
        predicate=lambda metric: "llamacpp:" in metric and "kv" in metric and "ratio" in metric,
    )
    kv_tokens_name, kv_tokens_value = pick_metric(
        parsed,
        KV_TOKEN_CANDIDATES,
        predicate=lambda metric: "llamacpp:" in metric and "kv" in metric and "token" in metric,
    )

    if kv_ratio_name is not None and kv_ratio_value is not None:
        out["kv_ratio"] = kv_ratio_value
        out["kv_ratio_metric"] = kv_ratio_name
    if kv_tokens_name is not None and kv_tokens_value is not None:
        out["kv_tokens"] = kv_tokens_value
        out["kv_tokens_metric"] = kv_tokens_name

    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://localhost:8080/metrics")
    parser.add_argument("--duration", type=int, default=60, help="seconds to record")
    parser.add_argument("--interval", type=float, default=2.0, help="seconds between scrapes")
    parser.add_argument("--out", default="benchmarks/02-server-metrics.csv")
    args = parser.parse_args()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    deadline = time.time() + args.duration
    rows: list[dict[str, float | str]] = []
    warned_missing_kv = False
    print(f"==> Recording {args.url} for {args.duration}s, every {args.interval}s")
    while time.time() < deadline:
        sample = scrape(args.url)
        if sample:
            sample["t"] = round(time.time(), 1)
            rows.append(sample)
            kv_display = (
                f"{sample['kv_ratio']:.2f}"
                if isinstance(sample.get("kv_ratio"), float)
                else "n/a"
            )
            print(
                f"   t={sample['t']:.0f}  "
                f"reqs_proc={sample.get('llamacpp:requests_processing', 0):.0f}  "
                f"deferred={sample.get('llamacpp:requests_deferred', 0):.0f}  "
                f"kv_ratio={kv_display}  "
                f"tok_pred={sample.get('llamacpp:tokens_predicted_total', 0):.0f}"
            )
            if not warned_missing_kv and "kv_ratio" not in sample:
                print("   note: this llama-server build does not expose a KV-cache ratio metric under /metrics")
                warned_missing_kv = True
        else:
            print("   (scrape failed — is llama-server running with --metrics?)")
        time.sleep(args.interval)

    if not rows:
        print("ERROR: no samples collected.", file=sys.stderr)
        return 1

    fieldnames = sorted({k for r in rows for k in r.keys()})
    with out_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in rows:
            w.writerow(r)
    print(f"\n==> Wrote {out_path} ({len(rows)} samples)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
