# Life OS — Super App Quản lý Cuộc sống & Gia đình

> **Kiến trúc:** Flutter `3.47` + **Feature-First Clean Architecture** + **BLoC Event-Driven (`flutter_bloc` + `bloc_concurrency`, 0% Cubit)** + `get_it` + `go_router` + **Firebase Authentication** + **Cloud Firestore** + **Firestore Security Rules** + **Design System “Tammy × Apple”**.

---

## 1. Điểm Nổi bật Cốt lõi

- **Privacy-by-Default (Riêng tư mặc định):** Tách biệt vật lý không gian dữ liệu cá nhân (`/users/{uid}/**`) và không gian gia đình (`/families/{familyId}/**`). Chủ gia đình (`owner`/`admin`) **tuyệt đối không thể đọc** ví ngân hàng riêng, giao dịch riêng hay lịch cá nhân (`PRIVATE_EVENT`) của thành viên khác.
- **Sổ cái Tài chính Cá nhân Chuyên sâu `VND` Nguyên đồng (`int` Minor Units):**
  - Không bao giờ dùng số thực dấu phẩy động (`double`) cho tính toán kế toán.
  - **15 Danh mục Đời sống Việt Nam** (*Ăn uống*, *Việc nhà & Gia dụng*, *Nhà cửa & Thuê nhà*, *Điện/Nước/Internet*, *Chợ & Mua sắm*, *Xe cộ & Di chuyển*, *Bảo dưỡng & Sửa xe*, *Sức khỏe & Giáo dục*, *Giải trí & Đăng ký*, *Hiếu hỉ & Đối ngoại*, *Trả nợ & Cho vay*, *Phí ngân hàng*...).
  - **Tách Giao dịch Đa Danh mục (`Split Transaction`):** Cho phép tách 1 biên lai thanh toán (VD: đi siêu thị `500.000 ₫`) vào nhiều khoản mục (*Ăn uống* `320.000 ₫` + *Việc nhà & Gia dụng* `180.000 ₫`), tự động hạch toán chính xác vào tỷ trọng phân tích và hạn mức ngân sách từng danh mục.
  - **Bộ Phân tích Sức khỏe Tài chính & Chia Thu nhập Thông minh (`IncomeAllocationEngine`):** Theo dõi Dòng tiền ròng (`Thu - Chi`), Tỷ lệ tiết kiệm (`%`), Tốc độ chi ngày (`Daily Burn Rate`), độ tin cậy nguồn chuẩn SePay (`VERIFIED` / `USER_CONFIRMED` / `PROVISIONAL`), và phân bổ lương/ngân quỹ theo 3 mô hình (*Cá nhân 50/30/20*, *Gia đình 60/20/20*, *Ở ghép 55/20/25*) không lệch dù chỉ `1 ₫` (Hamilton's Largest Remainder Method).
  - Phân tách rõ giao dịch chuyển tiền nội bộ giữa các ví (`transfer`) và trả dư nợ thẻ tín dụng (`creditCardPayment`) để **không bao giờ tính đúp chi tiêu**; cấm xóa cứng lịch sử giao dịch (`allow delete: if false`), hỗ trợ **Đảo bút toán (`reversal`)** nguyên tử.
- **Nhận diện Thông báo Ngân hàng VN có Kiểm duyệt (Chuẩn SePay Blueprint):**
  - Module Android Native Kotlin `BankNotificationListenerService` mặc định **TẮT**, chỉ hoạt động khi người dùng chủ động cấp quyền (Prominent Disclosure) và chọn allowlist từng ngân hàng (VCB, TCB, MB, ACB, VietinBank, TPBank, BIDV, VPBank).
  - Bộ lọc **Chặn OTP tuyệt đối** ngay trên thiết bị; khử trùng lặp đa nguồn & tự động nâng cấp giao dịch `PROVISIONAL` → `VERIFIED` mà không nhân đôi chi tiêu.
- **3 Không gian Cộng tác Thực tế: Gia đình · Ở ghép · Hội nhóm & Bộ Chia Tiền Tối giản Công nợ:**
  - Tùy chọn tạo không gian theo đúng bản chất vận hành: **Hộ Gia đình / Tổ ấm (`family`)**, **Ở ghép / Nhà trọ (`roommates`)**, hoặc **Hội nhóm / Chuyến đi (`group`)**.
  - **Chia Hóa đơn Chung 4 Chế độ (`SplitBillCalculator`):** Chia tiền ăn uống, việc nhà, điện nước, tiền trọ, du lịch theo *Chia đều* (tự xử lý số dư lẻ `1 ₫`), *Chia theo tỷ lệ `%`*, *Chia theo phần/hệ số (`Shares`)* hoặc *Chia số tiền cụ thể (`Exact`)*.
  - **Tối giản hóa Đồ thị Nợ (`DebtSimplifier`) & Mã CK Chuẩn SePay (`SEVQR LIFEOS ...`):** Tự động rút gọn nợ chéo nhiều chiều thành số lệnh chuyển khoản ít nhất, sinh mã nội dung chuyển khoản giữ nguyên tiền tố `SEVQR` và ghi nhận tất toán 1 chạm.
  - Quỹ riêng & Quỹ chung, Giao việc có đồng thuận (`proposed` → `accepted` / `declined` → `done` + lặp định kỳ), Phương tiện (`min(km, ngày)`), Hóa đơn định kỳ & Mua sắm chung.
- **Xác thực Đa phương thức & Hồ sơ Bảo mật (`/account-profile`):** Đăng nhập / Đăng ký 1 chạm bằng **Google (`google_sign_in 7.2.0` + Federated OAuth)**, Email/Mật khẩu có thanh đo độ mạnh theo thời gian thực, liên kết tài khoản chéo Google ↔ Email, xác thực Email và đổi mật khẩu bảo mật.
- **Cơ chế Tự động Cập nhật Phiên bản Mới (`OTA In-App Update` — `features/app_update`):** Tự động kiểm tra bản phát hành mới từ **GitHub Releases API** và **Cloud Firestore (`/app_config/release_manifest`)**, hiển thị thông báo kèm nhật ký thay đổi (Changelog), tải trực tiếp tệp APK có thanh tiến độ `0% → 100%`, kiểm tra mã băm toàn vẹn `SHA-256` và kích hoạt trình cài đặt hệ thống Android thông qua `FileProvider` an toàn.
- **Trợ lý Ghi Nhanh Ngôn ngữ Tự nhiên & Quỹ Dự phòng Khẩn cấp:** Nhập nhanh 1 dòng kiểu Việt Nam (*"ăn phở bò 65k"*, *"tiền điện 850k"*, *"nhận lương 18tr5"*) tự bóc tách số tiền, thu/chi và danh mục; tự động tính số tháng sống sót của **Quỹ dự phòng khẩn cấp**; tạo **Mã QR quyết toán nhóm chuẩn VietQR / SePay** và **Bảng Cân bằng Việc nhà** giữa các thành viên.
- **Design System “Tammy × Apple” (UI/UX Pro Max) & Bộ Hình ảnh Nano Banana:** Bảng màu semantic Light (`#0B7A2A` / `#F2F4F7`) & Dark (`#19C23E` / `#000000`) + chế độ Tương phản cao WCAG 2.2 AA, `FontFeature.tabularFigures()`, biểu đồ vòng GPU `ProDonutChart`, **Splash Screen đa tầng**, **App Logo & Bộ 8 Minh họa 3D Frosted Liquid Glass** (`assets/images/`), chuyển đổi tự động giữa Floating Glass Capsule Dock (Mobile) và NavigationRail Split View (Tablet/Web).

---

## 2. Cấu trúc Thư mục (Feature-First Clean Architecture)

```text
lib/
├── main.dart
├── bootstrap.dart
├── firebase_options.dart
├── app/
│   ├── app.dart
│   ├── app_router.dart
│   ├── app_bloc_observer.dart
│   ├── config/firebase_config.dart
│   └── theme/ (app_colors.dart, app_spacing.dart, app_typography.dart, app_theme.dart, theme_bloc.dart)
├── core/
│   ├── di/dependency_injection.dart
│   ├── error/ (failure.dart, app_exception.dart, error_mapper.dart)
│   ├── security/bank_notification_parser.dart
│   ├── services/android_notification_bridge.dart
│   ├── usecases/usecase.dart
│   ├── utils/ (vnd_amount.dart, stream_combiner.dart)
│   └── widgets/status_widgets.dart
└── features/
    ├── app_update/      (domain / data / presentation — GitHub Releases + Cloud OTA Updater)
    ├── authentication/  (domain / data / presentation — Google OAuth + Email + Profile Security)
    ├── financial_ai/    (domain / data / presentation — On-Device FastText INT8 + Personalized AI)
    ├── dashboard/       (domain / data / presentation)
    ├── transactions/    (domain / data / presentation)
    ├── budgets/         (domain / data / presentation)
    ├── family/          (domain / data / presentation)
    ├── calendar/        (domain / data / presentation)
    ├── tasks/           (domain / data / presentation)
    ├── vehicles/        (domain / data / presentation)
    └── notifications/   (domain / data / presentation)
```

---

## 3. Hướng dẫn Cài đặt & Chạy Ứng dụng

### 3.1. Cài đặt thư viện
```bash
flutter pub get
```

### 3.2. Chạy với Firebase Local Emulator Suite (Khuyến nghị phát triển cục bộ — Miễn phí 100%)
Mở một cửa sổ terminal khởi động Auth (`9199`) và Firestore (`8188`) Emulator:
```bash
firebase emulators:start --only auth,firestore --project demo-life-os
```
Mở cửa sổ thứ hai để chạy ứng dụng Flutter (Web hoặc Android):
```bash
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
```

### 3.3. Kết nối Firebase Cloud Project Thật (Gói Spark Miễn phí)
1. Đăng nhập lại Firebase CLI trên trình duyệt:
   ```bash
   firebase login --reauth
   ```
2. Tạo hoặc chọn project và sinh cấu hình FlutterFire chính thức:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure --project=<YOUR_FIREBASE_PROJECT_ID>
   firebase deploy --only firestore:rules,firestore:indexes --project <YOUR_FIREBASE_PROJECT_ID>
   ```
3. Bật **Email/Password** trong mục **Authentication → Sign-in method** trên Firebase Console, sau đó chạy `flutter run`.

---

## 4. Kiểm thử Tự động & Phân tích Tĩnh

```bash
# Kiểm tra phân tích tĩnh & quy tắc lint
flutter analyze

# Chạy toàn bộ Unit, Domain, Architecture Guard (0% Cubit), BLoC, Widget & Integration Tests
flutter test --reporter expanded

# Kiểm thử trực tiếp tập quy tắc bảo mật firestore.rules trên Firebase Firestore Emulator thật
firebase emulators:exec --only firestore --project demo-life-os "node firebase/rules_tests/run_emulator_rules_tests.mjs"
```

---

## 5. Agent AI Nội bộ Trên Thiết Bị & Hệ thống Đa Luồng 6 Ban Antigravity v6.1

### 5.1. Agent AI Nội bộ Trên Thiết Bị (`FastText INT8` + `SmartOmni NLU` + Học Cá nhân hóa)
- **Phân loại siêu nhẹ Offline (`lib/features/financial_ai/`):** Tích hợp mô hình nhị phân lượng tử hóa **`FastText INT8`** (hỗ trợ FFI tốc độ cao và bộ giải mã thuần Dart đa nền tảng) kết hợp chuẩn hóa văn bản tiếng Việt có dấu/không dấu/viết tắt (`65k`, `1tr2`, `18tr5`).
- **Điều phối Đa Tác vụ `SmartOmni NLU` (`lib/core/utils/smart_omni_intent_parser.dart`):** Tự động bóc tách ý định từ một dòng nhập tự nhiên thành giao dịch thu/chi, chuyển ví, việc cần làm, sự kiện lịch hoặc nhắc nhở định kỳ mà không bắt buộc gửi dữ liệu thô lên đám mây.
- **Học Cá nhân hóa Bảo toàn Riêng tư (`ConfidencePolicyEngine`):** Tự động ghi nhận thói quen sửa danh mục và từ khóa thương nhân của từng người dùng ngay trên thiết bị, nâng dần độ chính xác gợi ý theo thời gian.

### 5.2. Hệ thống Đa Luồng 6 Ban Antigravity v6.1 (`AGENTS.md` + `.agents/agents/`)
Dự án vận hành quy trình điều phối song song **Đội kỹ thuật 6 ban** gồm **Engineering Lead** và 5 custom subagents đồng bộ (`architect`, `developer`, `qa`, `creative`, `release`). Mỗi worker CLI chạy cô lập trên Git worktree riêng `agy/<run>/<task>`, kiểm tra nghiêm ngặt `agy models`, tự xuất `.diff.patch`, hậu kiểm `owned_paths` (`SCOPE_VIOLATION` exit `4` nếu ghi ngoài phạm vi) và hỗ trợ tự dọn worktree sạch.

```bash
# Kiểm tra preflight wave 4 ban (schema, known roles, single-writer & danh sách model thật từ `agy models`)
python scripts/parallel_models.py --tasks examples/parallel-tasks.json --dry-run

# Chạy song song wave kiểm toán chỉ đọc và tự động dọn sạch worktree/nhánh tạm khi hoàn tất
python scripts/parallel_models.py --tasks examples/parallel-tasks.json --jobs 4 --base HEAD --cleanup-clean-worktrees
```

---

## 6. Tài liệu Kỹ thuật Đầy đủ (`docs/`)
- [PROJECT_AUDIT.md](docs/PROJECT_AUDIT.md) — Khảo sát tài liệu & hiện trạng workspace.
- [PRODUCT_REQUIREMENTS.md](docs/PRODUCT_REQUIREMENTS.md) & [USER_FLOWS.md](docs/USER_FLOWS.md) — Yêu cầu sản phẩm & luồng nghiệp vụ.
- [MVP_SCOPE.md](docs/MVP_SCOPE.md) — Phạm vi tính năng P0/P1 & tiêu chí hoàn thành.
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) & [DECISIONS.md](docs/DECISIONS.md) — Kiến trúc Clean Architecture, BLoC Concurrency & ADRs.
- [PERSONAL_GROUP_FAMILY_FINANCE.md](docs/PERSONAL_GROUP_FAMILY_FINANCE.md) — Nghiên cứu sâu & đặc tả toán học: Tài chính Cá nhân (SePay Standard), Hội nhóm/Ở ghép & Gia đình, Split Transaction, Phân bổ Thu nhập & Tối giản Công nợ.
- [FIRESTORE_SCHEMA.md](docs/FIRESTORE_SCHEMA.md) & [FIREBASE_SECURITY.md](docs/FIREBASE_SECURITY.md) — Thiết kế NoSQL & bảo mật dữ liệu.
- [TEST_REPORT.md](docs/TEST_REPORT.md) & [MVP_FINAL_REPORT.md](docs/MVP_FINAL_REPORT.md) — Kết quả kiểm thử, build & bàn giao MVP.
