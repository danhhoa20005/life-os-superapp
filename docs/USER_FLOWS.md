# LUỒNG NGƯỜI DÙNG CHI TIẾT (USER FLOWS)

## 1. Luồng Xác thực & Khởi tạo Không gian Riêng tư
```mermaid
flowchart LR
    Splash["Khởi động App / Kiểm tra Phiên"] -->|Chưa đăng nhập| Login["Đăng nhập / Đăng ký / Quên MK"]
    Login -->|Thành công lần đầu| Onboarding["Onboarding Quyền riêng tư<br/>(Tạo Ví tiền mặt + Danh mục chuẩn VN)"]
    Splash -->|Đã đăng nhập & Đã Onboarding| Today["Màn hình Hôm nay (5 Tabs)"]
    Onboarding --> Today
```

## 2. Luồng Ghi nhận Tài chính, Chuyển ví & Duyệt Giao dịch Thông báo
```mermaid
flowchart TD
    Source["Nguồn phát sinh"] -->|Nhập thủ công| Form["Form Giao dịch (Thu / Chi / Chuyển ví / Trả thẻ)"]
    Source -->|Thông báo Ngân hàng Android đã cấp Consent| Parser["Local Parser + Bộ lọc Chặn OTP"]
    Parser -->|Hợp lệ & Không trùng| Prov["Giao dịch PROVISIONAL chờ duyệt"]
    Prov -->|Người dùng bấm Xác nhận / Sửa danh mục| Confirmed["USER_CONFIRMED + Cập nhật Số dư Ví"]
    Prov -->|Nguồn API xác thực trùng khớp| Verified["Nâng cấp lên VERIFIED (Không nhân đôi)"]
    Form -->|operationId chống bấm đúp| Confirmed
    Confirmed -->|Hoàn tiền / Hủy| Reversal["Tạo Bút toán Đảo (Reversal) bù trừ số dư"]
```

## 3. Luồng Phối hợp Gia đình, Quỹ Chung & Giao việc Bảo toàn Đời tư
```mermaid
flowchart TD
    CreateFam["Tạo Hộ gia đình / Sinh Mã mời"] --> Join["Thành viên nhập Mã mời tham gia"]
    Join --> FundFlow["Quỹ Chung: Ghi nhận đóng góp → Đề xuất chi → Quản trị quỹ duyệt"]
    Join --> TaskFlow["Giao việc: Trạng thái proposed → Assignee Chấp nhận / Từ chối → Hoàn thành (Tự lặp kỳ mới)"]
    Join --> CalFlow["Lịch: PRIVATE_EVENT lưu riêng tại users/uid (Chủ gia đình không thấy) | SHARED_EVENT lưu tại families/fid"]
    Join --> LeaveFlow["Rời Gia đình: Xóa uid khỏi memberIds → Mất quyền đọc dữ liệu nhóm ngay lập tức"]
```

## 4. Luồng Phương tiện, Bảo dưỡng & Hóa đơn Định kỳ
```mermaid
flowchart LR
    AddVehicle["Tạo Hồ sơ Xe (Che biển số khi chia sẻ)"] --> UpdateOdo["Cập nhật Odometer (km)"]
    AddVehicle --> AddMaint["Ghi nhận Bảo dưỡng (Chu kỳ km + Chu kỳ ngày + Chi phí)"]
    UpdateOdo & AddMaint --> CalcDue["Tính hạn tiếp theo theo min(km còn lại, ngày còn lại)"]
    CalcDue --> Alert["Hiển thị Cảnh báo Sắp đến hạn / Quá hạn trên Tab Hôm nay"]
```
