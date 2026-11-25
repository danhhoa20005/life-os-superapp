# LifeOS Super App — Danh Mục Toàn Bộ Màn Hình (Screen Inventory)

Tổng hợp đầy đủ toàn bộ các màn hình và modal đang hoạt động trong `lib/app/app_router.dart` và `lib/core/widgets/`.

---

## 1. Luồng Khởi Động & Xác Thực (Auth & FTUE)

| ID | Route | Widget / File | Vai trò |
|---|---|---|---|
| `AUTH-01` | `/splash` | `SplashPage` (`auth_pages.dart`) | Khởi tạo phiên đăng nhập và tải cấu hình giao diện cục bộ |
| `AUTH-02` | `/welcome` | `WelcomePage` (`auth_pages.dart`) | Giới thiệu giá trị cốt lõi LifeOS cho người dùng mới |
| `AUTH-03` | `/login` | `LoginPage` (`auth_pages.dart`) | Đăng nhập Email/Mật khẩu hoặc Google |
| `AUTH-04` | `/register` | `RegisterPage` (`auth_pages.dart`) | Tạo tài khoản mới với kiểm tra đầu vào trực tiếp |
| `AUTH-05` | `/forgot-password` | `ForgotPasswordPage` (`auth_pages.dart`) | Gửi liên kết đặt lại mật khẩu qua Email Firebase thật |
| `AUTH-06` | `/verify-otp` | `VerifyOtpPage` (`auth_pages.dart`) | Hướng dẫn xác nhận email đặt lại mật khẩu (đã loại bỏ mã giả) |
| `AUTH-07` | `/reset-password` | `ResetPasswordPage` (`auth_pages.dart`) | Hướng dẫn hoàn tất đổi mật khẩu qua liên kết bảo mật (đã loại bỏ toast giả) |
| `AUTH-08` | `/onboarding` | `OnboardingPrivacyPage` (`auth_pages.dart`) | FTUE ngắn, có nút `Bỏ qua` theo tài khoản, chọn nhu cầu quan tâm (Cold Start) |

---

## 2. Năm Trụ Điều Hướng Chính (4 Nhánh Shell + Danh Bạ Menu 1 Chạm)

| ID | Route | Widget / File | Vai trò |
|---|---|---|---|
| `TAB-01` | `/today` | `TodayPage` (`today_page.dart`) | Dashboard thích ứng: Số dư (ẩn/hiện), Việc cần chú ý, Gợi ý theo ngữ cảnh 2.0, Lịch sắp tới, Tiện ích ghim |
| `TAB-02` | `/finance` | `FinancePage` (`finance_page.dart`) | Sổ thu chi, ví cá nhân, ngân sách, quỹ, phân tích & công cụ tài chính |
| `TAB-03` | `/planning` | `PlanningPage` (`planning_page.dart`) | Lịch trình, sự kiện đồng bộ lịch máy, danh sách công việc & công cụ thời gian |
| `TAB-04` | `/family` | `FamilyPage` (`family_page.dart`) | Không gian gia đình, chia tiền nhóm, công nợ, thành viên, mua sắm & tiện ích nhà |
| `TAB-05` | `/menu` & `/super-app-hub` | `SuperAppDirectoryPage` (`super_app_directory_page.dart`) | Danh bạ 23 dịch vụ 360° truy cập 1 chạm từ nút `Menu` trên thanh đỉnh |

---

## 3. Phân Hệ Tài Chính, AI & Tự Động Hóa

| ID | Route | Widget / File | Vai trò |
|---|---|---|---|
| `FIN-01` | `/auto-tx-review` | `AutoTransactionReviewPage` (`auto_tx_and_report_pages.dart`) | Rà soát, xác nhận hoặc từ chối giao dịch từ thông báo ngân hàng |
| `FIN-02` | `/finance-report` | `FinanceReportPage` (`auto_tx_and_report_pages.dart`) | Báo cáo thu chi theo tháng, xu hướng dòng tiền & xuất dữ liệu |
| `FIN-03` | `/financial-ai` | `FinancialAiAssistantPage` (`financial_ai_assistant_page.dart`) | Nhập câu tự nhiên đa tác vụ Offline FastText + tùy chọn kết nối Gemini |
| `FIN-04` | `/financial-ai-settings` | `FinancialAiSettingsPage` (`financial_ai_settings_page.dart`) | Cấu hình lá chắn quyền riêng tư AI và khóa Gemini tùy chọn (Keystore) |
| `FIN-05` | `/automation-studio` | `AutomationStudioPage` (`automation_studio_page.dart`) | Bật/tắt quy tắc tự động hóa (lương, xăng xe, hóa đơn) kèm nhật ký hoàn tác |
| `FIN-06` | `/wealth-tools` | `WealthToolsPage` (`wealth_tools_page.dart`) | Chia hóa đơn theo món, tính lãi vay và kế hoạch tiết kiệm dài hạn |
| `FIN-07` | `/subscriptions-warranty` | `SubscriptionsWarrantyPage` (`subscriptions_warranty_page.dart`) | Theo dõi gói đăng ký định kỳ và thời hạn bảo hành sản phẩm |

---

## 4. Phân Hệ Lịch Trình, Gia Đình & Đời Sống

