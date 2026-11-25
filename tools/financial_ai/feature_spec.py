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

OOD_LABEL: str = "__ood__"
ALL_FINANCIAL_LABELS: list[str] = [*SEMANTIC_LABELS, OOD_LABEL]

FINANCIAL_THRESHOLDS: dict[str, float] = {
    "highConfidence": 0.87,
    "mediumConfidence": 0.52,
    "lowConfidence": 0.34,
    "oodReject": 0.40,
}

MONEY_SPLIT_THRESHOLDS: dict[str, float] = {
    "highConfidence": 0.87,
    "mediumConfidence": 0.52,
    "lowConfidence": 0.36,
    "oodReject": 0.44,
}

ABBREVIATION_MAP: dict[str, str] = {
    "cf": "cà phê",
    "cafe": "cà phê",
    "caphe": "cà phê",
    "ts": "trà sữa",
    "trasua": "trà sữa",
    "ck": "chuyển khoản",
    "bhxh": "bảo hiểm xã hội",
    "bhyt": "bảo hiểm y tế",
    "tgdd": "thế giới di động",
    "dmx": "điện máy xanh",
    "bhx": "bách hóa xanh",
    "winmart": "siêu thị winmart",
    "vinmart": "siêu thị winmart",
    "coopmart": "siêu thị coopmart",
    "gs25": "siêu thị gs25",
    "circlek": "circle k",
    "kfc": "gà rán kfc",
    "jollibee": "gà rán jollibee",
    "lotteria": "gà rán lotteria",
    "cgv": "rạp phim cgv",
    "bhd": "rạp phim bhd",
    "lotte": "siêu thị lotte",
    "aeon": "siêu thị aeon",
    "evn": "tiền điện evn",
    "sawaco": "tiền nước sawaco",
    "capnuoc": "tiền nước",
    "vnpt": "viễn thông vnpt",
    "fpt": "internet fpt",
    "vt": "viễn thông viettel",
    "spt": "spotify",
    "ytb": "youtube",
    "fb": "facebook",
    "icloud": "gói icloud",
    "netflix": "gói netflix",
    "grabbike": "grab xe ôm",
    "grabcar": "grab taxi",
    "bebike": "be xe ôm",
    "becar": "be taxi",
    "gsm": "xanh sm taxi",
    "xanhsm": "xanh sm taxi",
    "epass": "trạm thu phí epass",
    "vetc": "trạm thu phí vetc",
    "bsx": "bảo dưỡng sửa xe",
    "nsd": "nhông sên dĩa sửa xe",
    "longchau": "nhà thuốc long châu",
    "pharmacity": "nhà thuốc pharmacity",
    "ankhang": "nhà thuốc an khang",
    "vnvc": "tiêm vắc xin vnvc",
    "fecredit": "trả góp fe credit",
    "homecredit": "trả góp home credit",
    "hdsaison": "trả góp hd saison",
    "vpp": "văn phòng phẩm",
    "fahasa": "nhà sách fahasa",
    "concung": "mẹ bé con cưng",
    "kidsplaza": "mẹ bé kids plaza",
    "ghtk": "giao hàng tiết kiệm",
    "ghn": "giao hàng nhanh",
}

# Unambiguous bank/SMS channel tokens with ZERO Vietnamese noun or pronoun polarity collisions.
# Kept 100% identical across Python, C++17 FFI, and Dart.
CARRIER_STOPWORDS: set[str] = {
    "vcb", "tcb", "mbbank", "bidv", "acb", "tpb", "vpb",
    "tpbank", "vpbank", "techcombank", "vietcombank", "vietinbank", "sacombank",
    "digibank", "smartbanking", "zalopay", "momo", "qr", "nd", "gd",
}

