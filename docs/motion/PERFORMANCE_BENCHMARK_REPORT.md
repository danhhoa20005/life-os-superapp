# Báo Cáo Thực Nghiệm Hiệu Năng — LifeOS Motion Design System v2.0

- **Mã kiểm định:** `LIFEOS-MOTION-BENCH-2026-11-24`
- **Nhánh kiểm thử:** `agy/motion-v2/q01-qa-and-benchmark` (từ commit nền `d71eea2`)
- **Bộ đo tự động tái lập được:** [`test/features/motion_gallery/motion_performance_benchmark_test.dart`](../../test/features/motion_gallery/motion_performance_benchmark_test.dart)

---

## 1. Môi Trường Đo Thực Nghiệm & Giới Hạn Trung Thực

| Thông số môi trường | Giá trị thực tế |
| :--- | :--- |
| **Hệ điều hành máy trạm** | Windows (PowerShell / Host Desktop CPU) |
| **SDK thực thi** | `Flutter 3.47.0` (channel `stable`) · `Dart 3.13.0` · `DevTools 2.60.0` |
| **Chế độ biên dịch khi đo** | Headless `TestWidgetsFlutterBinding` trên **Dart JIT VM (Debug/Test mode)** — chưa bật tối ưu hóa biên dịch trước `AOT --profile / --release` |
| **Khung hình mô phỏng** | `360 × 800` logical px (`devicePixelRatio = 1.0`), đã chạy warm-up cache font & theme trước khi bấm giờ `Stopwatch` |
| **Đo FPS GPU / Impeller Raster trên điện thoại vật lý** | **`NOT RUN`** *(Yêu cầu cắm thiết bị Android `60Hz/120Hz` hoặc iPhone vật lý chạy `flutter run --profile`; máy trạm hiện chưa kết nối thiết bị ngoại vi qua USB/ADB)* |

> **Lưu ý đọc số liệu:** Trong môi trường `flutter test` (Dart JIT + bật toàn bộ `assert` kiểm tra cây RenderObject), chi phí CPU mỗi khung luôn cao hơn bản biên dịch `AOT --profile` trên thiết bị thật từ `2.5× – 4×`. Do đó, các tỷ lệ cải thiện tương đối (**Trước vs Sau**) phản ánh trực tiếp hiệu quả kiến trúc, còn chi phí tuyệt đối (`µs/tick`) là ngưỡng cận trên bảo thủ.

---

## 2. Kết Quả Đối Chiếu Trước vs Sau Tối Ưu Kiến Trúc

### 2.1. Kiến trúc 1 — Khởi tạo Phòng Trưng Bày `66` Mẫu Chuyển Động (`#01`..`#66`)

- **Trước tối ưu (Eager `Column` không ảo hóa):** Dựng đồng loạt toàn bộ `66` thẻ mẫu tương tác (gồm các bộ điều khiển lò xo, `CustomPainter`, Lottie, Sprite Sheet và GLSL Shader fallback) ngay ở khung hình đầu tiên.
- **Sau tối ưu (`MotionGalleryPage` với `SliverList.builder` + `RepaintBoundary` + hoạt ảnh hữu hạn):** Chỉ khởi tạo các phần tử nằm trong vùng nhìn thấy (`viewport` + `cacheExtent`) của `CustomScrollView` và cô lập từng thẻ mẫu trong `RepaintBoundary`.

| Chỉ số đo thực tế (`360×800`, trung vị 3 lần chạy độc lập) | Trước tối ưu (`Column` đồng loạt) | Sau tối ưu (`SliverList.builder` ảo hóa) | Mức cải thiện thực nghiệm |
| :--- | ---: | ---: | ---: |
| **Số thẻ mẫu phải mount ngay khung đầu** | `66 / 66` thẻ | `1 / 66` thẻ *(cùng Hero & Toolbar)* | **Giảm `98.5%` số cây mẫu trên RAM** |
| **Thời gian mount + pump khung đầu (tiến trình đơn)** | `951.24 ms` | `181.70 ms` | **Nhanh hơn `5.24×` (`-80.9%` độ trễ)** |
| **Thời gian mount + pump khung đầu (chạy song song tải cao)** | `1,046.64 ms` | `200.62 ms` | **Nhanh hơn `5.22×`** |

---

### 2.2. Kiến trúc 2 — Vầng Sóng Âm AI Voice (`30` Sự Kiện Biên Độ RMS Liên Tiếp)

- **Trước tối ưu (`setState` toàn khung Form mỗi sự kiện RMS):** Mỗi tín hiệu `VoiceRmsSignal(rmsDb)` từ microphone gọi `setState()` ở cấp Sheet, buộc toàn bộ cây giao diện (Header, `TextField` câu nói, danh sách Chip ví, 4 thẻ dự thảo giao dịch và cụm nút hành động) phải `build()` lại `30` lần liên tiếp.
- **Sau tối ưu (`ValueNotifier<double>` + `RepaintBoundary` + `CustomPainter` cô lập):** Tín hiệu `rmsDb` chỉ cập nhật `_rmsNotifier.value`, kích hoạt vẽ lại riêng vùng `CustomPaint` cao `22px–28px` nằm bên trong `RepaintBoundary`; toàn bộ cây Form xung quanh giữ nguyên `0` lần rebuild.

