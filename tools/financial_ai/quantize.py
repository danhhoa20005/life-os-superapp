"""Per-Row Symmetric INT8 Quantizer producing compact `LFTQ` v1 binary model."""

from __future__ import annotations
import json
import struct
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
ART_DIR = BASE_DIR / "artifacts"


def quantize_to_lftq_bytes(fp32_model: dict[str, object]) -> bytes:
    labels: list[str] = fp32_model["labels"]  # type: ignore[assignment]
    cfg: dict[str, int] = fp32_model["config"]  # type: ignore[assignment]
    temp = float(fp32_model["temperature"])  # type: ignore[arg-type]
    A: list[list[float]] = fp32_model["A"]  # type: ignore[assignment]
    W: list[list[float]] = fp32_model["W"]  # type: ignore[assignment]
    b: list[float] = fp32_model["b"]  # type: ignore[assignment]

    num_classes = len(labels)
    num_buckets = len(A)
    dim = len(A[0])
    word_ngrams = int(cfg["word_ngrams"])
    min_sub = int(cfg["min_sub"])
    max_sub = int(cfg["max_sub"])

    buf = bytearray()
    # 32-byte LFTQ v1 Little-Endian Header
    buf.extend(
        struct.pack(
            "<4sIIIIHHHHf",
            b"LFTQ",
            1,
            num_classes,
            dim,
            num_buckets,
            word_ngrams,
            min_sub,
            max_sub,
            0,
            temp,
        )
    )

    # Label table
    for lbl in labels:
        raw = lbl.encode("utf-8")
        buf.extend(struct.pack("<H", len(raw)))
        buf.extend(raw)

    # Per-row symmetric INT8 quantization for Embedding Matrix A [B x D]
    scales: list[float] = []
    q_weights = bytearray()
    for row in A:
        max_abs = max((abs(v) for v in row), default=0.0)
        scale = (max_abs / 127.0) if max_abs > 1e-12 else 0.0
        scales.append(scale)
        if scale == 0.0:
            q_weights.extend(b"\x00" * dim)
        else:
            inv = 1.0 / scale
            for v in row:
                q = int(round(v * inv))
                if q > 127:
                    q = 127
                elif q < -127:
                    q = -127
                q_weights.append(q & 0xFF)

    buf.extend(struct.pack(f"<{num_buckets}f", *scales))
    buf.extend(q_weights)

    # Output Classifier W [K x D] and Bias b [K] in float32
    flat_w = [v for row in W for v in row]
    buf.extend(struct.pack(f"<{num_classes * dim}f", *flat_w))
    buf.extend(struct.pack(f"<{num_classes}f", *b))
    return bytes(buf)


def main() -> None:
    fp32_path = ART_DIR / "model_fp32.json"
    with fp32_path.open("r", encoding="utf-8") as f:
        fp32_model = json.load(f)

    binary_bytes = quantize_to_lftq_bytes(fp32_model)
    out_ftq = ART_DIR / "vn_financial_fasttext_v1.ftq"
    out_ftq.write_bytes(binary_bytes)

    fp32_est_bytes = (
        len(fp32_model["A"]) * len(fp32_model["A"][0]) * 4
        + len(fp32_model["W"]) * len(fp32_model["W"][0]) * 4
    )
    ratio = fp32_est_bytes / max(len(binary_bytes), 1)
    print(
        f"Quantized LFTQ v1 binary saved: {out_ftq} | Size: {len(binary_bytes):,} bytes "
        f"({len(binary_bytes) / 1024:.1f} KB, {ratio:.2f}x smaller than FP32 raw tensors)"
    )


if __name__ == "__main__":
    main()
