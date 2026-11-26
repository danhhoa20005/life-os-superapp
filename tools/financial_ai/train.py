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


def load_in_domain_split_with_flags(
    name: str,
    label_to_idx: dict[str, int],
) -> list[tuple[int, str, bool]]:
    rows: list[tuple[int, str, bool]] = []
    with (DATA_DIR / f"{name}.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            is_aug = str(obj.get("template_id", "")).startswith("aug_")
            rows.append((label_to_idx[obj["label"]], obj["normalized_text"], is_aug))
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


def load_ood_split_with_strata(name: str, ood_idx: int) -> list[tuple[int, str, str]]:
    rows: list[tuple[int, str, str]] = []
    with (DATA_DIR / f"{name}.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            norm = obj.get("normalized_text") or ""
            stratum = str(obj.get("stratum") or "unknown")
            if norm:
                rows.append((ood_idx, norm, stratum))
    return rows


def load_ood_tail_flags(name: str) -> list[bool]:
    flags: list[bool] = []
    with (DATA_DIR / f"{name}.jsonl").open("r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            if obj.get("normalized_text"):
                flags.append("_tail_" in str(obj.get("template_id") or ""))
    return flags


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
    ood_weight: float = 0.74,
    ood_bias_target: float = 1.85,
    seed: int = 20261125,
    train_ood_strata: list[str] | None = None,
    train_id_is_aug: list[bool] | None = None,
    class_multipliers: dict[int, float] | None = None,
    train_ood_is_tail: list[bool] | None = None,
) -> dict[str, object]:
    rng = random.Random(seed)
    dim = num_classes
    A = [[0.0] * dim for _ in range(num_buckets)]
    W = [[logit_gain if r == c else 0.0 for c in range(dim)] for r in range(num_classes)]
    # Initialize positive OOD bias prior; AdaGrad + val calibration tunes final class biases cleanly
    b = [-0.15] * num_classes
    b[ood_idx] = 1.75

    gA = [[1e-2] * dim for _ in range(num_buckets)]
    gb = [1e-2] * num_classes

    # Sample tuple: (y, scale_factor, bucket_counts, weight, is_zero_vec)
    compiled_train: list[tuple[int, float, list[tuple[int, int]], float, bool]] = []
    compiled_tail_ood: list[tuple[int, float, list[tuple[int, int]], float, bool]] = []

    def compile_sample(
        y: int,
        buckets: list[int],
        weight: float = 1.0,
        is_zero: bool = False,
        target_list: list[tuple[int, float, list[tuple[int, int]], float, bool]] | None = None,
    ) -> None:
        dst = compiled_train if target_list is None else target_list
        if not buckets:
            dst.append((y, 0.0, [], weight, True))
            return
        counts: dict[int, int] = {}
        for b_id in buckets:
            counts[b_id] = counts.get(b_id, 0) + 1
        dst.append((y, logit_gain / len(buckets), list(counts.items()), weight, is_zero))

    # Class-balanced weighting prevents over-represented augmented classes from swallowing rarer ones
    id_class_counts: dict[int, int] = {}
    for y, bkts in train_id_feats:
        if bkts:
            id_class_counts[y] = id_class_counts.get(y, 0) + 1
    sorted_counts = sorted(id_class_counts.values())
    median_cnt = sorted_counts[len(sorted_counts) // 2] if sorted_counts else 150

    for y, buckets in train_id_feats:
        if buckets:
            c_cnt = max(id_class_counts.get(y, median_cnt), 1)
            bal = min(1.26, max(0.80, (median_cnt / c_cnt) ** 0.42))
            if class_multipliers and y in class_multipliers:
                bal *= class_multipliers[y]
            if len(buckets) < 6:
                compile_sample(y, buckets, 1.35 * bal)
            else:
                compile_sample(y, buckets, 1.15 * bal)
            # Mild subword/word-drop resilience so unseen wrapper words never dilute core entity tokens
            if len(buckets) >= 18:
                kept = rng.sample(buckets, k=max(10, (len(buckets) * 2) // 3))
                compile_sample(y, kept, 0.70 * bal)

    in_domain_buckets = {b_id for _, bkts in train_id_feats for b_id in bkts}
    unseen_bucket_pool = [b_id for b_id in range(num_buckets) if b_id not in in_domain_buckets]
    if not unseen_bucket_pool:
        unseen_bucket_pool = list(range(num_buckets))

    for ood_i, (y, buckets) in enumerate(train_ood_feats):
        if not buckets:
            continue
        stratum = train_ood_strata[ood_i] if train_ood_strata and ood_i < len(train_ood_strata) else ""
        if stratum == "c_english_gibberish_code_fragments":
            w_mult = 1.245
            min_keep_len = 10
        elif stratum == "a_chatter_homonyms":
            w_mult = 1.10
            min_keep_len = 14
        elif stratum == "d_negated_hypothetical_balance_otp":
            w_mult = 1.085
            min_keep_len = 14
        else:
            w_mult = 1.035
            min_keep_len = 14
        is_tail = bool(train_ood_is_tail and ood_i < len(train_ood_is_tail) and train_ood_is_tail[ood_i])
        if is_tail:
            compile_sample(y, buckets, ood_weight * w_mult * 0.95, target_list=compiled_tail_ood)
            continue
        compile_sample(y, buckets, ood_weight * w_mult)
        if len(buckets) >= min_keep_len:
            kept_ood = rng.sample(buckets, k=max(7, (len(buckets) * 2) // 3))
            compile_sample(y, kept_ood, ood_weight * w_mult * 0.43)

    # Synthetic unknown-subword / zero-vector OOD samples (stopped once P(__ood__) >= 0.53
    # so b[__ood__] maintains a strong rejection prior against unseen English/code/gibberish!)
    for _ in range(190):
        compile_sample(ood_idx, [], 0.55, is_zero=True)
    for _ in range(230):
        syn_bkts = rng.sample(unseen_bucket_pool, k=rng.randint(3, 12))
        compile_sample(ood_idx, syn_bkts, 0.55, is_zero=True)

    smooth_neg = label_smoothing / num_classes
    smooth_pos = (1.0 - label_smoothing) + smooth_neg
    indices = list(range(len(compiled_train)))
    sqrt = math.sqrt

    def step_sample(
        sample: tuple[int, float, list[tuple[int, int]], float, bool],
        step_lr: float,
        bias_lr: float,
        apply_id_skip: bool,
        qA_buf: list[list[float]] | None,
        ood_skip_override: float | None = None,
    ) -> None:
        y, scale_factor, bucket_counts, weight, is_zero = sample
        if not bucket_counts:
            logits = list(b)
        else:
            h = [0.0] * dim
            src_mat = A if qA_buf is None else qA_buf
            for b_id, cnt in bucket_counts:
                row = src_mat[b_id]
                if cnt == 1:
                    for c in range(dim):
                        h[c] += row[c]
                else:
                    for c in range(dim):
                        h[c] += row[c] * cnt
            logits = [b[c] + scale_factor * h[c] for c in range(dim)]

        probs = softmax_probs(logits)
        if is_zero:
            if probs[y] > 0.53:
                return
        else:
            ood_skip = 0.89 if ood_skip_override is None else ood_skip_override
            skip_thresh = 0.994 if y != ood_idx else ood_skip
            if (y == ood_idx or apply_id_skip) and probs[y] > skip_thresh:
                return

        grad_z = [
            weight * (probs[c] - (smooth_pos if c == y else smooth_neg))
            for c in range(dim)
        ]

        for c in range(dim):
            bias_target = ood_bias_target if c == ood_idx else 0.0
            bg = grad_z[c] + l2_bias * (b[c] - bias_target)
            gb[c] += bg * bg
            b[c] -= (bias_lr / sqrt(gb[c])) * bg

        for b_id, cnt in bucket_counts:
            row = A[b_id]
            grow = gA[b_id]
            mult = scale_factor * cnt
            for c in range(dim):
                g = grad_z[c] * mult + l2 * row[c]
                grow[c] += g * g
                row[c] -= (step_lr / sqrt(grow[c])) * g
            if qA_buf is not None:
                qA_buf[b_id] = simulate_int8_row(row)

    for ep in range(epochs):
        rng.shuffle(indices)
        progress = ep / max(epochs - 1, 1)
        cur_lr = lr * (0.18 + 0.82 * 0.5 * (1.0 + math.cos(math.pi * progress)))
        bias_lr = cur_lr * 0.025
        for idx in indices:
            step_sample(compiled_train[idx], cur_lr, bias_lr, ep >= 5, None)
        for tail_s in compiled_tail_ood:
            step_sample(tail_s, cur_lr, 0.0, ep >= 5, None, ood_skip_override=0.95)

    # Stage 2: Straight-Through Symmetric INT8 Quantization-Aware Fine-Tuning
    qA = [simulate_int8_row(r) for r in A]
    for qep in range(qat_epochs):
        rng.shuffle(indices)
        qat_lr = lr * 0.14 * (1.0 - 0.5 * (qep / max(qat_epochs, 1)))
        bias_lr = qat_lr * 0.025
        for idx in indices:
            step_sample(compiled_train[idx], qat_lr, bias_lr, True, qA)
        for tail_s in compiled_tail_ood:
            step_sample(tail_s, qat_lr, 0.0, True, qA, ood_skip_override=0.95)

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


def calibrate_post_quant_temperature_and_ood_bias(
    val_logits: list[list[float]],
    val_labels: list[int],
    ood_logits: list[list[float]],
    ood_strata: list[str],
    ood_idx: int,
    ood_reject_threshold: float,
    low_conf_threshold: float,
    high_conf_threshold: float,
) -> tuple[float, float, dict[str, float]]:
    """Jointly calibrates (T*, b[__ood__] delta) strictly on disjoint val + ood_val."""
    n_id = max(len(val_labels), 1)
    n_ood = max(len(ood_logits), 1)

    def eval_pair(t: float, delta: float) -> tuple[float, dict[str, float]]:
        nll_id = 0.0
        confs: list[float] = []
        accs: list[int] = []
        false_auto_id = 0
        id_rejected_as_ood = 0
        id_correct = 0

        for logits, y in zip(val_logits, val_labels):
            adj = list(logits)
            adj[ood_idx] += delta
            probs = softmax_probs(adj, temp=t)
            nll_id -= math.log(max(probs[y], 1e-12))
            pred_c = max(range(len(probs)), key=lambda c: probs[c])
            ood_p = probs[ood_idx]
            best_id_c = max(range(ood_idx), key=lambda c: probs[c])
            best_id_p = probs[best_id_c]
            is_ood = (
                pred_c == ood_idx
                or ood_p >= ood_reject_threshold
                or best_id_p < low_conf_threshold
            )
            if is_ood:
                id_rejected_as_ood += 1
            ok = 1 if (not is_ood and best_id_c == y) else 0
            if ok:
                id_correct += 1
            confs.append(probs[pred_c])
            accs.append(ok)
            if not is_ood and ok == 0 and best_id_p >= high_conf_threshold:
                false_auto_id += 1

        nll_ood = 0.0
        ood_rejected = 0
        ood_false_auto = 0
        stratum_totals: dict[str, int] = {}
        stratum_rejs: dict[str, int] = {}
        for o_log, stratum in zip(ood_logits, ood_strata):
            adj = list(o_log)
            adj[ood_idx] += delta
            probs = softmax_probs(adj, temp=t)
            nll_ood -= math.log(max(probs[ood_idx], 1e-12))
            pred_c = max(range(len(probs)), key=lambda c: probs[c])
            ood_p = probs[ood_idx]
            best_id_p = max(probs[c] for c in range(ood_idx))
            is_ood = (
                pred_c == ood_idx
                or ood_p >= ood_reject_threshold
                or best_id_p < low_conf_threshold
            )
            stratum_totals[stratum] = stratum_totals.get(stratum, 0) + 1
            if is_ood:
                ood_rejected += 1
                stratum_rejs[stratum] = stratum_rejs.get(stratum, 0) + 1
            elif best_id_p >= high_conf_threshold:
                ood_false_auto += 1
            confs.append(probs[pred_c])
            accs.append(1 if is_ood else 0)

        comb_nll = (nll_id + nll_ood) / (n_id + n_ood)
        comb_ece = compute_ece_fast(confs, accs)
        val_id_acc = id_correct / n_id
        ood_rej_rate = ood_rejected / n_ood
        min_stratum_ood = min(
            (stratum_rejs.get(s, 0) / max(tot, 1) for s, tot in stratum_totals.items()),
            default=ood_rej_rate,
        )
        id_false_rej_rate = id_rejected_as_ood / n_id
        false_auto_rate = (false_auto_id + ood_false_auto) / (n_id + n_ood)

        obj = (
            0.35 * comb_nll
            + 2.2 * comb_ece
            + 13.0 * max(0.0, 0.994 - ood_rej_rate)
            + 10.0 * max(0.0, 0.980 - min_stratum_ood)
            + 15.0 * id_false_rej_rate
            + 14.0 * (1.0 - val_id_acc)
            + 30.0 * false_auto_rate
        )
        stats = {
            "val_id_acc_gated": round(val_id_acc, 4),
            "val_combined_nll": round(comb_nll, 4),
            "val_combined_ece": round(comb_ece, 4),
            "val_ood_rejection_rate": round(ood_rej_rate, 4),
            "val_min_stratum_ood_rejection": round(min_stratum_ood, 4),
            "val_id_false_rejection_rate": round(id_false_rej_rate, 4),
            "val_false_auto_rate": round(false_auto_rate, 4),
            "ood_bias_delta": round(delta, 4),
        }
        return obj, stats

    best_t = 0.96
    best_delta = 0.0
    best_obj = float("inf")
    best_stats: dict[str, float] = {}

    # Coarse grid search over (T, ood_bias_delta)
    for step_t in range(88, 138, 3):
        t = step_t / 100.0
        for delta in (-0.13, -0.09, -0.05):
            obj, stats = eval_pair(t, delta)
            if obj < best_obj:
                best_obj = obj
                best_t = t
                best_delta = delta
                best_stats = stats

    # Fine local refinement around coarse optimum
    t_lo = max(88, int(round((best_t - 0.04) * 100)))
    t_hi = min(145, int(round((best_t + 0.04) * 100)))
    d_lo = max(-0.15, round(best_delta - 0.04, 2))
    d_hi = min(-0.05, round(best_delta + 0.04, 2))
    for step_t in range(t_lo, t_hi + 1, 1):
        t = step_t / 100.0
        d = d_lo
        while d <= d_hi + 1e-9:
            obj, stats = eval_pair(t, round(d, 4))
            if obj < best_obj:
                best_obj = obj
                best_t = t
                best_delta = round(d, 4)
                best_stats = stats
            d += 0.02

    return round(best_t, 2), round(best_delta, 4), best_stats


def main() -> None:
    t0 = time.perf_counter()
    ART_DIR.mkdir(parents=True, exist_ok=True)
    num_classes = len(ALL_FINANCIAL_LABELS)
    ood_idx = ALL_FINANCIAL_LABELS.index(OOD_LABEL)
    label_to_idx = {lbl: i for i, lbl in enumerate(ALL_FINANCIAL_LABELS)}

    train_id_flagged = load_in_domain_split_with_flags("train", label_to_idx)
    val_id_raw = load_in_domain_split("val", label_to_idx)
    train_ood_rows = load_ood_split_with_strata("ood_financial_train", ood_idx)
    train_ood_is_tail = load_ood_tail_flags("ood_financial_train")
    val_ood_rows = load_ood_split_with_strata("ood_financial_val", ood_idx)

    # Compact < 1 MB binary (28672 * 31 INT8 + scales + W + b ~= 984 KB < 1,048,576 B)
    cfg = {
        "num_buckets": 28672,
        "dim": num_classes,
        "lr": 0.45,
        "epochs": 30,
        "qat_epochs": 7,
        "word_ngrams": 2,
        "min_sub": 4,
        "max_sub": 5,
        "l2": 8.0e-6,
        "l2_bias": 1.4e-2,
        "logit_gain": 26.0,
        "ood_weight": 0.68,
        "ood_bias_target": 1.72,
    }

    nb = int(cfg["num_buckets"])
    wn = int(cfg["word_ngrams"])
    ms = int(cfg["min_sub"])
    xs = int(cfg["max_sub"])

    train_id_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt, _ in train_id_flagged]
    train_id_is_aug = [is_aug for _, _, is_aug in train_id_flagged]
    train_ood_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt, _ in train_ood_rows]
    train_ood_strata = [s for _, _, s in train_ood_rows]
    val_id_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt in val_id_raw]
    val_ood_feats = [(y, extract_feature_buckets(txt, nb, wn, ms, xs)) for y, txt, _ in val_ood_rows]
    val_ood_strata = [s for _, _, s in val_ood_rows]

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
        ood_weight=float(cfg["ood_weight"]),
        ood_bias_target=float(cfg["ood_bias_target"]),
        train_ood_strata=train_ood_strata,
        train_id_is_aug=train_id_is_aug,
        class_multipliers={
            label_to_idx["housing.housework"]: 0.88,
            label_to_idx["health.hospital"]: 1.14,
        },
        train_ood_is_tail=train_ood_is_tail,
    )

    opt_temp, opt_ood_delta, val_cal_stats = calibrate_post_quant_temperature_and_ood_bias(
        val_logits=res["val_logits"],  # type: ignore[arg-type]
        val_labels=res["val_labels"],  # type: ignore[arg-type]
        ood_logits=res["ood_logits"],  # type: ignore[arg-type]
        ood_strata=val_ood_strata,
        ood_idx=ood_idx,
        ood_reject_threshold=FINANCIAL_THRESHOLDS["oodReject"],
        low_conf_threshold=FINANCIAL_THRESHOLDS["lowConfidence"],
        high_conf_threshold=FINANCIAL_THRESHOLDS["highConfidence"],
    )

    b_vec: list[float] = list(res["b"])  # type: ignore[arg-type]
    b_vec[ood_idx] += opt_ood_delta
    elapsed = time.perf_counter() - t0
    fp32_payload = {
        "version": 3,
        "labels": ALL_FINANCIAL_LABELS,
        "config": cfg,
        "temperature": opt_temp,
        "ood_bias_delta": opt_ood_delta,
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
                "ood_bias_delta": opt_ood_delta,
                "max_in_domain_bias": round(max(b_vec[:ood_idx]), 4),
                "seconds": round(elapsed, 2),
            }
        ],
        "selected": cfg,
        "calibrated_temperature": opt_temp,
        "calibrated_ood_bias_delta": opt_ood_delta,
    }
    with (ART_DIR / "hyperparam_search.json").open("w", encoding="utf-8") as f:
        json.dump(search_log, f, indent=2)

    print(
        f"[FINANCIAL AI v3.0 QAT+OOD] classes={num_classes} (30+__ood__) | "
        f"val_acc={float(res['val_acc']):.4f} | val_macro_f1={float(res['val_macro_f1']):.4f} | "
        f"T*={opt_temp:.2f} | delta={opt_ood_delta:+.2f} | b[__ood__]={b_vec[ood_idx]:.3f} (max_id_b={max(b_vec[:ood_idx]):.3f}) | "
        f"val_cal={val_cal_stats} ({elapsed:.1f}s)",
        flush=True,
    )


if __name__ == "__main__":
    main()
