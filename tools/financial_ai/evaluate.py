"""Evaluates the quantized `.ftq` Financial AI binary model on held-out test + unseen multi-stratum OOD."""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

from feature_spec import FINANCIAL_THRESHOLDS, OOD_LABEL, extract_feature_buckets

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"
ART_DIR = BASE_DIR / "artifacts"


class QuantizedFastTextReader:
    def __init__(self, data: bytes) -> None:
        magic, ver, k, dim, buckets, wn, min_s, max_s, _, temp = struct.unpack_from(
            "<4sIIIIHHHHf", data, 0
        )
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


def compute_ece(confidences: list[float], accuracies: list[int], n_bins: int = 10) -> float:
    n = max(len(confidences), 1)
    ece = 0.0
    for b in range(n_bins):
        lo = b / n_bins
        hi = (b + 1) / n_bins
        idx = [
            i
            for i, c in enumerate(confidences)
            if (lo <= c < hi) or (b == n_bins - 1 and c == 1.0)
        ]
        if not idx:
            continue
        avg_conf = sum(confidences[i] for i in idx) / len(idx)
        avg_acc = sum(accuracies[i] for i in idx) / len(idx)
        ece += (len(idx) / n) * abs(avg_acc - avg_conf)
    return ece


def compute_auroc(scores: list[float], is_positive: list[int]) -> float:
    """Exact trapezoidal AUROC (positive = 1 for OOD, 0 for ID)."""
    n_pos = sum(is_positive)
    n_neg = len(is_positive) - n_pos
    if n_pos == 0 or n_neg == 0:
        return 1.0
    paired = sorted(zip(scores, is_positive), key=lambda x: x[0], reverse=True)
    tp = 0
    fp = 0
    prev_tpr = 0.0
    prev_fpr = 0.0
    auc = 0.0
    i = 0
    while i < len(paired):
        j = i
        while j < len(paired) and paired[j][0] == paired[i][0]:
            if paired[j][1] == 1:
                tp += 1
            else:
                fp += 1
            j += 1
        tpr = tp / n_pos
        fpr = fp / n_neg
        auc += 0.5 * (fpr - prev_fpr) * (tpr + prev_tpr)
        prev_tpr = tpr
        prev_fpr = fpr
        i = j
    return auc


