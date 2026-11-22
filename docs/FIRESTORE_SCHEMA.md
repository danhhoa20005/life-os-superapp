# THIẾT KẾ CƠ SỞ DỮ LIỆU CLOUD FIRESTORE (FIRESTORE SCHEMA)

> **Nguyên tắc NoSQL:** Phân tách vật lý giữa không gian cá nhân (`users/{uid}/...`) và không gian hộ gia đình (`families/{familyId}/...`), không tạo một tài liệu khổng lồ chứa mảng giao dịch vô hạn, tận dụng `includeMetadataChanges: true` để phân biệt dữ liệu lưu tạm cục bộ (`hasPendingWrites`) với dữ liệu đã xác nhận trên máy chủ.

---

## 1. Không gian Cá nhân (`users/{userId}`)

### 1.1. `users/{userId}`
- **Mục đích:** Hồ sơ người dùng, trạng thái onboarding và tùy chọn chia sẻ rảnh/bận.
- **Cấu trúc trường:** `id` (`string`), `email` (`string`), `fullName` (`string`), `timezone` (`string`, mặc định `Asia/Ho_Chi_Minh`), `onboardingCompleted` (`bool`), `availabilityOptIn` (`bool`, mặc định `false`), `activeFamilyId` (`string?`), `schemaVersion` (`int`), `createdAt` (`Timestamp`), `updatedAt` (`Timestamp`).
- **Quyền truy cập:** Chỉ chính chủ `request.auth.uid == userId`.

### 1.2. `users/{userId}/wallets/{walletId}`
- **Mục đích:** Tài khoản tiền mặt, ngân hàng tham chiếu hoặc thẻ tín dụng riêng của cá nhân.
- **Cấu trúc trường:** `id`, `ownerId`, `name`, `type` (`cash` | `bank` | `creditCard`), `bankCode` (`string?`), `maskedAccount` (`string?`), `balanceMinor` (`int` — đơn vị đồng nguyên VND), `isEstimatedBalance` (`bool` — `true` khi tính từ nguồn quan sát thông báo/nhập tay, không mạo nhận số dư ngân hàng thời gian thực), `createdAt`, `updatedAt`.
- **Quyền truy cập:** Chỉ `ownerId == request.auth.uid`. Quản trị gia đình tuyệt đối không đọc được.

### 1.3. `users/{userId}/categories/{categoryId}`
- **Mục đích:** Danh mục thu/chi cá nhân hóa (khởi tạo sẵn bộ danh mục tiếng Việt chuẩn).
- **Cấu trúc trường:** `id`, `ownerId`, `name`, `direction` (`debit` | `credit`), `iconKey`, `isSystem` (`bool`).

### 1.4. `users/{userId}/transactions/{txId}`
- **Mục đích:** Sổ giao dịch bất biến cá nhân (`txId` chính là `operationId` lũy đẳng).
- **Cấu trúc trường:**
  - `id` (`string`), `ownerId` (`string`), `walletId` (`string`), `targetWalletId` (`string?`), `categoryId` (`string?`), `categoryName` (`string`),
  - `kind` (`expense` | `income` | `transfer` | `creditCardPayment` | `reversal`),
  - `direction` (`debit` | `credit`), `amountMinor` (`int > 0`), `currencyCode` (`'VND'`),
  - `merchant` (`string`), `note` (`string?`), `occurredAt` (`Timestamp`), `monthKey` (`'YYYY-MM'`),
  - `sourceKind` (`manual` | `androidNotification` | `csv` | `bankApi`),
  - `verification` (`provisional` | `userConfirmed` | `verified` | `rejected`),
  - `crossSourceFingerprint` (`string` — dùng khử trùng lặp 15 phút & nâng cấp `provisional` → `verified`),
  - `reversalOfId` (`string?`), `reversedById` (`string?`), `isVehicleMaintenanceHint` (`bool`),
  - `splitLines` (`List<Map>` tùy chọn — hỗ trợ **Split Transaction** tách 1 hóa đơn vào nhiều danh mục con như `Ăn uống` + `Việc nhà & Gia dụng` với bất biến `sum(splitLines.amountMinor) == amountMinor`),
  - `schemaVersion` (`int`), `createdAt`, `updatedAt`.
- **Chỉ mục:** `(monthKey ASC, occurredAt DESC)`, `(verification ASC, occurredAt DESC)`.
- **Quy tắc bất biến:** `allow delete: if false` trong Security Rules; hủy giao dịch phải tạo bản ghi `reversal` đối ứng trong Firestore Transaction.

### 1.5. `users/{userId}/budgets/{budgetId}`
- **Mục đích:** Ngân sách chi tiêu theo danh mục từng tháng (`budgetId = '{monthKey}_{categoryId}'`).
- **Cấu trúc trường:** `id`, `ownerId`, `categoryId`, `categoryName`, `monthKey`, `limitMinor` (`int > 0`), `alertThresholdPct` (`int`, mặc định `80`), `updatedAt`.

