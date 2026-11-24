"""Exports verified quantized `.ftq` model & SHA-256 metadata JSON into Flutter `assets/models/`."""

from __future__ import annotations
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

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

    metadata = {
        "modelId": "vn_financial_fasttext_v1",
        "modelVersion": "1.0.0",
        "architecture": "FastText Supervised Subword + Word Bigram (INT8 Per-Row Quantized LFTQ v1)",
        "license": "MIT",
        "language": "vi",
        "assetPath": "assets/models/vn_financial_fasttext_v1.ftq",
        "sizeBytes": len(raw_bytes),
        "sha256": sha256_hex,
        "numClasses": len(fp32_meta["labels"]),
        "labels": fp32_meta["labels"],
        "hyperparameters": fp32_meta["config"],
        "calibratedTemperature": fp32_meta["temperature"],
        "thresholds": {
            "highConfidence": 0.78,
            "mediumConfidence": 0.52,
            "lowConfidence": 0.32,
        },
        "metrics": {
            "testAccuracy": eval_rep["accuracy"],
            "testMacroF1": eval_rep["macro_f1"],
            "expectedCalibrationError": eval_rep["ece"],
            "falseAutoAssignmentRate": eval_rep["false_auto_assignment_rate"],
        },
        "exportedAtUtc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    meta_out = FLUTTER_MODELS_DIR / "vn_financial_fasttext_v1_meta.json"
    meta_out.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (ART_DIR / "vn_financial_fasttext_v1_meta.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"Exported model -> {dst_ftq} ({len(raw_bytes):,} bytes | SHA-256: {sha256_hex})")
    print(f"Exported metadata -> {meta_out}")


if __name__ == "__main__":
    main()
