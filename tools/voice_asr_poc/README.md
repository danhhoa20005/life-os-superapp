# LifeOS Voice 2.0 — Offline Vietnamese ASR PoC & Corpus Benchmark Suite

Bộ công cụ Proof-of-Concept & đánh giá độc lập cho kiến trúc Voice 2.0 tiếng Việt trên thiết bị (`Stage C — Section 7, 8, 15`).

## Cấu trúc thư mục

- `corpus/vi_financial_corpus.json`: Tập ngữ liệu chuẩn **36 câu lệnh tiếng Việt** phủ đầy đủ giọng Bắc/Trung/Nam, nói nhanh/chậm/nhỏ/ồn, ngắt nghỉ giữa câu, đa tác vụ, tiền tệ tiếng Việt nói tự nhiên, chuyển đổi mã Anh-Việt, 7 ngân hàng/ví (`Vietcombank`, `MB Bank`, `Techcombank`, `VPBank`, `BIDV`, `MoMo`, `ZaloPay`), 5 tên người (`Minh`, `Lan`, `Hòa`, `Tuấn`, `Ngọc Anh`), ngày/giờ, chuyển khoản, và sức khỏe/đời sống.
- `benchmark_asr.py`: Trình đo chuẩn độc lập cho WER/CER tiếng Việt (UTF-8 NFC & Levenshtein S/D/I), bộ đệm vòng PCM16 16kHz (`30s` = `960 KB`), VAD Energy/ZCR chống ngắt câu giữa chừng, và adapter dò/chạy engine ASR cục bộ (`sherpa_onnx`, `vosk`, `faster_whisper`, `pywhispercpp`, `onnxruntime`).
- `results/poc_benchmark_report.json`: Báo cáo JSON có gắn nhãn nguồn gốc dữ liệu rõ ràng (`MEASURED_HOST`, `UPSTREAM_REFERENCE`, `NOT_MEASURED_DEVICE_REQUIRED`).
- `.gitignore`: Chặn tuyệt đối việc commit file âm thanh `.wav/.pcm`, mô hình `.onnx/.bin/.tflite`, hoặc virtualenv trong `.cache/`.

## Cách chạy kiểm định

### 1. Chạy PoC Benchmark Python (không cần cài thêm package toàn cục)
```powershell
python tools/voice_asr_poc/benchmark_asr.py
```

*(Tùy chọn)* Khi mạng tải được package/model về cache cục bộ bị gitignore (`.cache/venv` & `.cache/models`):
```powershell
python -m venv tools/voice_asr_poc/.cache/venv
tools/voice_asr_poc/.cache/venv/Scripts/python.exe -m pip install --only-binary=:all: sherpa-onnx vosk==0.3.41
python tools/voice_asr_poc/benchmark_asr.py --bootstrap
```

### 2. Chạy kiểm thử Corpus NLP trên Dart (`VoiceFinancialNlpEngine` & `SmartOmniIntentParser`)
```powershell
flutter test --no-pub test/unit/voice_vietnamese_corpus_nlp_test.dart
```

---

## Tổng hợp kết quả & Phân tách nguồn gốc trung thực

### A. Thực đo trên máy host (`MEASURED_HOST`)

#### 1. Đường ống âm thanh PCM16 16kHz & Adaptive Energy/ZCR VAD (`36` câu)
- **Định dạng**: `16,000 Hz`, Mono, `16-bit PCM` (`20 ms` / `320` mẫu mỗi khung).
- **Dung lượng Ring Buffer 30 giây**: `960,000 bytes` (`938.36 KB` peak tracemalloc).
- **Độ trễ xử lý khung VAD (20ms)**: `P50 = 139.5 µs`, `P95 = 195.0 µs` (nhanh hơn `>100×` ngân sách thời gian thực `20,000 µs`).
- **Phát hiện bắt đầu nói (Speech Onset Lag)**: `P50 = 20.0 ms`, `P95 = 60.0 ms` (`36/36` câu).
- **Endpointing cuối câu (hangover `850 ms`)**: `P50 = 811.0 ms`, `P95 = 821.0 ms`.
- **Cắt nhầm lúc ngắt nghỉ giữa câu (`650 ms` pause ở `vi_07`, `vi_10`, `vi_29`)**: **`0 / 36`** (`0%`).

#### 2. Độ nhạy WER / CER với biến thể lỗi ASR mô phỏng (`108` cặp)
- **WER chuẩn (có dấu)**: `44.97%` | **WER bỏ dấu ASCII**: `19.31%`
- **CER chuẩn (có dấu)**: `19.11%` | **CER bỏ dấu ASCII**: `12.04%`

#### 3. Kiểm định Dart NLP trên toàn bộ 36 câu (`test/unit/voice_vietnamese_corpus_nlp_test.dart`)
- **Độ chính xác trích xuất số tiền**: `27 / 29` (`93.10%`)
- **Độ chính xác phân loại Intent**: `33 / 36` (`91.67%`)
- **Nhận diện mốc ngày/giờ**: `5 / 6` (`83.33%`)
- **Độ chính xác trích xuất số tiền trên 87 biến thể lỗi ASR**: `77 / 87` (`88.51%`)
- **Độ trễ chuẩn hóa số nói tiếng Việt (`normalizeSpokenVietnamese`)**: `P50 = 0.063 ms`, `P95 = 0.142 ms`
- **Độ trễ `VoiceFinancialNlpEngine.analyze`**: `P50 = 0.467 ms`, `P95 = 1.602 ms`
- **Độ trễ `SmartOmniIntentParser.parseDetailed`**: `P50 = 0.938 ms`, `P95 = 4.352 ms`

