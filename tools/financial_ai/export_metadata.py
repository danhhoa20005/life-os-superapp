"""Exports verified quantized `.ftq` model & SHA-256 metadata JSON into Flutter `assets/models/`."""

from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from feature_spec import FINANCIAL_THRESHOLDS, OOD_LABEL, SEMANTIC_LABELS

BASE_DIR = Path(__file__).resolve().parent
ART_DIR = BASE_DIR / "artifacts"
REPO_ROOT = BASE_DIR.parent.parent
FLUTTER_MODELS_DIR = REPO_ROOT / "assets" / "models"


def main() -> None:
    FLUTTER_MODELS_DIR.mkdir(parents=True, exist_ok=True)
    src_ftq = ART_DIR / "vn_financial_fasttext_v1.ftq"
    dst_ftq = FLUTTER_MODELS_DIR / "vn_financial_fasttext_v1.ftq"
    shutil.copy2(src_ftq, dst_ftq)

    raw_bytes = dst_ftq.read_bytes()
    sha256_hex = hashlib.sha256(raw_bytes).hexdigest()

    fp32_meta = json.loads((ART_DIR / "model_fp32.json").read_text(encoding="utf-8"))
    eval_rep = json.loads((ART_DIR / "eval_report.json").read_text(encoding="utf-8"))

    labels: list[str] = list(fp32_meta["labels"])
    in_domain_count = sum(1 for lbl in labels if lbl != OOD_LABEL)

    metadata = {
        "modelId": "vn_financial_fasttext_v1",
        "modelVersion": "3.0.0",
        "architecture": "FastText QAT Subword + Word Bigram + Explicit __ood__ Class (INT8 LFTQ v1)",
        "license": "MIT",
        "language": "vi",
        "assetPath": "assets/models/vn_financial_fasttext_v1.ftq",
        "sizeBytes": len(raw_bytes),
        "sha256": sha256_hex,
        "numClasses": in_domain_count if in_domain_count > 0 else len(SEMANTIC_LABELS),
        "totalOutputClasses": len(labels),
        "hasExplicitOodClass": OOD_LABEL in labels,
        "oodLabel": OOD_LABEL,
        "labels": labels,
        "hyperparameters": fp32_meta["config"],
        "calibratedTemperature": fp32_meta["temperature"],
        "thresholds": FINANCIAL_THRESHOLDS,
        "metrics": {
            "testAccuracy": eval_rep["accuracy"],
            "testMacroF1": eval_rep["macro_f1"],
            "expectedCalibrationError": eval_rep["ece"],
            "falseAutoAssignmentRate": eval_rep["false_auto_assignment_rate"],
            "oodUnknownRejectionRate": eval_rep["ood_unknown_rejection_rate"],
            "oodAuroc": eval_rep.get("ood_auroc", 0.0),
            "heldOutTestSamples": eval_rep["test_samples"],
            "heldOutOodTestSamples": eval_rep.get("ood_test_samples", 0),
        },
        "exportedAtUtc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    meta_out = FLUTTER_MODELS_DIR / "vn_financial_fasttext_v1_meta.json"
    meta_text = json.dumps(metadata, indent=2, ensure_ascii=False) + "\n"
    meta_out.write_text(meta_text, encoding="utf-8")
    (ART_DIR / "vn_financial_fasttext_v1_meta.json").write_text(
        meta_text,
        encoding="utf-8",
    )

    print(f"Exported model -> {dst_ftq} ({len(raw_bytes):,} bytes | SHA-256: {sha256_hex})")
    print(f"Exported metadata -> {meta_out}")


if __name__ == "__main__":
    main()
