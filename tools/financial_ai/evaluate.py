"""Evaluates the quantized `.ftq` binary model on the held-out test split + OOD unknown rejection."""

from __future__ import annotations
import json
import math
import struct
from pathlib import Path
from feature_spec import extract_feature_buckets, normalize_for_classifier

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"
ART_DIR = BASE_DIR / "artifacts"


class QuantizedFastTextReader:
    def __init__(self, data: bytes) -> None:
        magic, ver, k, dim, buckets, wn, min_s, max_s, _, temp = struct.unpack_from("<4sIIIIHHHHf", data, 0)
        if magic != b"LFTQ" or ver != 1:
            raise ValueError("Invalid LFTQ header")
        self.num_classes = k
        self.dim = dim
        self.num_buckets = buckets
        self.word_ngrams = wn
        self.min_sub = min_s
        self.max_sub = max_s
        self.temperature = temp

        offset = 32
        self.labels: list[str] = []
        for _ in range(k):
            (ln,) = struct.unpack_from("<H", data, offset)
            offset += 2
            self.labels.append(data[offset : offset + ln].decode("utf-8"))
            offset += ln

        self.scales = list(struct.unpack_from(f"<{buckets}f", data, offset))
        offset += buckets * 4

        # Signed int8 weights
        self.q_a = struct.unpack_from(f"<{buckets * dim}b", data, offset)
        offset += buckets * dim

        self.w = struct.unpack_from(f"<{k * dim}f", data, offset)
        offset += k * dim * 4
        self.b = struct.unpack_from(f"<{k}f", data, offset)

    def predict(self, normalized_text: str) -> list[tuple[str, float]]:
        b_ids = extract_feature_buckets(
            normalized_text,
            num_buckets=self.num_buckets,
            word_ngrams=self.word_ngrams,
            min_subword=self.min_sub,
            max_subword=self.max_sub,
        )
        if not b_ids:
            u = 1.0 / self.num_classes
            return [(lbl, u) for lbl in self.labels]

        dim = self.dim
        h = [0.0] * dim
        for b_id in b_ids:
            sc = self.scales[b_id]
            if sc == 0.0:
                continue
            base = b_id * dim
            for d in range(dim):
                h[d] += self.q_a[base + d] * sc
        inv_len = 1.0 / len(b_ids)
        for d in range(dim):
            h[d] *= inv_len

        inv_t = 1.0 / max(self.temperature, 1e-4)
        logits: list[float] = []
        for c in range(self.num_classes):
            w_base = c * dim
            s = self.b[c]
            for d in range(dim):
                s += self.w[w_base + d] * h[d]
            logits.append(s * inv_t)

        m = max(logits)
        exps = [math.exp(z - m) for z in logits]
        total = sum(exps)
        probs = [e / total for e in exps]
        ranked = sorted(zip(self.labels, probs), key=lambda x: x[1], reverse=True)
        return ranked


OOD_UNKNOWN_SAMPLES = [
    "alo một hai ba bốn",
    "thời tiết hôm nay trời mưa to quá",
    "nhớ mang ô khi ra ngoài nhé",
    "xyz qwerty asdfgh",
    "họp nhóm lúc ba giờ chiều phòng zoom",
    "chúc ngủ ngon hẹn mai gặp lại",
]


def compute_ece(confidences: list[float], accuracies: list[int], n_bins: int = 10) -> float:
    n = max(len(confidences), 1)
    ece = 0.0
    for b in range(n_bins):
        lo = b / n_bins
        hi = (b + 1) / n_bins
        idx = [i for i, c in enumerate(confidences) if (lo <= c < hi) or (b == n_bins - 1 and c == 1.0)]
        if not idx:
            continue
        avg_conf = sum(confidences[i] for i in idx) / len(idx)
        avg_acc = sum(accuracies[i] for i in idx) / len(idx)
        ece += (len(idx) / n) * abs(avg_acc - avg_conf)
    return ece


def main() -> None:
    ftq_bytes = (ART_DIR / "vn_financial_fasttext_v1.ftq").read_bytes()
    model = QuantizedFastTextReader(ftq_bytes)
    label_to_idx = {l: i for i, l in enumerate(model.labels)}
    k = model.num_classes

    confusion = [[0] * k for _ in range(k)]
    confidences: list[float] = []
    correct_flags: list[int] = []
    high_conf_threshold = 0.78
    false_auto_assign = 0
    total = 0

    with (DATA_DIR / "test.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            true_lbl = obj["label"]
            true_idx = label_to_idx[true_lbl]
            ranked = model.predict(obj["normalized_text"])
            pred_lbl, top_prob = ranked[0]
            pred_idx = label_to_idx[pred_lbl]

            confusion[true_idx][pred_idx] += 1
            is_ok = 1 if pred_idx == true_idx else 0
            confidences.append(top_prob)
            correct_flags.append(is_ok)
            if top_prob >= high_conf_threshold and is_ok == 0:
                false_auto_assign += 1
            total += 1

    per_class: dict[str, dict[str, float]] = {}
    f1s: list[float] = []
    for c, lbl in enumerate(model.labels):
        tp = confusion[c][c]
        fp = sum(confusion[r][c] for r in range(k) if r != c)
        fn = sum(confusion[c][col] for col in range(k) if col != c)
        prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        rec = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = (2 * prec * rec / (prec + rec)) if (prec + rec) > 0 else 0.0
        f1s.append(f1)
        per_class[lbl] = {
            "precision": round(prec, 4),
            "recall": round(rec, 4),
            "f1": round(f1, 4),
            "support": tp + fn,
        }

    accuracy = sum(correct_flags) / max(total, 1)
    macro_f1 = sum(f1s) / k
    ece = compute_ece(confidences, correct_flags)
    false_auto_rate = false_auto_assign / max(total, 1)

    # Evaluate OOD / Unknown rejection (rejected when top_prob < 0.45)
    ood_rejected = 0
    for s in OOD_UNKNOWN_SAMPLES:
        norm = normalize_for_classifier(s)
        _, p = model.predict(norm)[0]
        if p < 0.45:
            ood_rejected += 1
    ood_rejection_rate = ood_rejected / len(OOD_UNKNOWN_SAMPLES)

    report = {
        "test_samples": total,
        "accuracy": round(accuracy, 4),
        "macro_f1": round(macro_f1, 4),
        "ece": round(ece, 4),
        "high_confidence_threshold": high_conf_threshold,
        "false_auto_assignment_rate": round(false_auto_rate, 4),
        "ood_unknown_rejection_rate": round(ood_rejection_rate, 4),
        "per_category": per_class,
        "confusion_matrix_labels": model.labels,
        "confusion_matrix": confusion,
    }
    with (ART_DIR / "eval_report.json").open("w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(
        f"[TEST EVALUATION] Samples={total} | Accuracy={accuracy:.4f} | Macro F1={macro_f1:.4f} "
        f"| ECE={ece:.4f} | False Auto-Assign={false_auto_rate:.4f} | OOD Rejection={ood_rejection_rate:.2%}"
    )


if __name__ == "__main__":
    main()
