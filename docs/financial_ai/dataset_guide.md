# Hướng dẫn Bộ dữ liệu Huấn luyện — Offline Vietnamese Financial AI (`dataset_guide.md`)

## 1. Mục tiêu và Nguyên tắc Thiết kế Dữ liệu

Bộ dữ liệu huấn luyện cho mô hình `vn_financial_fasttext_v1` được thiết kế chuyên biệt cho **ngôn ngữ tài chính đời thực của người Việt Nam** trên 3 kênh đầu vào chính của Life OS Super App:

1. **Nhập văn bản tự nhiên (Manual / Quick Input):** Câu ngắn có dấu, không dấu, viết tắt (`cf 30k`, `an sang 35k`, `mua tai nghe tgdd 350k`, `ck 500k cho mẹ`).
2. **Nhận diện giọng nói (ASR Voice Transcript):** Văn phong khẩu ngữ, số tiền đọc bằng chữ (`mười hai triệu`, `bốn trăm năm mươi nghìn`, `một triệu rưỡi`), câu nối nhiều khoản thu chi.
3. **Thông báo biến động số dư Ngân hàng & Ví điện tử (Bank Notification):** Chuỗi in hoa không dấu, mã giao dịch, tên merchant POS/QR (`SD TK ... -55,000VND ... ND: THANH TOAN HIGHLANDS COFFEE`, `GD THE TAI CIRCLE K`, `MBBANK ...`).

### Quy tắc An toàn & Bảo mật Dữ liệu (Phase 8 & Phase 17)
- **0% PII thật:** Không chứa số tài khoản thật, họ tên khách hàng thật, số thẻ, số điện thoại hay mã OTP thật.
- **Tách biệt hoàn toàn theo Họ Mẫu Câu (`template_family_id`):** Mọi biến thể sinh ra từ cùng một cấu trúc câu gốc bắt buộc nằm trong cùng một tập (`train`, `val`, hoặc `test`) — **0% rò rỉ mẫu câu (data leakage)** giữa tập huấn luyện và tập kiểm thử.
- **Loại bỏ từ nhiễu kênh dẫn (`CARRIER_STOPWORDS`):** Các từ chỉ thời gian (`hôm nay`, `chiều qua`) và tiền tố ngân hàng (`VCB`, `TCB`, `GD`, `ND`) được lọc đồng nhất ở cả Python (`tools/financial_ai/feature_spec.py`) và Dart (`FinancialTextNormalizer.toClassifierInput`) để mô hình học đúng bản chất ngữ nghĩa của danh mục, không học vẹt theo ngân hàng hay thời điểm.

---

## 2. Cấu trúc Thư mục & Tệp Dữ liệu

Toàn bộ dữ liệu và công cụ tiền xử lý nằm tại [`tools/financial_ai/`](file:///g:/superapp/tools/financial_ai/):

| Đường dẫn | Vai trò | Số dòng / Quy mô thực tế |
| :--- | :--- | :--- |
| [`tools/financial_ai/feature_spec.py`](file:///g:/superapp/tools/financial_ai/feature_spec.py) | Định nghĩa chuẩn hóa văn bản, từ viết tắt, FNV-1a 32-bit UTF-8 n-gram hashing đồng nhất 100% với Dart/C++ | 30 nhãn chuẩn |
| [`tools/financial_ai/generate_synthetic_data.py`](file:///g:/superapp/tools/financial_ai/generate_synthetic_data.py) | Bộ sinh dữ liệu đa dạng hóa dấu câu, viết tắt, phương ngữ Bắc–Trung–Nam, merchant thực tế tại Việt Nam | Sinh `5,009` mẫu thô |
| [`tools/financial_ai/prepare_dataset.py`](file:///g:/superapp/tools/financial_ai/prepare_dataset.py) | Khử trùng lặp văn bản chuẩn hóa, chia tách theo `template_family_id`, kiểm định `0%` overlap | Xuất `2,741` mẫu duy nhất |
| `tools/financial_ai/datasets/train.jsonl` | Tập huấn luyện chính (JSONL đầy đủ metadata) | `1,361` mẫu duy nhất |
| `tools/financial_ai/datasets/val.jsonl` | Tập tinh chỉnh siêu tham số & hiệu chỉnh nhiệt độ $T^*$ | `699` mẫu duy nhất |
| `tools/financial_ai/datasets/test.jsonl` | Tập kiểm thử độc lập (Held-out Test Set) | `681` mẫu duy nhất |
| `tools/financial_ai/datasets/*.fasttext.txt` | Định dạng chuẩn FastText (`__label__<semanticKey> <normalizedText>`) | Tương ứng `train` / `val` / `test` |

---

## 3. Định dạng Bản ghi JSONL Chuẩn

Mỗi dòng trong `train.jsonl`, `val.jsonl`, `test.jsonl` tuân thủ lược đồ:

```json
{
  "id": "syn_000142",
  "raw_text": "Sáng nay ghé Highlands uống cf sữa đá hết 39k",
  "normalized_text": "ghé highlands uống cà phê sữa đá",
  "category": "food.drinks",
  "direction": "debit",
  "template_family_id": "food.drinks::fam_02",
  "has_accents": true,
  "channel": "manual_or_voice"
}
```

### Kiểm định Chống Rò rỉ (Anti-Leakage Audit)
Khi chạy `python tools/financial_ai/prepare_dataset.py`, hệ thống thực thi 2 phép kiểm tra bắt buộc (`assert` cứng):
1. Giao của tập `template_family_id` giữa `train`, `val`, `test` bằng $\emptyset$ (`0` họ mẫu câu trùng lặp).
2. Giao của tập `normalized_text` giữa `train`, `val`, `test` bằng $\emptyset$ (`0` câu chuẩn hóa trùng lặp).

---

## 4. Quy trình Bổ sung Dữ liệu Thực tế & Tái tạo Tập Dữ liệu

Khi muốn mở rộng thêm từ lóng, merchant địa phương hoặc dữ liệu ẩn danh đã được người dùng đồng ý:

1. **Thêm mẫu hoặc từ khóa mới** vào bảng hạt giống ngữ nghĩa trong [`tools/financial_ai/generate_synthetic_data.py`](file:///g:/superapp/tools/financial_ai/generate_synthetic_data.py) (hoặc đặt tệp dữ liệu thực tế đã ẩn danh PII vào `tools/financial_ai/datasets/custom_seed.jsonl` theo cùng schema).
2. **Nếu thêm từ viết tắt mới** (ví dụ viết tắt tên chuỗi cửa hàng mới), cập nhật đồng thời tại **cả hai nơi** để giữ tính đồng nhất Train–Serve (`100%` parity):
   - `ABBREVIATIONS` trong [`tools/financial_ai/feature_spec.py`](file:///g:/superapp/tools/financial_ai/feature_spec.py)
   - `kClassifierAbbreviations` trong [`lib/features/financial_ai/data/normalization/financial_text_normalizer.dart`](file:///g:/superapp/lib/features/financial_ai/data/normalization/financial_text_normalizer.dart)
3. **Chạy lệnh tái tạo & kiểm định dữ liệu:**

```powershell
python tools/financial_ai/generate_synthetic_data.py
python tools/financial_ai/prepare_dataset.py
```