_SPOKEN_HALF_MILLION_RE = re.compile(
    r"(?<![\w])(?:nửa|nua)\s+(?:triệu|trieu|củ|cu)(?![\w])",
    re.IGNORECASE | re.UNICODE,
)
_SPOKEN_HALF_XI_RE = re.compile(
    r"(?<![\w])(?:nửa|nua)\s+xị(?![\w])",
    re.IGNORECASE | re.UNICODE,
)
_SPOKEN_TRAM_RUOI_RE = re.compile(
    r"(?<![\w])(?:[1-9]|một|mot|hai|ba|bốn|bon|tư|tu|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin)?\s*(?:trăm|tram)\s+(?:rưỡi|ruoi)(?:\s*(?:nghìn|nghin|ngàn|ngan))?(?![\w])",
    re.IGNORECASE | re.UNICODE,
)
_SPOKEN_CU_RUOI_RE = re.compile(
    r"(?<![\w])(?:\d+|một|mot|hai|ba|bốn|bon|năm|nam|sáu|sau|bảy|bay|bẩy|tám|tam|chín|chin|mười|muoi)?\s*(?:triệu|trieu|tr|củ|cu)\s+(?:rưỡi|ruoi)(?![\w])",
    re.IGNORECASE | re.UNICODE,
)
_PRE_AMOUNT_MARKER_RE = re.compile(
    r"(?<![\w])(?:hết|het|mất|tốn|ton|khoảng|khoang|tầm|tam)\s+(?=(?:\$|\d))",
    re.IGNORECASE | re.UNICODE,
)
_USD_NOISE_RE = re.compile(r"\$\s*\d+(?:[.,]\d{1,2})?", re.IGNORECASE)
_AMOUNT_NOISE_RE = re.compile(
    r"(?<![\w])\d+(?:[.,]\d+)?\s*(?:tr|triệu|trieu|củ|cu|tỷ|ty|k|nghìn|nghin|ngàn|ngan|xị|xi|cành|canh|nhành|nhanh|chục|chuc|đ|d|₫|vnd|vnđ|đồng|dong|usd)?(?:\s*(?:rưỡi|ruoi))?(?:\s*\d{1,3}(?:\s*(?:nghìn|nghin|ngàn|ngan|k))?)?(?![\w])",
    re.IGNORECASE | re.UNICODE,
)
_CARRIER_PHRASE_RE = re.compile(
    r"(?<![\w])(?:"
    r"(?:hôm|hom)\s+(?:nay|qua|kia)|"
    r"(?:sáng|sang|trưa|trua|chiều|chieu|tối|toi|đêm|dem)\s+(?:nay|qua)|"
    r"(?:tuần|tuan)\s+(?:này|nay|trước|truoc)|"
    r"(?:vừa|vua|mới|moi)\s+(?:thanh\s+toán|thanh\s+toan|trả\s+tiền|tra\s+tien)|"
    r"(?:vừa|vua)\s+(?:mới|moi)|"
    r"(?:cho|chi)\s+(?:khoản|khoan)|"
    r"(?:dùng|dung)\s+(?:cho\s+)?(?:việc|viec)|"
    r"(?:số|so)\s+(?:tiền|tien)|"
    r"(?:nội|noi)\s+dung|"
    r"(?:báo|bao)\s+(?:có|co|nợ|no)|"
    r"tinh\s+tinh|"
    r"sd\s+tk|"
    r"gd\s+(?:the|thẻ|qr)"
    r")(?![\w])",
    re.IGNORECASE | re.UNICODE,
)
_NON_WORD_RE = re.compile(r"[^\w\s]|_", re.UNICODE)
_MULTI_SPACE_RE = re.compile(r"\s+")


def strip_vn_accents(text: str) -> str:
    text = text.replace("đ", "d").replace("Đ", "D")
    decomposed = unicodedata.normalize("NFD", text)
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")


def normalize_for_classifier(raw_text: str) -> str:
    """Canonicalizes Vietnamese financial text for FastText classification (100% parity with Dart)."""
    s = unicodedata.normalize("NFC", raw_text.strip().lower())
    s = _SPOKEN_HALF_MILLION_RE.sub("500k", s)
    s = _SPOKEN_HALF_XI_RE.sub("50k", s)
    s = _SPOKEN_TRAM_RUOI_RE.sub("150k", s)
    s = _SPOKEN_CU_RUOI_RE.sub("1tr5", s)
    s = _PRE_AMOUNT_MARKER_RE.sub(" ", s)
    s = _USD_NOISE_RE.sub(" ", s)
    s = _AMOUNT_NOISE_RE.sub(" ", s)
    s = _NON_WORD_RE.sub(" ", s)
    s = _CARRIER_PHRASE_RE.sub(" ", s)
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
    num_buckets: int = 24576,
    word_ngrams: int = 3,
    min_subword: int = 4,
    max_subword: int = 5,
) -> list[int]:
    """Extracts FastText word n-grams (accented + ASCII-folded) and character subwords."""
    trimmed = normalized_text.strip()
    if not trimmed:
        return []
    accented_tokens = [t for t in trimmed.split(" ") if t]
    if not accented_tokens:
        return []
    ascii_tokens = [strip_vn_accents(t) for t in accented_tokens]

    features: list[str] = []

    # 1. Word Unigrams (2x accented + 1x ASCII-folded so tonal Vietnamese distinctions stay sharp)
    for w_acc, w_asc in zip(accented_tokens, ascii_tokens):
        features.append(f"w:{w_acc}")
        features.append(f"w:{w_acc}")
        features.append(f"a:{w_asc}")

    # 2. Word N-grams (2..word_ngrams; 2x accented bigram for Vietnamese disyllabic compounds)
    n_tok = len(accented_tokens)
    for n in range(2, word_ngrams + 1):
        for i in range(n_tok - n + 1):
            bg_acc = "_".join(accented_tokens[i : i + n])
            bg_asc = "_".join(ascii_tokens[i : i + n])
            features.append(f"ng:{bg_acc}")
            if n == 2:
                features.append(f"ng:{bg_acc}")
            features.append(f"na:{bg_asc}")

    # 3. Character subwords on ASCII-folded tokens of length >= 4 (typo & brand resilience without 2-3 char syllable noise)
    if max_subword >= min_subword and min_subword > 0:
        for w_asc in ascii_tokens:
            if len(w_asc) < 4:
                continue
            framed = f"<{w_asc}>"
            L = len(framed)
            for sub_len in range(min_subword, min(max_subword, L) + 1):
                for start in range(0, L - sub_len + 1):
                    features.append(f"s:{framed[start : start + sub_len]}")

    return [fnv1a32_utf8(feat) % num_buckets for feat in features]
