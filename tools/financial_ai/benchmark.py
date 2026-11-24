"""Benchmarks Cold-Start Load Time, Warm Inference Latency (p50/p95), and Peak RAM."""

from __future__ import annotations
import json
import statistics
import time
import tracemalloc
from pathlib import Path
from evaluate import QuantizedFastTextReader
from feature_spec import normalize_for_classifier

BASE_DIR = Path(__file__).resolve().parent
ART_DIR = BASE_DIR / "artifacts"

BENCHMARK_QUERIES = [
    "ăn sáng phở bò 65 nghìn",
    "an sang 35k",
    "cf highlands 55k",
    "do xang petrolimex 80k",
    "thanh toán tiền điện evn 950k",
    "nhận lương tháng 11 18tr5",
    "mua thuốc cảm nhà thuốc long châu 120k",
    "gia hạn gói netflix 260k",
    "thay nhớt xe vision 165k",
    "đi taxi xanh sm 85 nghìn",
]


def percentile(sorted_vals: list[float], pct: float) -> float:
    if not sorted_vals:
        return 0.0
    idx = min(len(sorted_vals) - 1, max(0, int(round((pct / 100.0) * (len(sorted_vals) - 1)))))
    return sorted_vals[idx]


def main() -> None:
    ftq_path = ART_DIR / "vn_financial_fasttext_v1.ftq"

    tracemalloc.start()
    t_cold0 = time.perf_counter()
    raw_bytes = ftq_path.read_bytes()
    reader = QuantizedFastTextReader(raw_bytes)
    _ = reader.predict(normalize_for_classifier(BENCHMARK_QUERIES[0]))
    cold_start_ms = (time.perf_counter() - t_cold0) * 1000.0
    _, peak_bytes = tracemalloc.get_traced_memory()
    tracemalloc.stop()

    # Warm latency over 1,000 inferences
    latencies_ms: list[float] = []
    for i in range(1000):
        q = BENCHMARK_QUERIES[i % len(BENCHMARK_QUERIES)]
        t0 = time.perf_counter()
        norm = normalize_for_classifier(q)
        _ = reader.predict(norm)
        latencies_ms.append((time.perf_counter() - t0) * 1000.0)

    latencies_ms.sort()
    p50 = percentile(latencies_ms, 50)
    p95 = percentile(latencies_ms, 95)
    p99 = percentile(latencies_ms, 99)
    mean_ms = statistics.mean(latencies_ms)

    bench = {
        "model_size_bytes": len(raw_bytes),
        "model_size_kb": round(len(raw_bytes) / 1024.0, 2),
        "cold_start_ms": round(cold_start_ms, 3),
        "warm_latency_mean_ms": round(mean_ms, 4),
        "warm_latency_p50_ms": round(p50, 4),
        "warm_latency_p95_ms": round(p95, 4),
        "warm_latency_p99_ms": round(p99, 4),
        "peak_python_heap_kb": round(peak_bytes / 1024.0, 2),
        "iterations": 1000,
    }
    (ART_DIR / "python_benchmark.json").write_text(json.dumps(bench, indent=2), encoding="utf-8")
    print(
        f"[BENCHMARK] Size={bench['model_size_kb']} KB | ColdStart={bench['cold_start_ms']} ms "
        f"| Warm p50={bench['warm_latency_p50_ms']} ms | p95={bench['warm_latency_p95_ms']} ms "
        f"| PeakHeap={bench['peak_python_heap_kb']} KB"
    )


if __name__ == "__main__":
    main()