| ID | Route | Widget / File | Vai trò |
|---|---|---|---|
| `LIFE-01` | `/tasks-board` | `TasksBoardPage` (`tasks_board_page.dart`) | Bảng công việc cá nhân & gia đình có bộ lọc hạn và trạng thái |
| `LIFE-02` | `/calendar-event/:id` | `EventDetailPage` (`event_detail_and_alarm_pages.dart`) | Chi tiết lịch hẹn, nhắc nhở và đồng bộ lịch thiết bị |
| `LIFE-03` | `/alarm-center` | `AlarmCenterPage` (`event_detail_and_alarm_pages.dart`) | Báo thức và nhắc giờ hằng ngày |
| `LIFE-04` | `/habits-focus` | `HabitsFocusPage` (`habits_focus_page.dart`) | Theo dõi thói quen tích cực & đồng hồ tập trung Pomodoro |
| `LIFE-05` | `/family-funds` | `FamilyFundsPage` (`family_funds_page.dart`) | Quỹ chung gia đình, đề xuất chi 9 trạng thái, duyệt chéo và đối soát |
| `LIFE-06` | `/family-documents` | `FamilyDocumentsPage` (`family_documents_page.dart`) | Kho giấy tờ gia đình (CCCD, hộ chiếu, BHYT, hợp đồng) có che mặc định |
| `LIFE-07` | `/assets` | `AssetsPage` (`assets_page.dart`) | Quản lý xe cộ, nhật ký đổ xăng, lịch bảo dưỡng theo OEM & hóa đơn định kỳ |
| `LIFE-08` | `/health-hub` | `HealthMedicalHubPage` (`health_medical_hub_page.dart`) | Nhắc uống thuốc, theo dõi nước uống & thẻ y tế khẩn cấp |
| `LIFE-09` | `/kitchen-groceries` | `KitchenGroceriesPage` (`kitchen_groceries_page.dart`) | Giỏ đi chợ, tủ lạnh và gợi ý thực đơn |
| `LIFE-10` | `/home-living` | `HomeLivingUtilitiesPage` (`home_living_utilities_page.dart`) | Tính tiền điện 5 bậc EVN, nước & chi phí nhà cửa |
| `LIFE-11` | `/smart-notes-hub` | `SmartNotesSalaryPage` (`smart_notes_salary_page.dart`) | Ghi chú nhanh, danh sách kiểm tra & tính lương thực nhận Gross–Net |
| `LIFE-12` | `/social-ledger-travel` | `SocialLedgerTravelPage` (`social_ledger_travel_page.dart`) | Sổ hiếu hỷ, sự kiện & quỹ chuyến đi |
| `LIFE-13` | `/pro-utilities` | `ProUtilitiesHubPage` (`pro_utilities_hub_page.dart`) | Trung tâm công cụ tài chính & năng suất nâng cao |
| `LIFE-14` | `/life-timeline` | `LifeTimelinePage` (`life_timeline_page.dart`) | Dòng thời gian hợp nhất mọi sự kiện đời sống & tài chính |

---

## 5. Trung Tâm Thông Báo, Cài Đặt & Modal Toàn Cục

| ID | Route / Trigger | Widget / File | Vai trò |
|---|---|---|---|
| `SYS-01` | `/activity-notifications` | `ActivityNotificationsPage` (`activity_and_settings_pages.dart`) | Trung tâm Thông báo 4 tầng, phân nhóm theo loại, hoãn đa mức & cài đặt Giờ yên lặng |
| `SYS-02` | `/notifications-privacy` | `NotificationsPrivacyPage` (`notifications_privacy_page.dart`) | Kết nối nhận diện thông báo ngân hàng, VietQR & quyền riêng tư |
| `SYS-03` | `/settings-hub` | `SettingsHubPage` (`activity_and_settings_pages.dart`) | Cài đặt tổng hợp: tài khoản, quyền thiết bị, giao diện, thông báo, sao lưu |
| `SYS-04` | `/account-profile` | `AccountProfilePage` (`account_profile_page.dart`) | Hồ sơ cá nhân, che PII mặc định, đổi PIN & xóa tài khoản an toàn |
| `SYS-05` | `/home-widgets` | `HomeWidgetsStudioPage` (`home_widgets_studio_page.dart`) | Cấu hình tiện ích màn hình chính Android |
| `SYS-06` | `/motion-gallery` | `MotionGalleryPage` (`motion_gallery_page.dart`) | Thư viện hiệu ứng (chỉ mở khi người dùng chủ động tìm kiếm/chọn) |
| `MOD-01` | Nút `+` trung tâm | `QuickCreateHubSheet` (`quick_create_hub_sheet.dart`) | Tạo nhanh 3 chế độ (10 Quick Actions + Ngôn ngữ tự nhiên + Giọng nói) |
| `MOD-02` | Nút `🔍` thanh đỉnh | `OmniCommandPaletteSheet` (`omni_command_palette_sheet.dart`) | Tìm kiếm toàn ứng dụng có đồng nghĩa, phân nhóm & lịch sử tìm kiếm |
| `MOD-03` | Nút `Nói` | `VoiceSmartCaptureSheet` (`voice_smart_capture_sheet.dart`) | Ghi nhanh giọng nói có xem trước, sửa transcript & nhập thủ công dự phòng |
| `MOD-04` | Nút `Aa` thanh đỉnh | `showLifeOsAppearanceSheet` (`lifeos_design_system.dart`) | Giao diện Sáng/Tối, Cỡ chữ, Tương phản cao, Giảm chuyển động |
| `MOD-05` | Logo / Vuốt cạnh trái | `LifeOsLogoSideDrawer` (`lifeos_logo_side_drawer.dart`) | Ngăn kéo điều hướng phụ & lối tắt cá nhân |
| `MOD-06` | Theo ngữ cảnh / Cài đặt | `LifeOsPermissionsPopup` & `LifeOsPermissionRationaleDialog` | Cấp quyền đúng lúc với 4 câu hỏi minh bạch dữ liệu |
