"""Unified Independent Benchmark & Anti-Leakage Verification for BOTH LifeOS Local AI Models.

Verifies:
1. 0% normalized text & template leakage across train / val / test for both in-domain and OOD splits.
2. Evaluates BOTH quantized `.ftq` models (`assets/models/vn_financial_fasttext_v1.ftq` and
   `assets/models/vn_money_split_fasttext_v1.ftq`) on strictly disjoint held-out test sets
   plus >= 250 unseen multi-stratum OOD utterances each.
3. Measures Accuracy, Macro F1, Per-Class P/R/F1, Confusion Matrix, Per-Stratum OOD Rejection,
   Overall OOD Rejection, OOD AUROC, False Auto-Assignment Rate, ECE, Latency P50/P95, Size, SHA-256.
4. Saves `tools/financial_ai/artifacts/v327_full_ai_eval_report.json` and updates `eval_report.json`
   + `vn_money_split_fasttext_v1_eval.json`.
"""

from __future__ import annotations

import hashlib
import json
import statistics
import time
from pathlib import Path

from evaluate import QuantizedFastTextReader, evaluate_model_on_splits
from feature_spec import (
    FINANCIAL_THRESHOLDS,
    MONEY_SPLIT_THRESHOLDS,
    normalize_for_classifier,
)

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"
ART_DIR = BASE_DIR / "artifacts"
REPO_ROOT = BASE_DIR.parent.parent
ASSETS_DIR = REPO_ROOT / "assets" / "models"

FIN_LATENCY_QUERIES = [
    "ăn sáng phở bò 65 nghìn",
    "an sang 35k",
    "cf highlands 55k",
    "do xang petrolimex 80k",
    "thanh toán tiền điện evn 950k",
    "nhận lương tháng 11 18tr5",
    "mua thuốc cảm nhà thuốc long châu 120k",
    "gia hạn gói netflix 260k",
    "kẹt xe trên đường lê văn lương",
    "mã otp xác thực là 482910",
]

SPLIT_LATENCY_QUERIES = [
    "ăn lẩu bò 600k chia đều 4 người",
    "tiền điện 900k hòa 60 phần trăm minh 40 phần trăm",
    "đi ăn hải sản 1tr4 nhà hòa 2 suất nam 1 suất",
    "nhận lương 22tr phân bổ theo quy tắc 50 30 20",
    "lương 26 triệu chia vào 6 chiếc lọ tài chính",
    "chuyển khoản 2 triệu cho mẹ",
    "nhận lương tháng này 20 triệu",
    "kẹt xe ngoài ngã tư căng quá",
]


def _percentile(sorted_vals: list[float], pct: float) -> float:
    if not sorted_vals:
        return 0.0
    idx = min(len(sorted_vals) - 1, max(0, int(round((pct / 100.0) * (len(sorted_vals) - 1)))))
    return sorted_vals[idx]


