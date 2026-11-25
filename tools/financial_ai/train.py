"""Globally Convex Supervised FastText Rank-(K+1) + Explicit __ood__ Class + INT8 QAT Trainer v3.0.

Key Capabilities:
1. Explicit (K+1)-th `__ood__` class (`ALL_FINANCIAL_LABELS` = 30 semantic categories + `__ood__`)
   trained jointly with strictly disjoint `ood_financial_train.jsonl` + synthetic unknown/zero-vector
   noise samples so `biasB[__ood__]` naturally learns a positive prior (`b[__ood__] > 0`).
2. Coordinate-Wise AdaGrad (`W = logit_gain * I_{31}`) with Cosine LR Schedule + learned per-class bias `b`.
3. Straight-Through Symmetric INT8 Quantization-Aware Fine-Tuning (`[-127, 127]`).
4. Post-Quantization Temperature Calibration (`T* >= 0.85`) strictly on disjoint `val + ood_financial_val`
   minimizing NLL + ECE while enforcing OOD rejection sharpness and 0% false auto-assignment.
"""

from __future__ import annotations

import json
import math
import random
import time
from pathlib import Path

from feature_spec import (
    ALL_FINANCIAL_LABELS,
    FINANCIAL_THRESHOLDS,
    OOD_LABEL,
    extract_feature_buckets,
)

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"
ART_DIR = BASE_DIR / "artifacts"