| Chỉ số đo thực tế (`30` nhịp RMS × `16ms`) | Trước tối ưu (`setState` toàn Form) | Sau tối ưu (`ValueNotifier` + `RepaintBoundary`) | Mức cải thiện thực nghiệm |
| :--- | ---: | ---: | ---: |
| **Số lần rebuild cây Form cha trong 30 nhịp RMS** | `30` lần | **`0` lần** | **Triệt tiêu `100%` rebuild thừa** |
| **Tổng thời gian CPU xử lý 30 sự kiện RMS** | `1,120.69 ms` | `59.01 ms` | **Nhanh hơn `18.99×` (`-94.7%` CPU)** |
| **Chi phí trung vị mỗi sự kiện RMS (`µs/event`)** | `34,274.0 µs` (`34.27 ms`) | **`1,817.5 µs` (`1.82 ms`)** | **Từ vượt ngưỡng 60Hz (`>16.67ms`) xuống đạt chuẩn 120Hz (`<8.33ms`)** |

---

## 3. Chi Phí Mỗi Khung Hình (`µs/tick`) Của Động Cơ Vật Lý & Hạt

Đo trực tiếp qua `Stopwatch` trên từng nhịp `tester.pump(16ms)` ở chế độ Dart JIT VM:

| Thành phần chuyển động | Quy mô bài đo | Trung vị (`Median`) | Phân vị thứ 95 (`P95`) | Đánh giá so với ngân sách 60Hz (`16,667 µs`) / 120Hz (`8,333 µs`) |
| :--- | :--- | ---: | ---: | :--- |
| **Giải tích `SpringSimulation` thuần (`x(t) + dx(t)`)** | `1,000` bước nội suy vị trí + vận tốc | **`3.67 µs / bước`** (`3,669 ns`) | — | Chiếm `< 0.05%` ngân sách khung 120Hz; chi phí toán học gần như bằng 0 |
| **`LifeOsSpringController` (1D) + `LifeOsSpring2DController` (2D) kèm đổi đích giữa chừng (`retargeting`)** | `180` khung liên tiếp, đảo đích mỗi `6` khung bảo toàn liên tục $C^0/C^1$ | **`1,225.0 µs / tick`** (`1.23 ms`) | **`7,279.0 µs / tick`** (`7.28 ms`) | **Đạt chuẩn `< 8.33 ms` (120Hz)** ngay cả ở `P95` trên JIT VM |
| **`LifeOsParticleBurst` (`28` hạt Struct-of-Arrays tiền cấp phát)** | `4` đợt nổ × `50` khung (`200` ticks), `0` cấp phát mảng mới mỗi khung | **`1,526.0 µs / tick`** (`1.53 ms`) | **`8,926.0 µs / tick`** (`8.93 ms`) | Trung vị chiếm `9.2%` khung 60Hz; không phát sinh GC pause do tiền cấp phát mảng phẳng (`_angles`, `_speeds`, `_radii`, `_colors`) |

---

## 4. Bảng Tổng Hợp Trạng Thái Kiểm Chứng Hiệu Năng & Rò Rỉ Tài Nguyên

| Hạng mục kiểm chứng | Phương pháp | Kết quả |
| :--- | :--- | :--- |
| **Ảo hóa danh sách 66 mẫu (`SliverList.builder`)** | Đo `Stopwatch` thực tế trong `motion_performance_benchmark_test.dart` | **PASS** (`5.24×` nhanh hơn) |
| **Cô lập sóng âm AI Voice (`ValueNotifier` + `RepaintBoundary`)** | Đo `Stopwatch` + đếm `build()` trong `motion_performance_benchmark_test.dart` | **PASS** (`18.99×` nhanh hơn, `0` form rebuild) |
| **Chi phí tick lò xo đổi đích giữa chừng & 28 hạt SoA** | Đo `µs/tick` trên 180–200 khung hình thực tế | **PASS** (`1.23 ms` & `1.53 ms` median) |
| **Dừng Ticker tức thì khi `TickerMode(enabled: false)` & Reduce Motion** | Kiểm thử tự động trong `advanced_motion_design_system_test.dart` & `pressable_widget_test.dart` | **PASS** (`!isAnimating`, `0` vòng lặp vô tận) |
| **Không rò rỉ `Ticker` / `AnimationController` khi `dispose()` giữa chừng** | `tester.verifyTickersWereDisposed()` khi hủy widget ở `24ms` đang bay | **PASS** (`0` ticker rò rỉ) |
| **Đo Raster / Impeller GPU Frame Timeline trên điện thoại Android/iOS vật lý** | `flutter run --profile` + Flutter DevTools Performance Overlay | **`NOT RUN`** *(Chưa cắm thiết bị vật lý Android/iOS)* |