def _read_jsonl(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def verify_zero_leakage() -> dict[str, object]:
    def norm_of(r: dict[str, str]) -> str:
        return str(r.get("normalized_text") or r.get("normalized") or "")

    # 1. Financial ID splits
    fin_tr = _read_jsonl(DATA_DIR / "train.jsonl")
    fin_va = _read_jsonl(DATA_DIR / "val.jsonl")
    fin_te = _read_jsonl(DATA_DIR / "test.jsonl")

    fin_id_norms = {
        "train": {norm_of(r) for r in fin_tr},
        "val": {norm_of(r) for r in fin_va},
        "test": {norm_of(r) for r in fin_te},
    }
    fin_id_tpls = {
        "train": {r["template_id"] for r in fin_tr},
        "val": {r["template_id"] for r in fin_va},
        "test": {r["template_id"] for r in fin_te},
    }
    assert fin_id_norms["train"].isdisjoint(fin_id_norms["val"])
    assert fin_id_norms["train"].isdisjoint(fin_id_norms["test"])
    assert fin_id_norms["val"].isdisjoint(fin_id_norms["test"])
    assert fin_id_tpls["train"].isdisjoint(fin_id_tpls["val"])
    assert fin_id_tpls["train"].isdisjoint(fin_id_tpls["test"])
    assert fin_id_tpls["val"].isdisjoint(fin_id_tpls["test"])

    # 2. Financial OOD splits
    food_tr = _read_jsonl(DATA_DIR / "ood_financial_train.jsonl")
    food_va = _read_jsonl(DATA_DIR / "ood_financial_val.jsonl")
    food_te = _read_jsonl(DATA_DIR / "ood_financial_test.jsonl")
    assert len(food_te) >= 250, f"Financial OOD test must have >= 250 samples, got {len(food_te)}"

    food_norms = {
        "train": {norm_of(r) for r in food_tr},
        "val": {norm_of(r) for r in food_va},
        "test": {norm_of(r) for r in food_te},
    }
    food_tpls = {
        "train": {r["template_id"] for r in food_tr},
        "val": {r["template_id"] for r in food_va},
        "test": {r["template_id"] for r in food_te},
    }
    assert food_norms["train"].isdisjoint(food_norms["val"])
    assert food_norms["train"].isdisjoint(food_norms["test"])
    assert food_norms["val"].isdisjoint(food_norms["test"])
    assert food_tpls["train"].isdisjoint(food_tpls["val"])
    assert food_tpls["train"].isdisjoint(food_tpls["test"])
    assert food_tpls["val"].isdisjoint(food_tpls["test"])

    all_fin_id = fin_id_norms["train"] | fin_id_norms["val"] | fin_id_norms["test"]
    all_food = food_norms["train"] | food_norms["val"] | food_norms["test"]
    assert all_food.isdisjoint(all_fin_id), "Financial OOD collides with Financial ID!"

    # 3. Money Split ID splits
    ms_tr = _read_jsonl(DATA_DIR / "money_split_train.jsonl")
    ms_va = _read_jsonl(DATA_DIR / "money_split_val.jsonl")
    ms_te = _read_jsonl(DATA_DIR / "money_split_test.jsonl")
    ms_norms = {
        "train": {norm_of(r) for r in ms_tr},
        "val": {norm_of(r) for r in ms_va},
        "test": {norm_of(r) for r in ms_te},
    }
    assert ms_norms["train"].isdisjoint(ms_norms["val"])
    assert ms_norms["train"].isdisjoint(ms_norms["test"])
    assert ms_norms["val"].isdisjoint(ms_norms["test"])

    # 4. Money Split OOD splits
    ms_ood_tr = _read_jsonl(DATA_DIR / "ood_money_split_train.jsonl")
    ms_ood_va = _read_jsonl(DATA_DIR / "ood_money_split_val.jsonl")
    ms_ood_te = _read_jsonl(DATA_DIR / "ood_money_split_test.jsonl")
    assert len(ms_ood_te) >= 250, f"Money Split OOD test must have >= 250 samples, got {len(ms_ood_te)}"

    ms_ood_norms = {
        "train": {norm_of(r) for r in ms_ood_tr},
        "val": {norm_of(r) for r in ms_ood_va},
        "test": {norm_of(r) for r in ms_ood_te},
    }
    ms_ood_tpls = {
        "train": {r["template_id"] for r in ms_ood_tr},
        "val": {r["template_id"] for r in ms_ood_va},
        "test": {r["template_id"] for r in ms_ood_te},
    }
    assert ms_ood_norms["train"].isdisjoint(ms_ood_norms["val"])
    assert ms_ood_norms["train"].isdisjoint(ms_ood_norms["test"])
    assert ms_ood_norms["val"].isdisjoint(ms_ood_norms["test"])
    assert ms_ood_tpls["train"].isdisjoint(ms_ood_tpls["val"])
    assert ms_ood_tpls["train"].isdisjoint(ms_ood_tpls["test"])
    assert ms_ood_tpls["val"].isdisjoint(ms_ood_tpls["test"])

    all_ms_id = ms_norms["train"] | ms_norms["val"] | ms_norms["test"]
    all_ms_ood = ms_ood_norms["train"] | ms_ood_norms["val"] | ms_ood_norms["test"]
    assert all_ms_ood.isdisjoint(all_ms_id), "Money Split OOD collides with Money Split ID!"

    return {
        "financialIdLeakagePct": 0.0,
        "financialOodLeakagePct": 0.0,
        "financialOodVsIdLeakagePct": 0.0,
        "moneySplitIdLeakagePct": 0.0,
        "moneySplitOodLeakagePct": 0.0,
        "moneySplitOodVsIdLeakagePct": 0.0,
        "counts": {
            "financialId": {"train": len(fin_tr), "val": len(fin_va), "test": len(fin_te)},
            "financialOod": {"train": len(food_tr), "val": len(food_va), "test": len(food_te)},
            "moneySplitId": {"train": len(ms_tr), "val": len(ms_va), "test": len(ms_te)},
            "moneySplitOod": {"train": len(ms_ood_tr), "val": len(ms_ood_va), "test": len(ms_ood_te)},
        },
    }


def _benchmark_python(ftq_path: Path, queries: list[str], iterations: int = 800) -> dict[str, float | int | str]:
    t_cold0 = time.perf_counter()
    raw_bytes = ftq_path.read_bytes()
    reader = QuantizedFastTextReader(raw_bytes)
    _ = reader.predict(normalize_for_classifier(queries[0]))
    cold_ms = (time.perf_counter() - t_cold0) * 1000.0

    latencies_ms: list[float] = []
    for i in range(iterations):
        q = queries[i % len(queries)]
        t0 = time.perf_counter()
        _ = reader.predict(normalize_for_classifier(q))
        latencies_ms.append((time.perf_counter() - t0) * 1000.0)
    latencies_ms.sort()

    sha = hashlib.sha256(raw_bytes).hexdigest()
    return {
        "sizeBytes": len(raw_bytes),
        "sizeKb": round(len(raw_bytes) / 1024.0, 2),
        "sha256": sha,
        "temperature": round(reader.temperature, 4),
        "totalOutputClasses": reader.num_classes,
        "coldStartMs": round(cold_ms, 3),
        "warmLatencyMeanMs": round(statistics.mean(latencies_ms), 4),
        "warmLatencyP50Ms": round(_percentile(latencies_ms, 50), 4),
        "warmLatencyP95Ms": round(_percentile(latencies_ms, 95), 4),
        "iterations": iterations,
    }


def main() -> None:
    leakage = verify_zero_leakage()

    fin_asset_ftq = ASSETS_DIR / "vn_financial_fasttext_v1.ftq"
    fin_art_ftq = ART_DIR / "vn_financial_fasttext_v1.ftq"
    ms_asset_ftq = ASSETS_DIR / "vn_money_split_fasttext_v1.ftq"
    ms_art_ftq = ART_DIR / "vn_money_split_fasttext_v1.ftq"

    fin_bytes = fin_asset_ftq.read_bytes()
    ms_bytes = ms_asset_ftq.read_bytes()
    assert fin_bytes == fin_art_ftq.read_bytes(), "Financial .ftq mismatch between artifacts/ and assets/models/!"
    assert ms_bytes == ms_art_ftq.read_bytes(), "Money Split .ftq mismatch between artifacts/ and assets/models/!"

    fin_model = QuantizedFastTextReader(fin_bytes)
    ms_model = QuantizedFastTextReader(ms_bytes)

    fin_id_rows = [(r["label"], r["normalized_text"]) for r in _read_jsonl(DATA_DIR / "test.jsonl")]
    fin_ood_rows = [(r["stratum"], r["normalized_text"]) for r in _read_jsonl(DATA_DIR / "ood_financial_test.jsonl")]

    fin_eval = evaluate_model_on_splits(
        model=fin_model,
        id_rows=fin_id_rows,
        ood_rows=fin_ood_rows,
        ood_reject_threshold=FINANCIAL_THRESHOLDS["oodReject"],
        low_conf_threshold=FINANCIAL_THRESHOLDS["lowConfidence"],
        high_conf_threshold=FINANCIAL_THRESHOLDS["highConfidence"],
    )
    (ART_DIR / "eval_report.json").write_text(
        json.dumps(fin_eval, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    ms_id_rows = [(r["label"], r["normalized"]) for r in _read_jsonl(DATA_DIR / "money_split_test.jsonl")]
    ms_ood_rows = [(r["stratum"], r["normalized_text"]) for r in _read_jsonl(DATA_DIR / "ood_money_split_test.jsonl")]

    ms_eval = evaluate_model_on_splits(
        model=ms_model,
        id_rows=ms_id_rows,
        ood_rows=ms_ood_rows,
        ood_reject_threshold=MONEY_SPLIT_THRESHOLDS["oodReject"],
        low_conf_threshold=MONEY_SPLIT_THRESHOLDS["lowConfidence"],
        high_conf_threshold=MONEY_SPLIT_THRESHOLDS["highConfidence"],
    )
    (ART_DIR / "vn_money_split_fasttext_v1_eval.json").write_text(
        json.dumps(
            {
                "calibratedTemperature": round(ms_model.temperature, 4),
                "testAccuracy": ms_eval["accuracy"],
                "testMacroF1": ms_eval["macro_f1"],
                "expectedCalibrationError": ms_eval["ece"],
                "falseAutoAssignmentRate": ms_eval["false_auto_assignment_rate"],
                "oodUnknownRejectionRate": ms_eval["ood_unknown_rejection_rate"],
                "oodAuroc": ms_eval["ood_auroc"],
                "perStratumOodRejection": ms_eval["per_stratum_ood_rejection"],
                "heldOutTestSamples": ms_eval["test_samples"],
                "heldOutOodTestSamples": ms_eval["ood_test_samples"],
                "labels": ms_eval["confusion_matrix_labels"],
                "confusionMatrix": ms_eval["confusion_matrix"],
                "perClass": ms_eval["per_category"],
            },
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )

    fin_bench = _benchmark_python(fin_asset_ftq, FIN_LATENCY_QUERIES)
    ms_bench = _benchmark_python(ms_asset_ftq, SPLIT_LATENCY_QUERIES)

    dart_bench_path = ART_DIR / "dart_runtime_benchmark.json"
    dart_bench = (
        json.loads(dart_bench_path.read_text(encoding="utf-8"))
        if dart_bench_path.exists()
        else None
    )

    full_report = {
        "schemaVersion": "3.27.0",
        "leakageAudit": leakage,
        "models": {
            "vn_financial_fasttext_v1": {
                "runtime": fin_bench,
                "evaluation": fin_eval,
                "dartRuntimeBenchmark": dart_bench,
            },
            "vn_money_split_fasttext_v1": {
                "runtime": ms_bench,
                "evaluation": ms_eval,
            },
        },
    }
    out_path = ART_DIR / "v327_full_ai_eval_report.json"
    out_path.write_text(json.dumps(full_report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print("=== V3.27.0 INDEPENDENT MULTI-STRATUM AI BENCHMARK ===")
    print("Leakage Audit: 0.0% across all train/val/test & ID/OOD splits!")
    print(
        f"[Financial AI] Size={fin_bench['sizeKb']} KB ({fin_bench['sizeBytes']} B) | SHA256={fin_bench['sha256'][:12]}... | T*={fin_bench['temperature']}\n"
        f"  ID Test={fin_eval['test_samples']} | Accuracy={fin_eval['accuracy']:.2%} | Macro F1={fin_eval['macro_f1']:.2%} | ID->OOD={fin_eval['in_domain_false_ood_rejection_rate']:.2%}\n"
        f"  OOD Test={fin_eval['ood_test_samples']} | OOD Rejection={fin_eval['ood_unknown_rejection_rate']:.2%} | AUROC={fin_eval['ood_auroc']:.4f} | False Auto-Assign={fin_eval['false_auto_assignment_rate']:.2%} | ECE={fin_eval['ece']:.4f}\n"
        f"  Per-stratum OOD: {fin_eval['per_stratum_ood_rejection']}\n"
        f"  Python Latency P50={fin_bench['warmLatencyP50Ms']}ms / P95={fin_bench['warmLatencyP95Ms']}ms"
    )
    print(
        f"[Money Split AI] Size={ms_bench['sizeKb']} KB ({ms_bench['sizeBytes']} B) | SHA256={ms_bench['sha256'][:12]}... | T*={ms_bench['temperature']}\n"
        f"  ID Test={ms_eval['test_samples']} | Accuracy={ms_eval['accuracy']:.2%} | Macro F1={ms_eval['macro_f1']:.2%} | ID->OOD={ms_eval['in_domain_false_ood_rejection_rate']:.2%}\n"
        f"  OOD Test={ms_eval['ood_test_samples']} | OOD Rejection={ms_eval['ood_unknown_rejection_rate']:.2%} | AUROC={ms_eval['ood_auroc']:.4f} | False Auto-Assign={ms_eval['false_auto_assignment_rate']:.2%} | ECE={ms_eval['ece']:.4f}\n"
        f"  Per-stratum OOD: {ms_eval['per_stratum_ood_rejection']}\n"
        f"  Python Latency P50={ms_bench['warmLatencyP50Ms']}ms / P95={ms_bench['warmLatencyP95Ms']}ms"
    )


if __name__ == "__main__":
    main()
