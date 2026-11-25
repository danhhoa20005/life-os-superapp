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

---

## 6. Mô hình Thứ 2: `vn_money_split_fasttext_v1` (Chia tiền Nhóm & Phân bổ Thu nhập — Section 14)

Bên cạnh `vn_financial_fasttext_v1` (giữ nguyên toàn vẹn cho phân loại 30 danh mục tài chính & 14 golden vectors), Wave 1C hiệu chỉnh lại toàn bộ mô hình thứ 2 [`assets/models/vn_money_split_fasttext_v1.ftq`](../../assets/models/vn_money_split_fasttext_v1.ftq) bằng QAT + Temperature Calibration trên tập dữ liệu mới chống rò rỉ mẫu câu:

### 6.1. Siêu tham số & Định dạng Đóng gói ([`vn_money_split_fasttext_v1_meta.json`](../../assets/models/vn_money_split_fasttext_v1_meta.json))

| Tham số | Giá trị | Ghi chú |
| :--- | :--- | :--- |
| `modelId` / `modelVersion` | `vn_money_split_fasttext_v1` / `1.0.0` | Định dạng `INT8` `LFTQ` v1 (MIT License) |
| `numClasses` ($K$) | `12` | `7` lớp `split.*` + `5` lớp `alloc.*` |
| `numBuckets` / `dim` | `24,576` / `12` | Word bigrams (`wordNgrams = 2`) + subword `4..5` ký tự |
| `logitGain` | `15.0` | Khớp bit-for-bit với `FastTextBinaryModel` |
| `epochs` / `qatEpochs` | `38` / `12` | Huấn luyện Quantization-Aware Training + Outlier Exposure |
| `calibratedTemperature` ($T^*$) | **`0.76`** | Giảm `ECE` từ `0.1001` xuống **`0.0405`** |
| **Dung lượng `.ftq`** | **`394,128 bytes` (`384.89 KB`)** | Nhỏ hơn ngưỡng `< 450 KB` |
| **SHA-256** | `c0365a61d930864da4d1e55477ea80d387d326c5569b29fa466a2376757f3bb1` | Khớp Runtime verification |

### 6.2. Chỉ số Đánh giá Held-Out Test (`232` mẫu) & Ma trận Nhầm lẫn (`vn_money_split_fasttext_v1_eval.json`)

- **Test Accuracy:** **`99.57%`** (`0.9957`)
- **Macro F1:** **`0.9958`**
- **Expected Calibration Error (ECE):** **`0.0405`** (`< 0.05`)
- **False Auto-Assignment Rate:** **`0.00%`** (`0.0`)
- **OOD Unknown Rejection Rate:** **`100.00%`** (`1.0`)
- **Độ chính xác theo từng lớp:** 11/12 lớp đạt `F1 = 1.0000`; duy nhất `alloc.family_household` đạt `precision = 1.0000`, `recall = 0.9500` (`19/20`, `1` mẫu nghiêng về `alloc.fire_high_savings` -> `alloc.fire_high_savings` `precision = 0.9524`, `recall = 1.0000`, `f1 = 0.9756`).

### 6.3. Lệnh Tái huấn luyện & Kiểm định `vn_money_split_fasttext_v1`

```powershell
python tools/financial_ai/train_money_split_ai.py
```

Lệnh trên tự động xuất đồng bộ 3 tập [`money_split_train.jsonl`](../../tools/financial_ai/datasets/money_split_train.jsonl) (`1,720` mẫu), [`money_split_val.jsonl`](../../tools/financial_ai/datasets/money_split_val.jsonl) (`242` mẫu), [`money_split_test.jsonl`](../../tools/financial_ai/datasets/money_split_test.jsonl) (`232` mẫu), thực hiện tìm $T^*$ tối ưu ECE, đóng gói `.ftq`, cập nhật `_meta.json` và xuất báo cáo `vn_money_split_fasttext_v1_eval.json`.
