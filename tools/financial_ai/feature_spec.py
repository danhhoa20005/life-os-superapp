"""Shared feature extraction & 32-bit FNV-1a hashing specification.

Bit-for-bit identical across:
1. Python training/evaluation (`tools/financial_ai/`)
2. Android C++17 NDK FFI (`android/app/src/main/cpp/lifeos_fasttext_ffi.cpp`)
3. Dart Background Isolate Runtime (`lib/features/financial_ai/data/inference/`)
"""

from __future__ import annotations
import re
import unicodedata

SEMANTIC_LABELS: list[str] = [
    # Expense (23)
    "food.meals",
    "food.drinks",
    "food.groceries",
    "transport.fuel",
    "transport.ride_hailing",
    "transport.public",
    "transport.maintenance",
    "housing.rent",
    "housing.utilities",
    "housing.housework",
    "shopping.clothes",
    "shopping.electronics",
    "shopping.general",
    "health.medicine",
    "health.hospital",
    "education",
    "entertainment",
    "subscriptions",
    "family",
    "gifts",
    "debt.interest",
    "bank.fee",
    "other",
    # Income (7)
    "income.salary",
    "income.bonus",
    "income.freelance",
    "income.business",
    "income.interest",
    "income.gift",
    "income.other",
]

ABBREVIATION_MAP: dict[str, str] = {
    "cf": "cà phê",
    "cafe": "cà phê",
    "caphe": "cà phê",
    "ck": "chuyển khoản",
    "bhxh": "bảo hiểm xã hội",
    "bhyt": "bảo hiểm y tế",
    "tgdd": "thế giới di động",
    "dmx": "điện máy xanh",
    "bhx": "bách hóa xanh",
    "gs25": "siêu thị gs25",
    "kfc": "gà rán kfc",
    "cgv": "rạp phim cgv",
    "lotte": "siêu thị lotte",
    "evn": "tiền điện evn",
    "vnpt": "viễn thông vnpt",
    "fpt": "internet fpt",
    "spt": "spotify",
    "ytb": "youtube",
    "fb": "facebook",
    "grabbike": "grab xe ôm",
    "grabcar": "grab taxi",
    "gsm": "xanh sm taxi",
    "xanhsm": "xanh sm taxi",
    "bsx": "bảo dưỡng sửa xe",
    "nsd": "nhông sên dĩa sửa xe",
}

# Channel/temporal carrier stopwords (already extracted by Temporal & Type extractors)
# Kept identical across Python, C++17 FFI, and Dart so carrier wrappers never bias category weights.
CARRIER_STOPWORDS: set[str] = {
    "hom", "nay", "qua", "kia", "sang", "trua", "chieu", "toi", "tuan", "truoc",
    "vua", "moi", "da", "minh", "em", "anh", "het", "mat", "ton", "khoang",
    "gd", "the", "qr", "nd", "vcb", "tcb", "mbbank", "bidv", "acb", "tpb", "vpb",
    "digibank", "tinh", "so",
}

_AMOUNT_NOISE_RE = re.compile(
    r"\b\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|k|nghìn|nghin|ngàn|ngan|đ|d|₫|vnd|vnđ|usd)?(?:\s*\d{1,3})?\b",
    re.IGNORECASE,
)
_NON_WORD_RE = re.compile(r"[^\w\s]", re.UNICODE)
_MULTI_SPACE_RE = re.compile(r"\s+")


def strip_vn_accents(text: str) -> str:
    text = text.replace("đ", "d").replace("Đ", "D")
    decomposed = unicodedata.normalize("NFD", text)
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")


def normalize_for_classifier(raw_text: str) -> str:
    """Canonicalizes Vietnamese financial text for FastText classification."""
    s = unicodedata.normalize("NFC", raw_text.strip().lower())
    s = _AMOUNT_NOISE_RE.sub(" ", s)
    s = _NON_WORD_RE.sub(" ", s)
    tokens = [t for t in _MULTI_SPACE_RE.split(s) if t and not t.isdigit()]
    expanded: list[str] = []
    for tok in tokens:
        mapped = ABBREVIATION_MAP.get(tok)
        if mapped:
            expanded.extend(mapped.split())
        else:
            expanded.append(tok)

    filtered = [
        w for w in expanded if strip_vn_accents(w) not in CARRIER_STOPWORDS
    ]
    return " ".join(filtered if filtered else expanded).strip()


def fnv1a32_utf8(s: str) -> int:
    data = s.encode("utf-8")
    h = 0x811C9DC5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def extract_feature_buckets(
    normalized_text: str,
    num_buckets: int = 16384,
    word_ngrams: int = 2,
    min_subword: int = 3,
    max_subword: int = 5,
) -> list[int]:
    """Extracts FastText word n-grams (accented + ASCII-folded) and character subwords."""
    if not normalized_text:
        return []
    accented_tokens = [t for t in normalized_text.split(" ") if t]
    if not accented_tokens:
        return []
    ascii_tokens = [strip_vn_accents(t) for t in accented_tokens]

    features: list[str] = []

    # 1. Unigrams (weighted x2 relative to subwords by emitting primary word features cleanly)
    for w_acc, w_asc in zip(accented_tokens, ascii_tokens):
        features.append(f"w:{w_acc}")
        features.append(f"a:{w_asc}")

    # 2. Word N-grams (2..word_ngrams)
    n_tok = len(accented_tokens)
    for n in range(2, word_ngrams + 1):
        for i in range(n_tok - n + 1):
            bg_acc = "_".join(accented_tokens[i : i + n])
            bg_asc = "_".join(ascii_tokens[i : i + n])
            features.append(f"ng:{bg_acc}")
            features.append(f"na:{bg_asc}")

    # 3. Character subwords on ASCII-folded words (robust to ASR typos & missing diacritics)
    if max_subword >= min_subword and min_subword > 0:
        for w_asc in ascii_tokens:
            if len(w_asc) < 3:
                continue
            framed = f"<{w_asc}>"
            L = len(framed)
            for sub_len in range(min_subword, min(max_subword, L) + 1):
                for start in range(0, L - sub_len + 1):
                    features.append(f"s:{framed[start : start + sub_len]}")

    return [fnv1a32_utf8(feat) % num_buckets for feat in features]
