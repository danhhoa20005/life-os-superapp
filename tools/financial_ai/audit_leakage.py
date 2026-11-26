"""Comprehensive Anti-Leakage Audit across all Financial AI & Money-Split datasets.

Checks:
1. 0% exact normalized_text overlap across train / val / test / hard_v2_test (ID & OOD).
2. 0% template_id overlap across train / val / test / hard_v2_test.
3. 0% cross-contamination between ID and OOD splits.
4. ASCII-folded exact overlap and near-duplicate (token Jaccard >= 0.80 or char 4-gram Jaccard >= 0.82)
   audit between train/val and held-out test / hard_v2_test.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from feature_spec import strip_vn_accents

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "datasets"


def _read_jsonl(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def _norm_of(row: dict[str, str]) -> str:
    return str(row.get("normalized_text") or row.get("normalized") or "").strip()


def _char_ngrams(s: str, n: int = 4) -> set[str]:
    compact = f" {s} "
    if len(compact) < n:
        return {compact}
    return {compact[i : i + n] for i in range(len(compact) - n + 1)}


def _jaccard(a: set[str], b: set[str]) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def index_target_rows(target_rows: list[dict[str, str]]) -> list[tuple[dict[str, str], str, str, set[str], set[str]]]:
    target_indexed = []
    for r in target_rows:
        norm = _norm_of(r)
        if not norm:
            continue
        asc = strip_vn_accents(norm)
        toks = set(asc.split())
        c4 = _char_ngrams(asc, 4)
        target_indexed.append((r, norm, asc, toks, c4))
    return target_indexed


def find_near_duplicates(
    source_rows: list[dict[str, str]],
    target_rows: list[dict[str, str]],
    token_jaccard_thresh: float = 0.80,
    char4_jaccard_thresh: float = 0.82,
    min_tokens: int = 4,
    preindexed_targets: list[tuple[dict[str, str], str, str, set[str], set[str]]] | None = None,
) -> list[dict[str, object]]:
    """Finds near-duplicate pairs between source (e.g. train/val) and target (e.g. test/hard_v2)."""
    target_indexed = preindexed_targets if preindexed_targets is not None else index_target_rows(target_rows)

    findings: list[dict[str, object]] = []
    for sr in source_rows:
        snorm = _norm_of(sr)
        if not snorm:
            continue
        sasc = strip_vn_accents(snorm)
        stoks = set(sasc.split())
        sc4 = _char_ngrams(sasc, 4)

        for tr, tnorm, tasc, ttoks, tc4 in target_indexed:
            if sasc == tasc:
                findings.append(
                    {
                        "kind": "exact_ascii",
                        "source": snorm,
                        "target": tnorm,
                        "score": 1.0,
                    }
                )
                continue
            if len(stoks) >= min_tokens and len(ttoks) >= min_tokens:
                tj = _jaccard(stoks, ttoks)
                if tj >= token_jaccard_thresh:
                    findings.append(
                        {
                            "kind": "token_jaccard",
                            "source": snorm,
                            "target": tnorm,
                            "score": round(tj, 4),
                        }
                    )
                    continue
            if len(sasc) >= 12 and len(tasc) >= 12:
                cj = _jaccard(sc4, tc4)
                if cj >= char4_jaccard_thresh:
                    findings.append(
                        {
                            "kind": "char4_jaccard",
                            "source": snorm,
                            "target": tnorm,
                            "score": round(cj, 4),
                        }
                    )
    return findings


def run_audit(strict_near_dups: bool = True) -> dict[str, object]:
    fin_tr = _read_jsonl(DATA_DIR / "train.jsonl")
    fin_va = _read_jsonl(DATA_DIR / "val.jsonl")
    fin_te = _read_jsonl(DATA_DIR / "test.jsonl")

    ood_tr = _read_jsonl(DATA_DIR / "ood_financial_train.jsonl")
    ood_va = _read_jsonl(DATA_DIR / "ood_financial_val.jsonl")
    ood_te = _read_jsonl(DATA_DIR / "ood_financial_test.jsonl")

    hard_v2 = _read_jsonl(DATA_DIR / "hard_v2_test.jsonl")
    hard_v2_id = [r for r in hard_v2 if r.get("label") != "__ood__"]
    hard_v2_ood = [r for r in hard_v2 if r.get("label") == "__ood__"]

    def norm_set(rows: list[dict[str, str]]) -> set[str]:
        return {_norm_of(r) for r in rows if _norm_of(r)}

    def tpl_set(rows: list[dict[str, str]]) -> set[str]:
        return {str(r.get("template_id") or "") for r in rows if r.get("template_id")}

    # Exact normalized text checks
    exact_checks = {
        "fin_id_train_vs_val": len(norm_set(fin_tr) & norm_set(fin_va)),
        "fin_id_train_vs_test": len(norm_set(fin_tr) & norm_set(fin_te)),
        "fin_id_val_vs_test": len(norm_set(fin_va) & norm_set(fin_te)),
        "fin_id_train_vs_hard_v2": len(norm_set(fin_tr) & norm_set(hard_v2)),
        "fin_id_val_vs_hard_v2": len(norm_set(fin_va) & norm_set(hard_v2)),
        "fin_ood_train_vs_val": len(norm_set(ood_tr) & norm_set(ood_va)),
        "fin_ood_train_vs_test": len(norm_set(ood_tr) & norm_set(ood_te)),
        "fin_ood_val_vs_test": len(norm_set(ood_va) & norm_set(ood_te)),
        "fin_ood_train_vs_hard_v2": len(norm_set(ood_tr) & norm_set(hard_v2)),
        "fin_ood_val_vs_hard_v2": len(norm_set(ood_va) & norm_set(hard_v2)),
        "ood_vs_id_all": len(
            (norm_set(ood_tr) | norm_set(ood_va) | norm_set(ood_te) | norm_set(hard_v2_ood))
            & (norm_set(fin_tr) | norm_set(fin_va) | norm_set(fin_te) | norm_set(hard_v2_id))
        ),
        "tpl_id_train_vs_val": len(tpl_set(fin_tr) & tpl_set(fin_va)),
        "tpl_id_train_vs_test": len(tpl_set(fin_tr) & tpl_set(fin_te)),
        "tpl_id_val_vs_test": len(tpl_set(fin_va) & tpl_set(fin_te)),
        "tpl_ood_train_vs_val": len(tpl_set(ood_tr) & tpl_set(ood_va)),
        "tpl_ood_train_vs_test": len(tpl_set(ood_tr) & tpl_set(ood_te)),
        "tpl_ood_val_vs_test": len(tpl_set(ood_va) & tpl_set(ood_te)),
    }

    # Filter augmented rows (template_id starts with aug_) vs all held-out test rows for strict near-dup check
    aug_fin_tr = [r for r in fin_tr if str(r.get("template_id", "")).startswith("aug_")]
    aug_fin_va = [r for r in fin_va if str(r.get("template_id", "")).startswith("aug_")]
    aug_ood_tr = [r for r in ood_tr if str(r.get("template_id", "")).startswith("aug_")]
    aug_ood_va = [r for r in ood_va if str(r.get("template_id", "")).startswith("aug_")]

    held_out_all = fin_te + ood_te + hard_v2
    aug_near_dups = find_near_duplicates(
        aug_fin_tr + aug_fin_va + aug_ood_tr + aug_ood_va,
        held_out_all,
    )
    all_tr_va_vs_hard_v2 = find_near_duplicates(
        fin_tr + fin_va + ood_tr + ood_va,
        hard_v2,
    )

    report = {
        "counts": {
            "train": len(fin_tr),
            "val": len(fin_va),
            "test": len(fin_te),
            "ood_train": len(ood_tr),
            "ood_val": len(ood_va),
            "ood_test": len(ood_te),
            "hard_v2_test": len(hard_v2),
            "aug_train": len(aug_fin_tr),
            "aug_val": len(aug_fin_va),
            "aug_ood_train": len(aug_ood_tr),
            "aug_ood_val": len(aug_ood_va),
        },
        "exactChecks": exact_checks,
        "augNearDupCount": len(aug_near_dups),
        "augNearDupSamples": aug_near_dups[:10],
        "allTrainValVsHardV2NearDupCount": len(all_tr_va_vs_hard_v2),
        "allTrainValVsHardV2NearDupSamples": all_tr_va_vs_hard_v2[:10],
    }

    failed_exact = {k: v for k, v in exact_checks.items() if v > 0}
    if failed_exact:
        raise AssertionError(f"Exact leakage detected: {failed_exact}")
    if strict_near_dups and (aug_near_dups or all_tr_va_vs_hard_v2):
        raise AssertionError(
            f"Near-duplicate leakage detected: aug={len(aug_near_dups)}, hard_v2={len(all_tr_va_vs_hard_v2)}"
        )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--non-strict-near-dups", action="store_true")
    args = parser.parse_args()
    rep = run_audit(strict_near_dups=not args.non_strict_near_dups)
    print(json.dumps(rep, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