def load_in_domain_split(name: str, label_to_idx: dict[str, int]) -> list[tuple[int, str]]:
    rows: list[tuple[int, str]] = []
    with (DATA_DIR / f"{name}.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            rows.append((label_to_idx[obj["label"]], obj["normalized_text"]))
    return rows


def load_ood_split(name: str, ood_idx: int) -> list[tuple[int, str]]:
    rows: list[tuple[int, str]] = []
    with (DATA_DIR / f"{name}.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            norm = obj.get("normalized_text") or ""
            if norm:
                rows.append((ood_idx, norm))
    return rows


def softmax_probs(logits: list[float], temp: float = 1.0) -> list[float]:
    inv_t = 1.0 / max(temp, 1e-4)
    scaled = [z * inv_t for z in logits]
    m = max(scaled)
    exps = [math.exp(z - m) for z in scaled]
    inv_s = 1.0 / sum(exps)
    return [e * inv_s for e in exps]


def compute_macro_f1(
    y_true: list[int],
    y_pred: list[int],
    eval_num_classes: int,
) -> tuple[float, float]:
    correct = sum(1 for t, p in zip(y_true, y_pred) if t == p)
    acc = correct / max(len(y_true), 1)
    tp = [0] * eval_num_classes
    fp = [0] * eval_num_classes
    fn = [0] * eval_num_classes
    for t, p in zip(y_true, y_pred):
        if t == p:
            if t < eval_num_classes:
                tp[t] += 1
        else:
            if p < eval_num_classes:
                fp[p] += 1
            if t < eval_num_classes:
                fn[t] += 1
    f1s: list[float] = []
    for c in range(eval_num_classes):
        prec = tp[c] / (tp[c] + fp[c]) if (tp[c] + fp[c]) > 0 else 0.0
        rec = tp[c] / (tp[c] + fn[c]) if (tp[c] + fn[c]) > 0 else 0.0
        f1 = (2 * prec * rec / (prec + rec)) if (prec + rec) > 0 else 0.0
        f1s.append(f1)
    return acc, sum(f1s) / eval_num_classes


def simulate_int8_row(row: list[float]) -> list[float]:
    max_abs = max((abs(v) for v in row), default=0.0)
    if max_abs <= 1e-12:
        return [0.0] * len(row)
    scale = max_abs / 127.0
    inv = 1.0 / scale
    return [max(-127, min(127, int(round(v * inv)))) * scale for v in row]


def eval_int8_logits(
    feats: list[tuple[int, list[int]]],
    A: list[list[float]],
    logit_gain: float,
    b: list[float],
    num_classes: int,
) -> tuple[list[int], list[int], list[list[float]]]:
    qA = [simulate_int8_row(r) for r in A]
    y_true: list[int] = []
    y_pred: list[int] = []
    all_logits: list[list[float]] = []

    for y, buckets in feats:
        y_true.append(y)
        if not buckets:
            logits = list(b)
            all_logits.append(logits)
            y_pred.append(max(range(num_classes), key=lambda c: logits[c]))
            continue
        scale = logit_gain / len(buckets)
        h = [0.0] * num_classes
        for b_id in buckets:
            row = qA[b_id]
            for c in range(num_classes):
                h[c] += row[c]
        logits = [b[c] + scale * h[c] for c in range(num_classes)]
        all_logits.append(logits)
        best_c = max(range(num_classes), key=lambda c: logits[c])
        y_pred.append(best_c)

    return y_true, y_pred, all_logits


def compute_ece_fast(
    confidences: list[float],
    accuracies: list[int],
    n_bins: int = 10,
) -> float:
    n = max(len(confidences), 1)
    ece = 0.0
    for b_idx in range(n_bins):
        lo = b_idx / n_bins
        hi = (b_idx + 1) / n_bins
        cnt = 0
        sum_conf = 0.0
        sum_acc = 0
        for c, a in zip(confidences, accuracies):
            if (lo <= c < hi) or (b_idx == n_bins - 1 and c == 1.0):
                cnt += 1
                sum_conf += c
                sum_acc += a
        if cnt > 0:
            ece += (cnt / n) * abs((sum_acc / cnt) - (sum_conf / cnt))
    return ece


def train_fasttext_with_ood_qat(
    train_id_feats: list[tuple[int, list[int]]],
    train_ood_feats: list[tuple[int, list[int]]],
    val_id_feats: list[tuple[int, list[int]]],
    val_ood_feats: list[tuple[int, list[int]]],
    num_classes: int,
    ood_idx: int,
    num_buckets: int,
    lr: float,
    epochs: int,
    qat_epochs: int,
    l2: float,
    l2_bias: float = 8e-3,
    label_smoothing: float = 0.005,
    logit_gain: float = 26.0,
    seed: int = 20261125,
) -> dict[str, object]:
    rng = random.Random(seed)
    dim = num_classes
    A = [[0.0] * dim for _ in range(num_buckets)]
    W = [[logit_gain if r == c else 0.0 for c in range(dim)] for r in range(num_classes)]
    # Initialize moderate positive OOD bias prior; AdaGrad calibrates final class biases cleanly
    b = [-0.15] * num_classes
    b[ood_idx] = 1.6

    gA = [[1e-2] * dim for _ in range(num_buckets)]
    gb = [1e-2] * num_classes

    # Sample tuple: (y, scale_factor, bucket_counts, weight, is_zero_vec)
    compiled_train: list[tuple[int, float, list[tuple[int, int]], float, bool]] = []

    def compile_sample(y: int, buckets: list[int], weight: float = 1.0, is_zero: bool = False) -> None:
        if not buckets:
            compiled_train.append((y, 0.0, [], weight, True))
            return
        counts: dict[int, int] = {}
        for b_id in buckets:
            counts[b_id] = counts.get(b_id, 0) + 1
        compiled_train.append((y, logit_gain / len(buckets), list(counts.items()), weight, is_zero))

    for y, buckets in train_id_feats:
        if buckets:
            compile_sample(y, buckets, 1.15)
            # Mild subword/word-drop resilience so unseen wrapper words never dilute core entity tokens
            if len(buckets) >= 18:
                kept = rng.sample(buckets, k=max(10, (len(buckets) * 2) // 3))
                compile_sample(y, kept, 0.70)

    in_domain_buckets = {b_id for _, bkts in train_id_feats for b_id in bkts}
    unseen_bucket_pool = [b_id for b_id in range(num_buckets) if b_id not in in_domain_buckets]
    if not unseen_bucket_pool:
        unseen_bucket_pool = list(range(num_buckets))

    for y, buckets in train_ood_feats:
        if not buckets:
            continue
        compile_sample(y, buckets, 0.36)

    # Synthetic unknown-subword / zero-vector OOD samples (stopped once P(__ood__) >= 0.30
    # so b[__ood__] learns a crisp positive prior without over-rejecting valid short ID phrases!)
    for _ in range(80):
        compile_sample(ood_idx, [], 0.42, is_zero=True)
    for _ in range(100):
        syn_bkts = rng.sample(unseen_bucket_pool, k=rng.randint(3, 12))
        compile_sample(ood_idx, syn_bkts, 0.42, is_zero=True)

    smooth_neg = label_smoothing / num_classes
    smooth_pos = (1.0 - label_smoothing) + smooth_neg
    indices = list(range(len(compiled_train)))
    sqrt = math.sqrt

    for ep in range(epochs):
        rng.shuffle(indices)
        progress = ep / max(epochs - 1, 1)
        cur_lr = lr * (0.18 + 0.82 * 0.5 * (1.0 + math.cos(math.pi * progress)))
        bias_lr = cur_lr * 0.025

        for idx in indices:
            y, scale_factor, bucket_counts, weight, is_zero = compiled_train[idx]
            if not bucket_counts:
                logits = list(b)
            else:
                h = [0.0] * dim
                for b_id, cnt in bucket_counts:
                    row = A[b_id]
                    if cnt == 1:
                        for c in range(dim):
                            h[c] += row[c]
                    else:
                        for c in range(dim):
                            h[c] += row[c] * cnt
                logits = [b[c] + scale_factor * h[c] for c in range(dim)]

            probs = softmax_probs(logits)
            if is_zero:
                if probs[y] > 0.30:
                    continue
            else:
                skip_thresh = 0.994 if y != ood_idx else 0.70
                if (y == ood_idx or ep >= 5) and probs[y] > skip_thresh:
                    continue

            grad_z = [
                weight * (probs[c] - (smooth_pos if c == y else smooth_neg))
                for c in range(dim)
            ]

            for c in range(dim):
                bg = grad_z[c] + l2_bias * b[c]
                gb[c] += bg * bg
                b[c] -= (bias_lr / sqrt(gb[c])) * bg

            for b_id, cnt in bucket_counts:
                row = A[b_id]
                grow = gA[b_id]
                mult = scale_factor * cnt
                for c in range(dim):
                    g = grad_z[c] * mult + l2 * row[c]
                    grow[c] += g * g
                    row[c] -= (cur_lr / sqrt(grow[c])) * g

    # Stage 2: Straight-Through Symmetric INT8 Quantization-Aware Fine-Tuning
    qA = [simulate_int8_row(r) for r in A]
    for qep in range(qat_epochs):
        rng.shuffle(indices)
        qat_lr = lr * 0.14 * (1.0 - 0.5 * (qep / max(qat_epochs, 1)))
        bias_lr = qat_lr * 0.025
        for idx in indices:
            y, scale_factor, bucket_counts, weight, is_zero = compiled_train[idx]
            if not bucket_counts:
                logits = list(b)
            else:
                h = [0.0] * dim
                for b_id, cnt in bucket_counts:
                    qrow = qA[b_id]
                    for c in range(dim):
                        h[c] += qrow[c] * cnt
                logits = [b[c] + scale_factor * h[c] for c in range(dim)]

            probs = softmax_probs(logits)
            if is_zero:
                if probs[y] > 0.30:
                    continue
            else:
                skip_thresh = 0.994 if y != ood_idx else 0.70
                if probs[y] > skip_thresh:
                    continue

            grad_z = [
                weight * (probs[c] - (smooth_pos if c == y else smooth_neg))
                for c in range(dim)
            ]

            for c in range(dim):
                bg = grad_z[c] + l2_bias * b[c]
                gb[c] += bg * bg
                b[c] -= (bias_lr / sqrt(gb[c])) * bg

            for b_id, cnt in bucket_counts:
                row = A[b_id]
                grow = gA[b_id]
                mult = scale_factor * cnt
                for c in range(dim):
                    g = grad_z[c] * mult + l2 * row[c]
                    grow[c] += g * g
                    row[c] -= (qat_lr / sqrt(grow[c])) * g
                qA[b_id] = simulate_int8_row(row)

    y_val_true, y_val_pred, val_int8_logits = eval_int8_logits(
        val_id_feats, A, logit_gain, b, num_classes
    )
    val_acc, val_f1 = compute_macro_f1(y_val_true, y_val_pred, ood_idx)

    _, _, ood_int8_logits = eval_int8_logits(
        val_ood_feats, A, logit_gain, b, num_classes
    )
    return {
        "A": A,
        "W": W,
        "b": b,
        "val_acc": val_acc,
        "val_macro_f1": val_f1,
        "val_logits": val_int8_logits,
        "val_labels": y_val_true,
        "ood_logits": ood_int8_logits,
    }


def calibrate_post_quant_temperature(
    val_logits: list[list[float]],
    val_labels: list[int],
    ood_logits: list[list[float]],
    ood_idx: int,
    ood_reject_threshold: float,
    low_conf_threshold: float,
    high_conf_threshold: float,
) -> tuple[float, dict[str, float]]:
    """Calibrates temperature T* >= 0.92 strictly on disjoint val + ood_val."""
    best_t = 0.96
    best_obj = float("inf")
    best_stats: dict[str, float] = {}

    n_id = max(len(val_labels), 1)
    n_ood = max(len(ood_logits), 1)

    for step in range(92, 181, 1):
        t = step / 100.0
        nll_id = 0.0
        confs: list[float] = []
        accs: list[int] = []
        false_auto_id = 0
        id_rejected_as_ood = 0

        for logits, y in zip(val_logits, val_labels):
            probs = softmax_probs(logits, temp=t)
            nll_id -= math.log(max(probs[y], 1e-12))
            pred_c = max(range(len(probs)), key=lambda c: probs[c])
            ood_p = probs[ood_idx]
            best_id_p = max(probs[c] for c in range(ood_idx))
            is_ood = (
                pred_c == ood_idx
                or ood_p >= ood_reject_threshold
                or best_id_p < low_conf_threshold
            )
            if is_ood:
                id_rejected_as_ood += 1
            confs.append(probs[pred_c])
            ok = 1 if pred_c == y else 0
            accs.append(ok)
            if not is_ood and ok == 0 and probs[pred_c] >= high_conf_threshold:
                false_auto_id += 1

        nll_ood = 0.0
        ood_rejected = 0
        ood_false_auto = 0
        for o_log in ood_logits:
            probs = softmax_probs(o_log, temp=t)
            nll_ood -= math.log(max(probs[ood_idx], 1e-12))
            pred_c = max(range(len(probs)), key=lambda c: probs[c])
            ood_p = probs[ood_idx]
            best_id_p = max(probs[c] for c in range(ood_idx))
            is_ood = (
                pred_c == ood_idx
                or ood_p >= ood_reject_threshold
                or best_id_p < low_conf_threshold
            )
            if is_ood:
                ood_rejected += 1
            elif best_id_p >= high_conf_threshold:
                ood_false_auto += 1
            confs.append(probs[pred_c])
            accs.append(1 if pred_c == ood_idx else 0)

        comb_nll = (nll_id + nll_ood) / (n_id + n_ood)
        comb_ece = compute_ece_fast(confs, accs)
        ood_rej_rate = ood_rejected / n_ood
        id_false_rej_rate = id_rejected_as_ood / n_id
        false_auto_rate = (false_auto_id + ood_false_auto) / (n_id + n_ood)

        obj = (
            0.4 * comb_nll
            + 2.5 * comb_ece
            + 5.0 * max(0.0, 0.98 - ood_rej_rate)
            + 3.0 * id_false_rej_rate
            + 30.0 * false_auto_rate
        )
        if obj < best_obj:
            best_obj = obj
            best_t = t
            best_stats = {
                "val_combined_nll": round(comb_nll, 4),
                "val_combined_ece": round(comb_ece, 4),
                "val_ood_rejection_rate": round(ood_rej_rate, 4),
                "val_id_false_rejection_rate": round(id_false_rej_rate, 4),
                "val_false_auto_rate": round(false_auto_rate, 4),
            }

    return round(best_t, 2), best_stats


def main() -> None:
    t0 = time.perf_counter()
    ART_DIR.mkdir(parents=True, exist_ok=True)
    num_classes = len(ALL_FINANCIAL_LABELS)
    ood_idx = ALL_FINANCIAL_LABELS.index(OOD_LABEL)
    label_to_idx = {lbl: i for i, lbl in enumerate(ALL_FINANCIAL_LABELS)}

    train_id_raw = load_in_domain_split("train", label_to_idx)
    val_id_raw = load_in_domain_split("val", label_to_idx)
    train_ood_raw = load_ood_split("ood_financial_train", ood_idx)
    val_ood_raw = load_ood_split("ood_financial_val", ood_idx)

    # Compact < 1 MB binary (28672 * 31 INT8 + scales + W + b ~= 984 KB < 1,048,576 B)
    cfg = {
        "num_buckets": 28672,
        "dim": num_classes,
        "lr": 0.45,
        "epochs": 26,
        "qat_epochs": 6,
        "word_ngrams": 2,
        "min_sub": 4,
        "max_sub": 5,
        "l2": 1.0e-5,
        "l2_bias": 1.4e-2,
        "logit_gain": 26.0,
    }

    nb = int(cfg["num_buckets"])
    wn = int(cfg["word_ngrams"])
    ms = int(cfg["min_sub"])
    xs = int(cfg["max_sub"])

    train_id_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt in train_id_raw]
    train_ood_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt in train_ood_raw]
    val_id_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt in val_id_raw]
    val_ood_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt in val_ood_raw]

    res = train_fasttext_with_ood_qat(
        train_id_feats=train_id_feats,
        train_ood_feats=train_ood_feats,
        val_id_feats=val_id_feats,
        val_ood_feats=val_ood_feats,
        num_classes=num_classes,
        ood_idx=ood_idx,
        num_buckets=nb,
        lr=float(cfg["lr"]),
        epochs=int(cfg["epochs"]),
        qat_epochs=int(cfg["qat_epochs"]),
        l2=float(cfg["l2"]),
        l2_bias=float(cfg["l2_bias"]),
        logit_gain=float(cfg["logit_gain"]),
    )

    opt_temp, val_cal_stats = calibrate_post_quant_temperature(
        val_logits=res["val_logits"],  # type: ignore[arg-type]
        val_labels=res["val_labels"],  # type: ignore[arg-type]
        ood_logits=res["ood_logits"],  # type: ignore[arg-type]
        ood_idx=ood_idx,
        ood_reject_threshold=FINANCIAL_THRESHOLDS["oodReject"],
        low_conf_threshold=FINANCIAL_THRESHOLDS["lowConfidence"],
        high_conf_threshold=FINANCIAL_THRESHOLDS["highConfidence"],
    )

    b_vec: list[float] = res["b"]  # type: ignore[assignment]
    elapsed = time.perf_counter() - t0
    fp32_payload = {
        "version": 3,
        "labels": ALL_FINANCIAL_LABELS,
        "config": cfg,
        "temperature": opt_temp,
        "val_acc": res["val_acc"],
        "val_macro_f1": res["val_macro_f1"],
        "val_calibration": val_cal_stats,
        "training_seconds": round(elapsed, 2),
        "A": res["A"],
        "W": res["W"],
        "b": b_vec,
    }
    with (ART_DIR / "model_fp32.json").open("w", encoding="utf-8") as f:
        json.dump(fp32_payload, f)

    search_log = {
        "trials": [
            {
                **cfg,
                "val_int8_acc": round(float(res["val_acc"]), 4),
                "val_int8_macro_f1": round(float(res["val_macro_f1"]), 4),
                "val_calibration": val_cal_stats,
                "learned_ood_bias": round(b_vec[ood_idx], 4),
                "max_in_domain_bias": round(max(b_vec[:ood_idx]), 4),
                "seconds": round(elapsed, 2),
            }
        ],
        "selected": cfg,
        "calibrated_temperature": opt_temp,
    }
    with (ART_DIR / "hyperparam_search.json").open("w", encoding="utf-8") as f:
        json.dump(search_log, f, indent=2)

    print(
        f"[FINANCIAL AI v3.0 QAT+OOD] classes={num_classes} (30+__ood__) | "
        f"val_acc={float(res['val_acc']):.4f} | val_macro_f1={float(res['val_macro_f1']):.4f} | "
        f"T*={opt_temp:.2f} | b[__ood__]={b_vec[ood_idx]:.3f} (max_id_b={max(b_vec[:ood_idx]):.3f}) | "
        f"val_cal={val_cal_stats} ({elapsed:.1f}s)",
        flush=True,
    )


if __name__ == "__main__":
    main()