#### 4. Các khoảng trống NLP phát hiện ở baseline (cần xử lý ở Wave 2)
1. **Số thập phân nói sau chữ "triệu"** (`vi_06`, `vi_19`): `"một triệu hai"` được chuẩn hóa thành `"1 triệu hai"`, dẫn tới chỉ bóc `1.000.000 ₫` thay vì `1.200.000 ₫`.
2. **Chia nhóm theo tên không có số lượng đầu người trong `SmartOmniIntentParser`** (`vi_19`): `"Tiền điện nước một triệu hai chia cho Hòa, Minh và Lan"` được `VoiceFinancialNlpEngine.analyze` nhận đúng `groupBillSplit`, nhưng `SmartOmniIntentParser` lại rơi về `transaction:expense` vì regex `_splitCountRegex` chỉ bắt `\d{1,2}`.
3. **Từ khóa nạp ví giữa hai ví/ngân hàng** (`vi_28`): `"Nạp 300 nghìn từ BIDV sang ZaloPay"` có `sourceWalletHint = BIDV`, `destinationWalletHint = ZaloPay`, nhưng `_inferFinancialSubtype` chỉ kiểm tra chuỗi `"nap sang"` liền nhau nên phân loại thành `expense` thay vì `transfer`.
4. **Lịch khám không bắt đầu bằng chữ "khám"** (`vi_31`): `"Đi khám răng cuối tuần này"` chưa khớp `_containsScheduleCue` (chỉ kiểm tra `kham ` ở đầu câu hoặc `kham luc/vao/\d`).
5. **Xung đột bỏ dấu `!gấp` vs `gặp`** (`vi_33`): `"Cần làm báo cáo tài chính cho Minh trước 17 giờ hôm nay !gấp"` bị `folded.contains('gap')` trong `_containsScheduleCue` hiểu nhầm `!gấp` thành `"gặp"` nên biến Task gấp thành `calendarEvent`.

---

### B. Tham chiếu Upstream đã xác minh & Kiểm toán Giấy phép (`UPSTREAM_REFERENCE`)

| Engine / Model | Kiến trúc | Dung lượng tải | Tham chiếu Upstream / WER | Giấy phép | Streaming | Hỗ trợ Wheel Py 3.14 (`win_amd64`) |
|---|---|---|---|---|---|---|
| `sherpa-onnx-zipformer-vi-30M-int8-2026-02-09` | Zipformer-30M RNN-T (INT8 ONNX) | `25.22 MB` (`.tar.bz2`) | Model tiếng Việt nhẹ nhất cho ARM64 trên `k2-fsa/sherpa-onnx` | Apache-2.0 (runtime) | Có | Có (`sherpa-onnx 2.0.3 cp314-win_amd64`) |
| `sherpa-onnx-zipformer-vi-int8-2025-04-20` | Zipformer RNN-T (INT8 ONNX) | `57.39 MB` (`.tar.bz2`) | Model Zipformer Vi dung lượng trung bình | Apache-2.0 (runtime) | Có | Có (`sherpa-onnx 2.0.3 cp314-win_amd64`) |
| `sherpa-onnx-moonshine-base-vi-quantized-2026-02-27` | Moonshine-Base Vi Quantized | `101.78 MB` (`.tar.bz2`) | Encoder-Decoder non-streaming | MIT / Apache-2.0 | Không | Có (`sherpa-onnx 2.0.3 cp314-win_amd64`) |
| `vosk-model-small-vn-0.4` | Kaldi TDNN-F + HCLG | `32.1 MiB` (`.zip`) | `15.70%` WER trên tập Vivos test (`alphacephei.com/vosk/models`) | Apache-2.0 | Có | Có (`vosk 0.3.41/0.3.45 win_amd64`) |
| `vosk-model-vn-0.4` | Kaldi TDNN-F Large | `78.0 MiB` (`.zip`) | `15.70%` WER trên tập Vivos test | Apache-2.0 | Có | Có (`vosk 0.3.41/0.3.45 win_amd64`) |
| `whisper-tiny-q5_1` / `faster-whisper-tiny-int8` | Transformer Seq2Seq 39M | `~32 MB` | Đa ngôn ngữ (cần VAD chunking, dễ mất dấu thanh tiếng Việt) | MIT | Giả lập | Có (`ctranslate2 4.9.1 cp314-win_amd64`) |

*(Lưu ý host: Đã xác minh trên PyPI các wheel `cp314-win_amd64` đều tồn tại, nhưng môi trường host không cài sẵn vào Python toàn cục và mạng sandbox giới hạn băng thông tải wheel/model lớn, nên các mục chạy suy luận ASR cục bộ được ghi nhận trung thực là `NOT_INSTALLED_IN_ENV`.)*

---

### C. Hạng mục cần thiết bị Android thật (`NOT_MEASURED_DEVICE_REQUIRED`)

Các chỉ số sau **CHƯA CHẠY (`NOT_RUN — Android Device Required`)** vì cần phần cứng Android vật lý:
- Độ ổn định jitter / buffer underrun của `AudioRecord` 16kHz Mono PCM16 trên thiết bị thật.
- Độ trễ partial transcript của `Android SpeechRecognizer` (`EXTRA_PREFER_OFFLINE` + gói ngôn ngữ `vi-VN` của OEM).
- RTF thực tế, Peak Native Heap và thermal throttling trên nhân ARM64 NEON big.LITTLE với `sherpa-onnx` Zipformer-30M INT8.
- Mức tăng kích thước APK/AAB (`libsherpa-onnx-jni.so` ABI `arm64-v8a` + `armeabi-v7a`).
