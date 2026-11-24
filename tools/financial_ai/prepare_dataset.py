"""Validates, deduplicates, checks anti-leakage invariants, and exports FastText splits."""

from __future__ import annotations
import json
from collections import Counter
from pathlib import Path
from feature_spec import SEMANTIC_LABELS, normalize_for_classifier

BASE_DIR = Path(__file__).resolve().parent
RAW_FILE = BASE_DIR / "datasets" / "raw" / "raw_corpus.jsonl"
OUT_DIR = BASE_DIR / "datasets"


def main() -> None:
    if not RAW_FILE.exists():
        raise FileNotFoundError(f"Run generate_synthetic_data.py first: {RAW_FILE}")

    valid_labels = set(SEMANTIC_LABELS)
    by_split: dict[str, list[dict[str, str]]] = {"train": [], "val": [], "test": []}
    seen_norm_per_split: dict[str, set[str]] = {"train": set(), "val": set(), "test": set()}
    templates_per_split: dict[str, set[str]] = {"train": set(), "val": set(), "test": set()}

    with RAW_FILE.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, start=1):
            obj = json.loads(line)
            label = obj["label"]
            split = obj["split"]
            if label not in valid_labels:
                raise ValueError(f"Invalid label at line {line_no}: {label}")
            if split not in by_split:
                raise ValueError(f"Invalid split at line {line_no}: {split}")

            norm = normalize_for_classifier(obj["text"])
            if len(norm) < 2:
                continue

            # Deduplicate normalized text within and across splits (train takes priority, never leak into val/test!)
            if norm in seen_norm_per_split["train"] or norm in seen_norm_per_split["val"] or norm in seen_norm_per_split["test"]:
                continue

            seen_norm_per_split[split].add(norm)
            templates_per_split[split].add(obj["template_id"])
            by_split[split].append(
                {
                    "label": label,
                    "raw_text": obj["text"],
                    "normalized_text": norm,
                    "template_id": obj["template_id"],
                    "style": obj["style"],
                }
            )

    # Strict Anti-Leakage Verification
    assert templates_per_split["train"].isdisjoint(templates_per_split["val"]), "Template leakage train <-> val!"
    assert templates_per_split["train"].isdisjoint(templates_per_split["test"]), "Template leakage train <-> test!"
    assert templates_per_split["val"].isdisjoint(templates_per_split["test"]), "Template leakage val <-> test!"
    assert seen_norm_per_split["train"].isdisjoint(seen_norm_per_split["test"]), "Normalized text leakage train <-> test!"

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    summary: dict[str, object] = {}
    for split, items in by_split.items():
        jsonl_path = OUT_DIR / f"{split}.jsonl"
        ft_path = OUT_DIR / f"{split}.fasttext.txt"
        counts = Counter(x["label"] for x in items)

        with jsonl_path.open("w", encoding="utf-8") as jf, ft_path.open("w", encoding="utf-8") as ff:
            for item in items:
                jf.write(json.dumps(item, ensure_ascii=False) + "\n")
                ff.write(f"__label__{item['label']} {item['normalized_text']}\n")

        summary[split] = {
            "count": len(items),
            "unique_templates": len(templates_per_split[split]),
            "num_classes": len(counts),
            "min_per_class": min(counts.values()),
            "max_per_class": max(counts.values()),
        }
        print(f"[{split.upper()}] {len(items)} deduplicated examples | {len(counts)} classes | 0% template leakage -> {ft_path.name}")

    with (OUT_DIR / "dataset_stats.json").open("w", encoding="utf-8") as sf:
        json.dump(summary, sf, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