### 1.6. `users/{userId}/personal_funds/{fundId}` (+ `contributions`, `expenses`)
- **Mục đích:** Quỹ mục tiêu tiết kiệm riêng của cá nhân.
- **Cấu trúc trường:** `id`, `ownerId`, `name`, `targetAmountMinor` (`int`), `balanceMinor` (`int`), `createdAt`, `updatedAt`.

### 1.7. `users/{userId}/private_events/{eventId}`
- **Mục đích:** Sự kiện lịch cá nhân riêng tư (`PRIVATE_EVENT`).
- **Cấu trúc trường:** `id`, `ownerId`, `title`, `description`, `location`, `startsAt` (`Timestamp`), `endsAt` (`Timestamp`), `createdAt`.
- **Bảo mật:** Nằm hoàn toàn dưới nhánh `users/{userId}` — không một thành viên hay chủ gia đình nào có đường dẫn hoặc quyền đọc.

### 1.8. `users/{userId}/personal_tasks/{taskId}`, `vehicles/{vehicleId}`, `bills/{billId}`, `consents/{sourceId}`, `source_events/{eventKey}`
- Lưu trữ công việc riêng, phương tiện riêng, hóa đơn riêng, trạng thái đồng ý quyền (`enabled: false` mặc định, `allowedPackages: List<String>`) và hộp thư sự kiện nguồn chống xử lý trùng lặp (`eventKey` duy nhất).

---

## 2. Không gian Cộng tác 3 Chế độ (`families/{familyId}` & `family_invites/{inviteCode}`)

### 2.1. `families/{familyId}`
- **Cấu trúc trường:** `id`, `name`, `spaceType` (`'family'` — Hộ Gia đình / Tổ ấm | `'roommates'` — Ở ghép / Nhà trọ | `'group'` — Hội nhóm / Chuyến đi), `createdBy`, `memberIds` (`List<String>` — phục vụ kiểm tra quyền O(1) trong Security Rules và truy vấn `where('memberIds', arrayContains: uid)`), `memberRoles` (`Map<String, String>`: `'owner' | 'admin' | 'member'`), `memberNames` (`Map<String, String>`), `lastJoinedInviteCode` (`string?`), `createdAt`, `updatedAt`.

### 2.2. `family_invites/{inviteCode}`
- **Cấu trúc trường:** `inviteCode` (Document ID), `familyId`, `familyName`, `createdBy`, `expiresAt` (`Timestamp`), `createdAt`.
- **Quyền truy cập:** Chỉ cho phép `get` khi biết chính xác `inviteCode`; cấm tuyệt đối `list` toàn bộ mã mời!

### 2.3. Các Subcollection Chia sẻ dưới `families/{familyId}/`
1. `funds/{fundId}` (+ `contributions/{id}`, `expenses/{id}`): Quỹ chung gia đình (sổ kế toán ảo, lưu `contributorId`, `contributorName`, `amountMinor`, tuyệt đối không lưu số dư ví riêng của người góp; duyệt chi chỉ cho phép `owner`/`admin`).
2. `shared_events/{eventId}`: Lịch chung của gia đình (`SHARED_EVENT`).
3. `availability/{slotId}`: Khung giờ bận ẩn nội dung, chỉ xuất bản khi chủ sở hữu chủ động bật `availabilityOptIn`.
4. `tasks/{taskId}`: Nhiệm vụ giao việc gia đình (`createdBy`, `assigneeId`, `assigneeName`, `status`: `proposed` | `accepted` | `declined` | `inProgress` | `done`, `recurrence`: `none` | `daily` | `weekly` | `monthly`, `dueAt`).
5. `vehicles/{vehicleId}` (+ `maintenances/{recordId}`): Phương tiện dùng chung (hỗ trợ `maskPlateWhenShared: true`).
6. `bills/{billId}`: Hóa đơn sinh hoạt chung (điện, nước, internet) kèm `averagePaidMinor` & `paymentCount` để cảnh báo tăng đột biến `>= 25%`.
7. `shopping_items/{itemId}`: Danh sách mua sắm chung gia đình / nhà trọ.
8. `split_bills/{billId}`: **Sổ Chia tiền Khoản chi Chung** (Ăn uống, Việc nhà, Điện nước, Tiền phòng, Du lịch): lưu `title`, `topic`, `paidByUserId`, `paidByName`, `totalAmountMinor` (`int > 0`), `splitMethod` (`equal` | `percentage` | `shares` | `exact`), `sharesByUserId` (`Map<String, int>` nguyên đồng VND khớp 100% tổng hóa đơn), `participantNames`, `choreOrTaskNote`.
9. `settlements/{settlementId}`: **Sổ Tất toán Công nợ Bất biến** (`allow update, delete: if false`): lưu `fromUserId`, `fromUserName`, `toUserId`, `toUserName`, `amountMinor` (`int > 0`), `paymentCode` (chuẩn `SEVQR LIFEOS ...` tương thích SePay/VietQR).
