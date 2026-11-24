# Quy trình Huấn luyện, Hiệu chỉnh & Lượng tử hóa Mô hình (`model_training.md`)

## 1. Kiến trúc Mô hình `vn_financial_fasttext_v1`

Mô hình phân loại danh mục tài chính tiếng Việt được huấn luyện theo kiến trúc **FastText Supervised Subword + Word Bigram Classifier** và đóng gói sang định dạng nhị phân lượng tử hóa đối xứng theo hàng **`LFTQ` v1 (`INT8`)**:

- **Đầu vào đặc trưng (`extract_feature_buckets`):**
  - Token từ đơn (`word unigram`) có dấu **và** bản đối chiếu bỏ dấu tiếng Việt (`strip_vn_accents`) để câu gõ không dấu (`an sang`, `do xang`) đạt độ chính xác tương đương câu có dấu.
  - Cặp từ liền kề (`word bigrams`, `word_ngrams = 2`) giữ ngữ cảnh cụm từ tiếng Việt (`tiền nhà` $\neq$ `việc nhà`, `lãi vay` $\neq$ `lãi tiết kiệm`).
  - Chuỗi ký tự con (`character subwords` độ dài `min_sub = 3..max_sub = 5` quanh `<word>`) giúp mô hình chịu lỗi chính tả nhẹ và biến thể tên thương hiệu.
- **Hàm băm đặc trưng:** `FNV-1a 32-bit` trên chuỗi byte UTF-8 ánh xạ vào `B = 16,384` bucket — thực thi giống hệt từng bit giữa Python (`feature_spec.py`), C++17 (`lifeos_fasttext_ffi.cpp`) và Dart (`fasttext_binary_model.dart`).
- **Tầng tính điểm & Hiệu chỉnh xác suất:**
  $$z = \frac{1}{|S|} \sum_{b \in S} E[b] \cdot W^\top + \text{bias}, \qquad P(y_k \mid x) = \text{softmax}\!\left(\frac{z}{T^*}\right)_k$$
  với $K = 30$ nhãn ngữ nghĩa và nhiệt độ hiệu chỉnh $T^* = 0.75$ tối ưu hóa Negative Log-Likelihood (NLL) trên tập `val`.

---

## 2. Siêu tham số Huấn luyện Tối ưu

Được lưu vết đầy đủ trong [`assets/models/vn_financial_fasttext_v1_meta.json`](file:///g:/superapp/assets/models/vn_financial_fasttext_v1_meta.json):

| Tham số | Giá trị | Ý nghĩa kỹ thuật |
| :--- | :--- | :--- |
| `num_classes` ($K$) | `30` | 23 nhãn chi tiêu (`debit`) + 7 nhãn thu nhập (`credit`) |
| `num_buckets` ($B$) | `16,384` | Số lượng bucket băm cho từ đơn, cặp từ và subword |
| `dim` ($D$) | `30` | Chiều nhúng hạng đầy đủ (Full-rank $K=30$) hội tụ lồi nhanh với AdaGrad |
| `word_ngrams` | `2` | Kích hoạt word bigrams tiếng Việt |
| `min_sub` / `max_sub` | `3` / `5` | Độ dài character n-gram cho khả năng chống lỗi gõ tắt |
| `lr` | `0.45` | Tốc độ học khởi tạo với lịch giảm tuyến tính & AdaGrad theo tọa độ |
| `epochs` | `28` | Số vòng huấn luyện trên tập `train` (`1,361` mẫu duy nhất) |
| `l2` | `5e-5` | Điều chuẩn $L_2$ chống quá khớp (overfitting) |
| `calibratedTemperature` ($T^*$) | `0.75` | Hệ số hiệu chỉnh độ tự tin xác suất trên tập `val` (`699` mẫu) |

---

## 3. Lượng tử hóa Đối xứng Theo hàng (`INT8` `LFTQ` v1)

Script [`tools/financial_ai/quantize.py`](file:///g:/superapp/tools/financial_ai/quantize.py) nén ma trận nhúng `float32` `[16384, 30]` (`1.97 MB`) xuống `int8` kèm hệ số tỷ lệ `float16` cho từng hàng:

$$s_i = \frac{\max_j |E_{i,j}|}{127.0}, \qquad Q_{i,j} = \text{round}\!\left(\frac{E_{i,j}}{s_i}\right) \in [-127, 127]$$

- **Dung lượng tệp sau nén:** `561,270 bytes` (**`548.12 KB`**, giảm **72.1%** so với bản `float32` gốc, nhỏ hơn rất nhiều so với ngưỡng mục tiêu `< 10 MB`).
- **SHA-256 kiểm định toàn vẹn:** `7e1178bb57fe78c2a57d0eb624e24eb870846c5993150609034ab2062e11b1a6`.
- **Độ suy hao F1 sau lượng tử hóa `INT8`:** `< 0.001` (gần như bằng 0).

---

## 4. Kết quả Đánh giá Thực tế trên Tập Held-Out Test (`681` mẫu)

Kết quả trích xuất trực tiếp từ [`tools/financial_ai/artifacts/eval_report.json`](file:///g:/superapp/tools/financial_ai/artifacts/eval_report.json):

- **Accuracy tổng thể:** **`90.75%`** (`0.9075`)
- **Macro F1 trên 30 danh mục:** **`0.9164`** (vượt mục tiêu thiết kế)
- **Expected Calibration Error (ECE):** **`0.0481`** (xác suất đầu ra phản ánh trung thực độ chính xác thực tế)
- **Tỷ lệ gán tự động sai ở ngưỡng `>= 0.78` (`False Auto-Assignment Rate`):** **`2.06%`** (`0.0206`)
- **Tỷ lệ từ chối câu ngoài miền (`OOD Unknown Rejection Rate`):** **`100.0%`** (`1.0000`)

---

## 5. Lệnh Tái huấn luyện & Xuất Model Đầy đủ (Reproducible Pipeline)

Yêu cầu môi trường: `Python >= 3.10` + `numpy` (`pip install -r tools/financial_ai/requirements.txt`).

```powershell
# Bước 1: Sinh và chuẩn bị dữ liệu chống rò rỉ (train / val / test)
python tools/financial_ai/generate_synthetic_data.py
python tools/financial_ai/prepare_dataset.py

# Bước 2: Huấn luyện + tìm nhiệt độ hiệu chỉnh T* trên tập val
python tools/financial_ai/train.py

# Bước 3: Lượng tử hóa INT8 sang assets/models/vn_financial_fasttext_v1.ftq
python tools/financial_ai/quantize.py

# Bước 4: Đánh giá độc lập trên tập test & xuất metadata SHA-256
python tools/financial_ai/evaluate.py
python tools/financial_ai/export_metadata.py

# Bước 5: Đo tốc độ inference chuẩn trên host Python
python tools/financial_ai/benchmark.py
```