def evaluate_model_on_splits(
    model: QuantizedFastTextReader,
    id_rows: list[tuple[str, str]],
    ood_rows: list[tuple[str, str]],
    ood_reject_threshold: float,
    low_conf_threshold: float,
    high_conf_threshold: float,
) -> dict[str, object]:
    label_to_idx = {lbl: i for i, lbl in enumerate(model.labels)}
    k = model.num_classes
    in_domain_labels = [lbl for lbl in model.labels if lbl != OOD_LABEL]
    ood_idx = label_to_idx.get(OOD_LABEL, -1)

    confusion = [[0] * k for _ in range(k)]
    id_confidences: list[float] = []
    id_correct_flags: list[int] = []
    all_confidences: list[float] = []
    all_correct_flags: list[int] = []
    auroc_scores: list[float] = []
    auroc_labels: list[int] = []

    false_auto_id = 0
    id_false_rejected = 0

    for true_lbl, norm in id_rows:
        true_idx = label_to_idx[true_lbl]
        ranked = model.predict(norm)
        prob_map = dict(ranked)
        top_lbl, top_prob = ranked[0]
        ood_prob = prob_map.get(OOD_LABEL, 0.0)
        in_domain_ranked = [(lbl, p) for lbl, p in ranked if lbl != OOD_LABEL]
        best_id_lbl, best_id_prob = in_domain_ranked[0]

        rejected_as_ood = (
            top_lbl == OOD_LABEL
            or ood_prob >= ood_reject_threshold
            or best_id_prob < low_conf_threshold
        )
        pred_lbl = OOD_LABEL if rejected_as_ood and ood_idx >= 0 else best_id_lbl
        pred_idx = label_to_idx[pred_lbl]
        confusion[true_idx][pred_idx] += 1

        is_ok = 1 if (not rejected_as_ood and best_id_lbl == true_lbl) else 0
        if rejected_as_ood:
            id_false_rejected += 1
        elif best_id_prob >= high_conf_threshold and is_ok == 0:
            false_auto_id += 1

        id_confidences.append(top_prob)
        id_correct_flags.append(is_ok)
        all_confidences.append(top_prob)
        all_correct_flags.append(is_ok)
        auroc_scores.append(1.0 - best_id_prob)
        auroc_labels.append(0)

    per_stratum: dict[str, dict[str, float | int]] = {}
    ood_rejected = 0
    false_auto_ood = 0

    for stratum, norm in ood_rows:
        ranked = model.predict(norm)
        prob_map = dict(ranked)
        top_lbl, top_prob = ranked[0]
        ood_prob = prob_map.get(OOD_LABEL, 0.0)
        in_domain_ranked = [(lbl, p) for lbl, p in ranked if lbl != OOD_LABEL]
        best_id_lbl, best_id_prob = in_domain_ranked[0]

        rejected_as_ood = (
            top_lbl == OOD_LABEL
            or ood_prob >= ood_reject_threshold
            or best_id_prob < low_conf_threshold
        )
        if ood_idx >= 0:
            pred_idx = ood_idx if rejected_as_ood else label_to_idx[best_id_lbl]
            confusion[ood_idx][pred_idx] += 1

        if rejected_as_ood:
            ood_rejected += 1
        elif best_id_prob >= high_conf_threshold:
            false_auto_ood += 1

        s_entry = per_stratum.setdefault(stratum, {"total": 0, "rejected": 0})
        s_entry["total"] = int(s_entry["total"]) + 1
        if rejected_as_ood:
            s_entry["rejected"] = int(s_entry["rejected"]) + 1

        all_confidences.append(top_prob)
        all_correct_flags.append(1 if rejected_as_ood else 0)
        auroc_scores.append(1.0 - best_id_prob)
        auroc_labels.append(1)

    for stratum, vals in per_stratum.items():
        tot = max(int(vals["total"]), 1)
        rej = int(vals["rejected"])
        vals["rejection_rate"] = round(rej / tot, 4)

    per_class: dict[str, dict[str, float | int]] = {}
    in_domain_f1s: list[float] = []
    for c, lbl in enumerate(model.labels):
        tp = confusion[c][c]
        fp = sum(confusion[r][c] for r in range(k) if r != c)
        fn = sum(confusion[c][col] for col in range(k) if col != c)
        prec = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        rec = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        f1 = (2 * prec * rec / (prec + rec)) if (prec + rec) > 0 else 0.0
        if lbl != OOD_LABEL:
            in_domain_f1s.append(f1)
        per_class[lbl] = {
            "precision": round(prec, 4),
            "recall": round(rec, 4),
            "f1": round(f1, 4),
            "support": tp + fn,
        }

    total_id = max(len(id_rows), 1)
    total_ood = max(len(ood_rows), 1)
    total_all = max(len(id_rows) + len(ood_rows), 1)

    accuracy = sum(id_correct_flags) / total_id
    macro_f1 = sum(in_domain_f1s) / max(len(in_domain_labels), 1)
    ece_combined = compute_ece(all_confidences, all_correct_flags)
    ece_id_only = compute_ece(id_confidences, id_correct_flags)
    false_auto_rate = (false_auto_id + false_auto_ood) / total_all
    ood_rejection_rate = ood_rejected / total_ood
    auroc = compute_auroc(auroc_scores, auroc_labels)

    return {
        "test_samples": len(id_rows),
        "ood_test_samples": len(ood_rows),
        "accuracy": round(accuracy, 4),
        "macro_f1": round(macro_f1, 4),
        "ece": round(ece_combined, 4),
        "ece_in_domain_only": round(ece_id_only, 4),
        "high_confidence_threshold": high_conf_threshold,
        "low_confidence_threshold": low_conf_threshold,
        "ood_reject_threshold": ood_reject_threshold,
        "false_auto_assignment_rate": round(false_auto_rate, 4),
        "id_false_auto_assignments": false_auto_id,
        "ood_false_auto_assignments": false_auto_ood,
        "in_domain_false_ood_rejection_rate": round(id_false_rejected / total_id, 4),
        "ood_unknown_rejection_rate": round(ood_rejection_rate, 4),
        "ood_auroc": round(auroc, 4),
        "per_stratum_ood_rejection": per_stratum,
        "per_category": per_class,
        "confusion_matrix_labels": model.labels,
        "confusion_matrix": confusion,
    }


def main() -> None:
    ftq_bytes = (ART_DIR / "vn_financial_fasttext_v1.ftq").read_bytes()
    model = QuantizedFastTextReader(ftq_bytes)

    id_rows: list[tuple[str, str]] = []
    with (DATA_DIR / "test.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            id_rows.append((obj["label"], obj["normalized_text"]))

    ood_rows: list[tuple[str, str]] = []
    with (DATA_DIR / "ood_financial_test.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            ood_rows.append((obj.get("stratum", "unknown"), obj["normalized_text"]))

    report = evaluate_model_on_splits(
        model=model,
        id_rows=id_rows,
        ood_rows=ood_rows,
        ood_reject_threshold=FINANCIAL_THRESHOLDS["oodReject"],
        low_conf_threshold=FINANCIAL_THRESHOLDS["lowConfidence"],
        high_conf_threshold=FINANCIAL_THRESHOLDS["highConfidence"],
    )

    with (ART_DIR / "eval_report.json").open("w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(
        f"[FINANCIAL TEST EVAL] ID={report['test_samples']} | OOD={report['ood_test_samples']} | "
        f"Accuracy={report['accuracy']:.4f} | Macro F1={report['macro_f1']:.4f} | "
        f"ECE={report['ece']:.4f} | False Auto-Assign={report['false_auto_assignment_rate']:.4f} | "
        f"OOD Rejection={report['ood_unknown_rejection_rate']:.2%} | AUROC={report['ood_auroc']:.4f}"
    )


if __name__ == "__main__":
    main()
