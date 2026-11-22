# ĐẶC TẢ KỸ THUẬT SEPAY-LIKE CHO LIFE OS

**Nghiên cứu chức năng, kết nối ngân hàng và kiến trúc triển khai trong Super App cá nhân - gia đình**  
**Phiên bản:** 1.0 | **Ngày nghiên cứu:** 22/11/2026 | **Phạm vi:** Việt Nam, ưu tiên Android và Flutter

> **Quy ước đọc:** Các nội dung được đánh dấu **[TÀI LIỆU SEPAY]** dựa trên tài liệu công khai chính thức. Các nội dung **[ĐỀ XUẤT LIFE OS]** là thiết kế kỹ thuật mới cho ứng dụng của bạn, không phải mô tả kiến trúc nội bộ của SePay. Tất cả endpoint SePay cần được đối chiếu lại với phiên bản docs và hợp đồng đối tác trước khi đưa lên production.

## 1. TÓM TẮT ĐIỀU HÀNH

**Mục tiêu sản phẩm:** Mọi thành viên quản lý được tiền cá nhân, tài khoản, giao dịch, ngân sách, quỹ, hóa đơn, tài sản và lịch riêng; gia đình cộng tác trong các việc chung nhưng không tự động được xem lịch và tài chính riêng của nhau.

**Kết luận kỹ thuật:** Có thể xây dựng hệ thống trải nghiệm tương tự phần quản lý giao dịch của SePay mà không sao chép phần kết nối ngân hàng độc quyền. Lớp kết nối tài khoản thật phải sử dụng hợp đồng/API hợp lệ (ví dụ SePay Bank Hub), còn lớp xử lý thông báo, chuẩn hóa, đối soát, phân quyền và phân tích chi tiêu được tự phát triển. Khi SePay không cung cấp giao dịch tiền ra cho một ngân hàng, app dùng thông báo Android, nguồn hóa đơn và CSV như nguồn bổ sung với nhãn độ tin cậy thấp hơn.

**Các nguyên tắc không được phá vỡ:**

1. Không xin mật khẩu ngân hàng, OTP hoặc cookie ngân hàng để tự đăng nhập/scrape; dùng luồng liên kết chính thức của nhà cung cấp.
2. Không coi notification/SMS/email là bằng chứng đã thanh toán; chỉ là tín hiệu quan sát cho đến khi xác thực, hoặc người dùng xác nhận.
3. Một giao dịch xuất hiện ở nhiều nguồn chỉ tạo **một** giao dịch kinh tế; các nguồn còn lại trở thành bằng chứng liên kết.
4. Một số dư không có dữ liệu kiểm chứng phải hiển thị là **số dư ước tính**, không là số dư ngân hàng thực.
5. Gia đình **không** đồng nghĩa với quyền truy cập tài chính riêng của mọi thành viên.
6. Quỹ nội bộ ban đầu là sổ phân bổ/ghi nhận đóng góp, **không** là ví giữ tiền hộ hoặc dịch vụ chuyển tiền.

## 2. DANH MỤC TÍNH NĂNG SEPAY VÀ GIỚI HẠN TÁI TẠO

| Nhóm | SePay công bố | Life OS tái tạo | Phụ thuộc |
|---|---|---|---|
| Liên kết ngân hàng | Bank Hub Hosted Link và API | Kết nối trong màn hình Flutter | Hợp đồng Bank Hub, ngân hàng hỗ trợ |
| Giao dịch mới | IPN/webhook gần thời gian thực | Tạo, xác thực và gán giao dịch | Đúng event/API và cấp quyền |
| Lịch sử | REST API giao dịch | Backfill và đối soát theo kỳ | Phạm vi lịch sử được cấp |
| Đa tài khoản | Danh sách, chi tiết bank account | Ví cá nhân; tài khoản phân quyền | Liên kết hợp lệ |
| Tiền vào / tiền ra | Tùy ngân hàng | Sổ thu/chi tự động | Ma trận khả năng từng ngân hàng |
| Số dư | Không đồng đều | Số dư xác thực hoặc ước tính | Balance API khi có |
| VietQR | Sinh QR chuyển khoản | Góp quỹ, trả khoản chung | QR ngân hàng hợp lệ |
| VA | Tài khoản ảo và VA theo đơn | Gán khoản thu, đóng góp quỹ | Ngân hàng, loại tài khoản, hợp đồng |
| Mã thanh toán | Mã trong nội dung chuyển khoản | Nhận dạng góp quỹ / khoản phải thu | Đúng định dạng, không xóa tiền tố |
| Cổng thanh toán | VietQR, NAPAS, thẻ | Thu phí app / dịch vụ tùy chọn | Merchant onboarding, SDK riêng |
| Hoàn tiền | API theo loại kết nối | Không làm mặc định | Quyền/hợp đồng/ngân hàng |
| Chia sẻ biến động | Mobile, Telegram, Lark, Sheets | Push thông báo theo người/quỹ | Quyền xem chi tiết |
| Webhook theo dõi | Lịch sử gửi, replay, cảnh báo | Monitoring và replay nội bộ | Infrastructure |
| SoundBox | API thiết bị loa | Chỉ mở rộng cho hộ kinh doanh | Thiết bị + hợp đồng |
| eInvoice | API hóa đơn điện tử | Liên kết hóa đơn và giao dịch | Sản phẩm và quy định riêng |

**[TÀI LIỆU SEPAY]** SePay có hai hướng khác nhau: (a) SePay User API/Webhook cho tài khoản SePay của đơn vị và (b) Bank Hub dành cho đối tác có người dùng đầu cuối. Cổng thanh toán `sepay-pg-node` là sản phẩm API riêng, không thay thế Bank Hub. Các phương thức không được gộp vào một kiểu xác thực hoặc payload. [S1] [S2] [S3] [S4]

## 3. MA TRẬN KHẢ NĂNG NGÂN HÀNG BANK HUB

Theo tài liệu Bank Hub tại thời điểm nghiên cứu; không phải cam kết hỗ trợ mọi loại tài khoản cá nhân hoặc mọi giao dịch:

| Ngân hàng | Phạm vi tài khoản công bố | Tiền vào | Tiền ra | Số dư |
|---|---|---|---|---|
| MBBank | Cá nhân / hộ KD / DN | Có | Có | Không nêu rõ |
| ACB | Cá nhân / hộ KD / DN | Có | Có | Không nêu rõ |
| TPBank | Cá nhân / hộ KD / DN | Có | Có | Có |
| VietinBank | Cá nhân / hộ KD | Có | Có | Có |
| Sacombank | Cá nhân / hộ KD | Có | Có | Không nêu rõ |
| VPBank NEO | Cá nhân, một số VA hộ KD | Có | Chưa công bố | Không nêu rõ |
| BIDV | Cá nhân / hộ KD (VA) | Chỉ tiền vào từ VA | Chưa công bố | Không nêu rõ |
| OCB | Cá nhân (VA) | Chỉ tiền vào từ VA | Chưa công bố | Không nêu rõ |
| KienLongBank | Cá nhân / hộ KD / DN (VA) | Chỉ tiền vào từ VA | Chưa công bố | Không nêu rõ |
| MSB | Cá nhân / hộ KD (VA) | Chỉ tiền vào từ VA | Chưa công bố | Không nêu rõ |

**Cảnh báo bắt buộc cho UI:** Nếu connector không hỗ trợ `debit`, không hiển thị số chi tiêu được suy ra từ API là 'toàn bộ chi tiêu'. Nếu `balance_supported=false`, tuyệt đối không diễn giải trường `accumulated=0` từ Bank Hub IPN thành số dư bằng 0. Tài liệu IPN hiện ghi `accumulated` chưa hỗ trợ và trả 0. [S1] [S5]

Một số quy tắc nhà cung cấp: VietinBank cá nhân/hộ KD cần tiền tố `SEVQR` được giữ nguyên trong nội dung QR; OCB, MSB, KienLongBank, TPBank có kiểu hủy liên kết chỉ vô hiệu hóa trong Bank Hub; giao dịch khi tài khoản dừng kích hoạt không được tự động bù theo mô tả sự kiện khôi phục. [S1] [S6]

## 4. CHIẾN LƯỢC TÍCH HỢP: 4 KÊNH ĐẦU VÀO

### 4.1 Bank Hub - nguồn ưu tiên

- **Phạm vi:** Khi app đã trở thành đối tác/merchant được SePay cấp quyền và đã có `client_id`, `client_secret`, `company_xid` theo mô hình hợp đồng.
- **Đầu việc:** Backend quản lý access token, link token, trạng thái liên kết, các tài khoản đã liên kết, IPN giao dịch, webhook sự kiện, đối soát giao dịch.
- **Không triển khai:** Tuyệt đối không đặt secret trong Flutter, mã nguồn mở, browser hoặc Android native.

### 4.2 Android Notification Listener - nguồn quan sát

- Ứng dụng Android có thể nhận notification qua `NotificationListenerService` nếu người dùng tự bật quyền thông báo đặc biệt trong Settings. Dùng native Kotlin làm cầu nối Flutter qua `EventChannel` hoặc lưu vào local Room/Drift trước.
- Chỉ xử lý thông báo của package ngân hàng do người dùng chủ động chọn; không quét toàn bộ và upload mọi thông báo. Chấp nhận khả năng thông báo mất, ẩn nội dung, gộp nhiều thông báo hoặc bị OS giới hạn.
- Parser theo ngân hàng: nhận diện loại giao dịch, số tiền, tài khoản che số, số dư nếu hiện diện, thời điểm và mã tham chiếu. Chỉ gửi **dữ liệu đã trích xuất** về backend nếu người dùng bật đồng bộ.
- Tuyệt đối không suy ra rằng ứng dụng có quyền đọc thông báo hệ thống trên iOS. [S10]

### 4.3 Gmail - nguồn hóa đơn và cảnh báo

- Tích hợp Google OAuth với scope ít nhất có thể; người dùng bật tính năng riêng. Gmail có `watch` / Cloud Pub/Sub / `history.list`, nhưng event Gmail báo **thay đổi mailbox**, không phải tự động gửi nguyên nội dung email.
- Gmail read scopes có thể thuộc nhóm restricted; cần quy trình xác minh và có thể cần đánh giá bảo mật hằng năm nếu dữ liệu đi qua backend bên thứ ba. Ưu tiên nhập tay và email chuyển tiếp có lựa chọn cho MVP; chỉ mở tính năng OAuth Gmail khi đủ điều kiện tuân thủ. [S11] [S12]

### 4.4 CSV, sao kê, nhập thủ công

- Import CSV/XLSX sao kê có preview mapping cột, xác nhận múi giờ và đơn vị tiền, hash file để tránh nhập hai lần.
- Người dùng tự sửa danh mục, tách một giao dịch thành nhiều danh mục, gắn hóa đơn, đánh dấu chuyển tiền nội bộ, hoàn tiền hay rút tiền mặt.

## 5. BANK HUB: LUỒNG LIÊN KẾT TÀI KHOẢN

**[TÀI LIỆU SEPAY]** Các endpoint Bank Hub production đặt dưới `https://bankhub-api.sepay.vn/v1`; sandbox `https://bankhub-api-sandbox.sepay.vn/v1`. [S2]

1. Người dùng mở **Tài khoản > Kết nối ngân hàng**; app hiển thị thông báo quyền dữ liệu và loại thông tin có thể đồng bộ.
2. Flutter gọi `POST /v1/bank-connections/link-session` của **backend Life OS** (endpoint của ta), kèm account type đã chọn.
3. Backend lấy Bank Hub access token qua `POST /v1/token` (Basic auth với client_id/secret), cache an toàn theo TTL.
4. Backend xác định `company_xid` đã được cấp/hợp lệ. Việc tạo `company_xid` cho từng người dùng hay nhóm khách hàng là quyết định **phải xác nhận theo hợp đồng đối tác**, không được tự coi nó là ID gia đình.
5. Backend gọi SePay `POST /v1/link-token/create` với `purpose=LINK_BANK_ACCOUNT`, `company_xid`, `is_mobile_app=1`, `completion_redirect_uri` HTTPS.
6. Trả `hosted_link_url` ngắn hạn về Flutter; mở Hosted Link theo cách SePay hỗ trợ. Không intercept password/OTP, không ghi màn hình nhạy cảm.
7. Flutter nhận redirect chỉ là tín hiệu UX. Backend chờ webhook `BANK_ACCOUNT_LINKED` / `LINK_SESSION_COMPLETED`, hoặc tra lại API nếu thiếu webhook, trước khi gắn trạng thái `ACTIVE`.
8. Lưu `bank_account_xid`, ngân hàng, khả năng của tài khoản, user sở hữu và thời gian đồng ý. Bắt đầu backfill rồi chuyển sang đồng bộ liên tục.
9. Gỡ liên kết dùng link token `purpose=UNLINK_BANK_ACCOUNT`, không xóa toàn bộ lịch sử kế toán; cho người dùng chọn xóa dữ liệu theo chính sách.
10. Với kết nối được hỗ trợ, `REACTIVATE_BANK_ACCOUNT` mở lại liên kết, nhưng phải cảnh báo dữ liệu gián đoạn.

Các webhook trạng thái liên kết (mẫu): `LINK_TOKEN_CREATED`, `LINK_SESSION_INITIALIZED`, `LINK_SESSION_STATE_CHANGED`, `BANK_ACCOUNT_LINKED`, `BANK_ACCOUNT_UNLINKED` / `BANK_ACCOUNT_INACTIVED`, `BANK_ACCOUNT_REACTIVATED`, `LINK_SESSION_COMPLETED`. Mỗi event có `xid` riêng. **Event kết nối không phải event giao dịch.** [S6] [S7]

### 5.1 Các endpoint SePay Bank Hub xác thực được

| Method | Đường dẫn | Mục đích |
|---|---|---|
| POST | `/v1/token` | Cấp bearer token (server-to-server) |
| POST | `/v1/link-token/create` | Tạo hosted link liên kết/hủy/khôi phục |
| POST | `/v1/link-token/get` | Kiểm tra link token |
| POST | `/v1/link-token/revoke` | Vô hiệu link token |
| GET | `/v1/company` | Danh sách công ty trong merchant |
| POST | `/v1/company/create` | Tạo công ty theo mô hình đối tác |
| GET | `/v1/bank-account` | Danh sách bank account đã liên kết |
| GET | `/v1/bank-account/{xid}` | Chi tiết bank account |
| GET | `/v1/transaction` | Danh sách giao dịch có lọc và phân trang |
| GET | `/v1/transaction/{transaction_id}` | Chi tiết giao dịch |
| POST | `/v1/webhook` | Cấu hình webhook trạng thái merchant |

**Lưu ý mâu thuẫn trong docs:** Trang API cấu hình Bank Hub webhook có tiêu đề ghi `PUT /webhooks/config` nhưng phần endpoint/cURL lại ghi **POST `/v1/webhook`**. Với phiên bản đang đọc, dùng `POST /v1/webhook` theo ví dụ chính thức và xác nhận lại với SePay trên sandbox trước khi triển khai. [S8]

## 6. PHÂN BIỆT 4 KIỂU CALLBACK KHÔNG THỂ ĐÁNH ĐỒNG

| Sản phẩm / Luồng | Nội dung | Nhận dạng | Bảo mật theo docs |
|---|---|---|---|
| Bank Hub **IPN** | Biến động giao dịch | `transaction_id`, `bank_account_xid` | Mặc định `Authorization: Apikey ...`; IP allowlist |
| Bank Hub **Webhook Events** | Trạng thái link, unlink, session | `xid`, `event`, `metadata` | `X-Secret-Key` trong cấu hình `SECRET_KEY` (kiểm chứng contract) |
| SePay Webhooks tiêu chuẩn | Giao dịch khách hàng SePay | `id`, `transferType`, `transferAmount` | HMAC-SHA256 hoặc API key/OAuth tùy cấu hình |
| SePay Payment Gateway IPN | Trạng thái đơn hàng thanh toán | Theo đặc tả cổng thanh toán | Cơ chế SDK/merchant secret của PG, tách riêng |

**Bank Hub IPN** có `transfer_type=credit|debit`, `amount`, `transaction_date`, `reference_code`, `content`, `transaction_id`, `bank_account_xid`; phản hồi `HTTP 200`, JSON `{"success":true}`. `accumulated` hiện chưa được hỗ trợ theo mô tả IPN. Theo tài liệu, IPN chỉ tự retry khi lỗi kết nối mạng: tối đa 7 lần theo khoảng 1,1,2,3,5,8,13 phút; sau ngưỡng 5 giờ không tiếp tục. **Do đó bắt buộc có backfill/đối soát.** [S5]

**SePay Webhooks thông thường** có mẫu JSON dùng camelCase `transactionDate`, `accountNumber`, `transferType=in|out`, `transferAmount`, `id`. HMAC sử dụng `X-SePay-Timestamp` + raw bytes body theo công thức SHA256 HMAC của chuỗi `{timestamp}.{raw_body}`. Cơ chế này **không tự áp vào Bank Hub IPN** nếu hợp đồng không quy định. [S9]

**Bank Hub webhook trạng thái** có cấu trúc chung:

```json
{
  "timestamp": 1768312100,
  "xid": "e61cdae9-505e-4349-9713-a3e5b8b80b5e",
  "version": "1.0",
  "event": "BANK_ACCOUNT_LINKED",
  "metadata": {
    "bank_account_xid": "587eabfb-f086-11f0-b16e-52c7e9b4f41b",
    "link_session_xid": "0e296f70-cf41-4e8f-a89f-00cee248b887"
  }
}
```

**Bank Hub IPN giao dịch** có cấu trúc riêng:

```json
{
  "gateway": "MBBank",
  "transaction_date": "2026-11-22 15:35:12",
  "account_number": "0000000000011111",
  "bank_account_xid": "587eabfb-f086-11f0-b16e-52c7e9b4f41b",
  "va": null,
  "payment_code": null,
  "content": "THANH TOAN DIEN NUOC",
  "transfer_type": "debit",
  "amount": 275000,
  "reference_code": "FT_EXAMPLE_001",
  "accumulated": 0,
  "transaction_id": "external-tx-001"
}
```

> Hai JSON trên là ví dụ minh họa giả lập đúng **tên trường và ý nghĩa**, không phải sự kiện sản xuất. IPN thành công chỉ sau khi xác thực và ghi bền vào `event_inbox`, không phải sau khi đã chạy AI phân loại xong.

## 7. KIẾN TRÚC MỤC TIÊU LIFE OS

**Giai đoạn 1: Modular Monolith** để dễ vận hành, giữ ranh giới module như microservice nhưng deploy một API server + một worker. Không cần Kafka/Kubernetes cho MVP.

```text
                   ┌─────────────────────┐
                   │ Flutter Android/iOS │
                   │ Riverpod + Drift    │
                   └──────────┬──────────┘
                              │ HTTPS/JWT
                   ┌──────────▼──────────┐
                   │ API Gateway/NestJS  │
                   │ Auth / ACL / Consent│
                   └──────────┬──────────┘
                              │
          ┌───────────────────┼───────────────────────────┐
          │                   │                           │
  ┌───────▼────────┐ ┌────────▼────────┐       ┌─────────▼────────┐
  │ Banking Module │ │ Household Module│       │ Calendar/Assets  │
  │ connectors     │ │ budgets / funds │       │ tasks / vehicles │
  └───────┬────────┘ └────────┬────────┘       └─────────┬────────┘
          └───────────────────┼───────────────────────────┘
                              │
           ┌──────────────────▼──────────────────────┐
           │ PostgreSQL: inbox, transactions, ledger│
           │ users, accounts, funds, ACL, audit     │
           └──────────────────┬──────────────────────┘
                              │ Outbox pattern
                       ┌──────▼──────┐
                       │ Redis/BullMQ│
                       └──────┬──────┘
                              │
          ┌───────────────────▼──────────────────────────────┐
          │ Worker: normalize -> dedupe -> reconcile ->      │
          │ categorize -> notify -> dashboard aggregates    │
          └───────────────────┬──────────────────────────────┘
                              │
       ┌──────────────────────┼───────────────────────┐
       │                      │                       │
 Bank Hub API/IPN     Android local events    Gmail/CSV import
```

### 7.1 Cấu trúc module codebase

```text
life-os/
  apps/
    mobile/                     # Flutter; Riverpod, Drift, local encryption
    api/                        # NestJS; REST API
    worker/                     # BullMQ processors
  packages/
    contracts/                  # OpenAPI, Zod schemas, DTO versions
    domain/                     # money, transaction, visibility rules
    bank-adapters/              # sepay-bankhub, sepay-v2, android-events
    parsers/                    # Android bank patterns, import adapters
    security/                   # access control, encryption, audit
  infra/
    docker/                     # compose dev: postgres + redis
    migrations/                 # PostgreSQL schema migration
  docs/
    ADR/                        # Architecture Decision Records
    policies/                   # permissions, retention, consent
    tests/fixtures/             # synthetic API IPN payloads
```

### 7.2 Phân ranh trách nhiệm

- **Flutter:** UI, tạo khoản chi thủ công, xác nhận gợi ý, lịch, quỹ, cache offline, thông báo người dùng.
- **Kotlin Android:** lắng nghe thông báo khi đã có quyền, lọc package, chuyển thành nguồn quan sát, không lưu tất cả nội dung thông báo mặc định.
- **NestJS API:** xác thực, quyền truy cập người dùng, gọi API SePay, tạo Hosted Link, ghi nhận inbox webhook, API dữ liệu.
- **Worker:** chuẩn hóa, dedupe, reconcile, rule engine, báo cáo, nhắc nhở, dự đoán bảo dưỡng xe.
- **PostgreSQL:** nguồn sự thật giao dịch và permissions, cất evidence và event log.
- **Redis/BullMQ:** job retry, rate-limit/backoff, delayed notifications; không được dùng Redis làm nơi lưu sự thật duy nhất.

## 8. CANONICAL TRANSACTION MODEL

Dữ liệu từ mọi nguồn được map về một kiểu duy nhất:

```ts
type CanonicalTransaction = {
  id: string;                         // UUID nội bộ
  ownerUserId: string;                // người sở hữu dữ liệu gốc
  householdId?: string | null;        // liên hệ gia đình nếu được chia sẻ
  bankAccountId?: string | null;      // ID nội bộ, không phải số TK thô
  direction: 'CREDIT' | 'DEBIT';
  amountMinor: string;                // decimal integer string, tránh float JS
  currency: 'VND' | string;
  occurredAt: string;                 // ISO8601 UTC
  sourceKind: 'BANK_API' | 'ANDROID_NOTIFICATION' | 'GMAIL' | 'CSV' | 'MANUAL';
  verification: 'VERIFIED' | 'PROVISIONAL' | 'USER_CONFIRMED';
  categoryId?: string | null;
  visibility: 'PRIVATE' | 'SHARED_SUMMARY' | 'SHARED_DETAIL';
  isInternalTransfer: boolean;
  externalRefs: Array<{ provider: string; externalId: string }>;
  confidence: number;                // 0..1, gợi ý phân loại
  rawEvidenceId?: string | null;      // payload riêng, mã hóa có TTL
};
```

**Quy tắc tin cậy:** BANK_API có thể đánh dấu giao dịch `VERIFIED` sau khi xác thực nguồn và mapping tài khoản; Android notification/email là `PROVISIONAL`; người dùng duyệt thành `USER_CONFIRMED` nhưng không được mô tả là 'đã xác nhận với ngân hàng'. Nếu dữ liệu mâu thuẫn, giữ toàn bộ evidence và mở trạng thái `NEEDS_REVIEW`.

### 8.1 SQL lõi tham khảo (PostgreSQL)

```sql
CREATE TABLE bank_connections (
  id UUID PRIMARY KEY,
  owner_user_id UUID NOT NULL REFERENCES users(id),
  provider TEXT NOT NULL,                -- SEPAY_BANK_HUB, MANUAL, ...
  provider_company_xid TEXT,
  provider_account_xid TEXT,
  bank_code TEXT NOT NULL,
  masked_account TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN
    ('PENDING', 'ACTIVE', 'INACTIVE', 'REVOKED', 'ERROR')),
  capabilities JSONB NOT NULL DEFAULT '{}'::jsonb,
  consent_version TEXT NOT NULL,
  consented_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_account_xid)
);

CREATE TABLE source_events (
  id UUID PRIMARY KEY,
  provider TEXT NOT NULL,
  event_kind TEXT NOT NULL,             -- BANK_HUB_IPN, LINK_EVENT, ANDROID...
  external_event_id TEXT NOT NULL,
  connection_id UUID REFERENCES bank_connections(id),
  payload_ciphertext BYTEA,             -- optional encrypted raw payload
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  processing_status TEXT NOT NULL DEFAULT 'PENDING',
  UNIQUE (provider, event_kind, external_event_id)
);

CREATE TABLE financial_transactions (
  id UUID PRIMARY KEY,
  owner_user_id UUID NOT NULL REFERENCES users(id),
  bank_connection_id UUID REFERENCES bank_connections(id),
  direction TEXT NOT NULL CHECK (direction IN ('CREDIT', 'DEBIT')),
  amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
  currency CHAR(3) NOT NULL DEFAULT 'VND',
  occurred_at TIMESTAMPTZ NOT NULL,
  verification TEXT NOT NULL CHECK (verification IN
    ('PROVISIONAL', 'VERIFIED', 'USER_CONFIRMED', 'NEEDS_REVIEW')),
  visibility TEXT NOT NULL DEFAULT 'PRIVATE',
  category_id UUID,
  internal_transfer_group_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE transaction_evidence (
  source_event_id UUID PRIMARY KEY REFERENCES source_events(id),
  transaction_id UUID NOT NULL REFERENCES financial_transactions(id),
  attached_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE event_outbox (
  id UUID PRIMARY KEY,
  topic TEXT NOT NULL,
  aggregate_id UUID NOT NULL,
  body JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ
);
```

Các bảng `users`, `households`, `household_members`, `accounts`, `funds`, `fund_contributions`, `task_assignments`, `permissions`, `ledger_entries`, `recurring_bills`, `assets`, `vehicle_maintenance`, `integration_consents` được triển khai qua migration riêng. Ví dụ SQL là khung dữ liệu cần ghép với mô hình users, chưa phải migration chạy độc lập.

## 9. THUẬT TOÁN XỬ LÝ CHỐNG TRÙNG VÀ ĐỐI SOÁT

### 9.1 Inbox + Outbox nguyên tử

1. Validate method, content type, kích thước payload và đúng secret của endpoint.
2. Parse JSON và kiểm tra schema bắt buộc, `bank_account_xid` thuộc một liên kết được chấp thuận.
3. Trong **một transaction PostgreSQL**, `INSERT ... ON CONFLICT DO NOTHING` sự kiện với unique key; nếu mới, ghi thêm `outbox` job cùng lúc.
4. COMMIT xong mới trả `200 {"success":true}`. Nếu mất kết nối DB, trả lỗi để provider có thể retry theo chính sách của họ.
5. Worker đọc outbox, normalize giao dịch, tìm giao dịch khớp, ghi `financial_transactions` hoặc gắn thêm `transaction_evidence`, sau đó cập nhật các projection.
6. Reconciler định kỳ gọi API theo tài khoản và cửa sổ thời gian trượt, đọc hết page, bảo vệ 429 với `Retry-After` nếu có.

### 9.2 Phân biệt duplicate và hai giao dịch thật

**Khóa cứng:** cùng nguồn API và `transaction_id` hoặc ID sự kiện chính thức => duplicate.  
**Khóa mềm liên nguồn:** tài khoản tương ứng + chiều + số tiền + tham chiếu + cửa sổ thời gian; chỉ merge tự động nếu xác suất cao và không có hai ứng viên giống nhau.  
**Không dùng một mình:** `amount` hoặc `reference_code`, vì có thể lặp theo hệ thống/tài khoản.

Ví dụ: Android thông báo trừ 120.000 VND lúc 10:01 và Bank Hub API nhận cùng giao dịch lúc 10:02. Hệ thống **cập nhật giao dịch provisional** thành verified, thêm nguồn chứng minh API, không tạo dòng chi phí thứ hai.

Ví dụ khác: Có hai lần chuyển khoản 120.000 VND cùng cửa hàng trong 1 phút. Nếu khác mã tham chiếu, phải là hai giao dịch khác nhau.

### 9.3 Backfill và đối soát

- Khi liên kết lần đầu: lấy lịch sử theo phạm vi dữ liệu thực sự SePay cung cấp; không hứa backfill không giới hạn.
- Mỗi 15 phút (mức đề xuất): lấy dữ liệu 24 giờ gần nhất theo cursor/thời gian, chồng lấp cửa sổ 5-15 phút.
- Mỗi đêm: đối soát lại 7 ngày gần nhất theo phân trang và idempotency.
- Khi webhook lỗi hoặc hệ thống phục hồi: chạy đối soát ưu tiên theo account.
- Với SePay API v2 `since_id`, tài liệu yêu cầu sắp xếp tăng dần theo thời gian giao dịch và đọc hết các trang trước khi ghi cursor cuối; nếu không có nguy cơ bỏ sót. Rate limit công bố API v2 là 3 req/s; Bank Hub cần thiết kế theo giới hạn hợp đồng/429 thực tế. [S13] [S14]

## 10. LEDGER TÀI CHÍNH VÀ QUỸ GIA ĐÌNH

**[ĐỀ XUẤT LIFE OS]** Cần sổ cái double-entry cho các sự kiện đã được xử lý: tránh tổng chi tiêu sai khi chuyển giữa hai tài khoản cá nhân, chuyển tiền vào quỹ, rút tiền mặt hoặc hoàn tiền.

### Ví dụ A: mua thực phẩm 120.000 VND

| Tài khoản kế toán | Debit | Credit |
|---|---:|---:|
| Chi phí thực phẩm | 120.000 | 0 |
| Tài sản ngân hàng | 0 | 120.000 |

### Ví dụ B: chuyển 1.000.000 VND từ ngân hàng A sang ví tiền mặt

| Tài khoản kế toán | Debit | Credit |
|---|---:|---:|
| Tài sản ví tiền mặt | 1.000.000 | 0 |
| Tài sản ngân hàng A | 0 | 1.000.000 |

=> Không cộng 1 triệu vào chi tiêu. Nếu người dùng chỉ muốn phân bổ 'quỹ du lịch' trong app, đó là **số tiền dành riêng trên sổ**, không đại diện cho tiền thực sự được chuyển đến một tài khoản lưu ký.

### Cơ chế gia đình bảo mật

- Mỗi `user` tự có một `personal_space`. Membership gia đình chỉ cho xem task được giao, khoản chi đã chủ động share, và quỹ chung được cho phép.
- `household_admin` có thể quản lý thành viên và nhiệm vụ chung, nhưng **không tự được xem** `PRIVATE` bank accounts hoặc private events.
- Khi đóng góp quỹ: ghi khoản đóng góp (receipt) và nguồn bank transaction nếu có; quỹ chung có `fund_balance_derived` từ các khoản được xác nhận. Người nhận tiền/quỹ thực tế phải được làm rõ (quỹ sổ sách hoặc tài khoản ngân hàng của người giữ quỹ).
- Lịch riêng chỉ xuất ra busy/free hoặc không xuất; việc được giao có due date hiển thị cho người nhận và người giao, không cấp quyền toàn bộ Google Calendar.
- Khi rời gia đình: thu hồi sharing token và quyền qua join table, không xóa giao dịch cá nhân.

## 11. PHÂN LOẠI CHI TIÊU VÀ GỢI Ý THÔNG MINH

Rule Engine trước, AI sau:

1. Chuẩn hóa Unicode, viết hoa, bỏ khoảng trắng dư, chuẩn mã ngân hàng và loại giao dịch.
2. Nhận diện merchant từ từ khóa mô tả (`GRAB`, `SHOPEE`, `DIEN LUC`, `XANG`...), không tự suy luận tên người từ thông báo cá nhân.
3. Ưu tiên luật do người dùng sửa > luật nguồn tin cậy > merchant rule > mô hình AI.
4. Với `confidence < 0.80`, hiển thị gợi ý để người dùng xác nhận; không tự động trừ quỹ nhạy cảm nếu chưa chắc.
5. Học từ nhãn người dùng trong phạm vi tài khoản với consent; không dùng dữ liệu nhà người khác để gợi ý khi chưa được chia sẻ.

Nhóm danh mục khởi đầu: ăn uống, chợ/siêu thị, nhà cửa, điện/nước/internet, di chuyển, xăng xe, bảo dưỡng xe, mua sắm, sức khỏe, giáo dục, giải trí, nợ/cho vay, chuyển khoản nội bộ, phí ngân hàng, khác. Có split transaction và hoàn tiền.

**Khai thác ưu thế Super App:** Từ giao dịch 'thay nhớt xe 350k', gợi ý liên kết với hồ sơ xe; từ hóa đơn điện định kỳ, tạo lịch nhắc thanh toán; từ đóng góp quỹ, cập nhật tiến độ quỹ gia đình; từ nhiệm vụ 'mua đồ ăn', cho phép gắn hóa đơn với task đã hoàn thành.

## 12. API NỘI BỘ LIFE OS (KHÔNG PHẢI ENDPOINT SEPAY)

| Verb | Endpoint Life OS | Mục đích | Quyền |
|---|---|---|---|
| POST | `/v1/bank-connections/link-session` | Khởi tạo Bank Hub Hosted Link | Account owner |
| GET | `/v1/bank-connections` | Liệt kê tài khoản của tôi | Owner |
| DELETE | `/v1/bank-connections/:id` | Bắt đầu flow ngừng liên kết | Owner |
| POST | `/v1/provider-events/sepay-bankhub/ipn` | Bank Hub IPN | Provider secret |
| POST | `/v1/provider-events/sepay-bankhub/link` | Bank Hub lifecycle event | Provider secret |
| POST | `/v1/provider-events/sepay-userapi/transaction` | Legacy/User API webhook | HMAC/API key riêng |
| GET | `/v1/transactions` | Sổ giao dịch đã lọc | Owner/explicit-share |
| PATCH | `/v1/transactions/:id` | Sửa category, note, split | Owner |
| POST | `/v1/transactions/:id/confirm` | Xác nhận tín hiệu provisional | Owner |
| POST | `/v1/transactions/import` | Nhập CSV với preview | Owner |
| POST | `/v1/households/:id/funds` | Tạo quỹ gia đình | Thành viên có quyền |
| POST | `/v1/funds/:id/contributions` | Đăng ký đóng góp/receipt | Contributor/manager |
| GET | `/v1/dashboard/monthly` | Tổng hợp chi tiêu theo quyền | User scope |
| POST | `/v1/consents/revoke` | Thu hồi quyền đồng bộ | Owner |

**Chuẩn API:** token người dùng của Life OS không phải token SePay. Mọi `account_id`, `household_id` phải xác thực cả quyền sở hữu và quyền chia sẻ tại backend. Tuyệt đối không dùng `householdId` do client gửi làm căn cứ truy cập dữ liệu của thành viên khác.

## 13. MẪU RECEIVER BANK HUB IPN (MỨC THAM KHẢO)

```ts
import express from 'express';
import { timingSafeEqual } from 'node:crypto';

const app = express();
app.use('/provider-events/sepay-bankhub/ipn', express.json({ limit: '64kb' }));

function constantTimeAuth(actual: string, expected: string): boolean {
  const a = Buffer.from(actual);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

app.post('/provider-events/sepay-bankhub/ipn', async (req, res) => {
  const configuredSecret = process.env.SEPAY_BANKHUB_IPN_KEY;
  if (!configuredSecret) return res.sendStatus(503);
  const auth = req.header('authorization') ?? '';
  if (!constantTimeAuth(auth, `Apikey ${configuredSecret}`))
    return res.status(401).json({ success: false });

  const e = req.body;
  if (!e || typeof e.transaction_id !== 'string' ||
      typeof e.bank_account_xid !== 'string' ||
      !['credit', 'debit'].includes(e.transfer_type) ||
      !Number.isSafeInteger(e.amount) || e.amount <= 0)
    return res.status(400).json({ success: false });

  // CẦN TRIỂN KHAI: tra bank_account_xid và trạng thái liên kết của owner;
  // trong 1 transaction SQL: INSERT inbox ON CONFLICT DO NOTHING + outbox.
  // KHÔNG tính tiền, cập nhật fund, gửi push hay gọi LLM ở request thread.
  await durableStoreInboxAndOutbox(e);
  return res.status(200).json({ success: true });
});
```

**Quan trọng:** `durableStoreInboxAndOutbox` là interface chưa có implementation trong snippet; code này minh họa đúng flow xác thực và acknowledgment chứ **không phải module production chạy ngay**. Cần thêm validation Zod, DB mapping, timeout, logger an toàn, secret rotation, kiểm thử integration; webhook trạng thái cần route và secret riêng.

### 13.1 Android listener pseudocode

```kotlin
class FinanceNotificationListener : NotificationListenerService() {
  override fun onNotificationPosted(sbn: StatusBarNotification?) {
    if (sbn == null || !userOptedIn()) return
    if (!userAllowedBankPackage(sbn.packageName)) return
    val data = extractMinimalFields(sbn.notification.extras)
    val parsed = localBankParser(sbn.packageName, data) ?: return
    saveProvisionalEvidenceLocally(parsed) // encrypted; no raw dump
    if (userEnabledCloudSync()) enqueueSecureSync(parsed)
  }
}
```

**Không yêu cầu** `READ_SMS` để đọc notification. Người dùng cần biết cấp quyền Notification Listener là quyền rộng, có thể tiếp cận nội dung thông báo nhạy cảm; app phải lọc và giữ riêng dữ liệu ngay trên máy. Thông báo của ứng dụng ngân hàng có thể thay đổi cấu trúc bất kỳ lúc nào. [S10] [S15]

## 14. BẢO MẬT - ĐỒNG Ý - TUÂN THỦ

**Đối với Bank Hub/API:**

- Merchant credentials trong secrets manager server, rotate định kỳ; token cache TTL an toàn, không ghi access token vào log; chỉ gửi Hosted Link URL ngắn hạn xuống app.
- Tách endpoint và bí mật: Bank Hub IPN, Bank Hub lifecycle webhook, SePay User API v2/Webhooks và Payment Gateway IPN.
- HTTPS + provider authentication + IP allowlist khi có danh sách chính thức; kiểm tra anti-replay nơi có timestamp/chữ ký; HMAC trên raw body nếu **đúng sản phẩm có HMAC**.
- Lưu source events đã xác thực với unique key và audit trail; không gửi giao dịch raw cho AI bên thứ ba theo mặc định.
- Mã hóa nội dung nhạy cảm ở mức app/DB; sao lưu mã hóa; phân quyền least-privilege; audit access tới giao dịch tài chính; xóa dữ liệu và thu hồi kết nối được kiểm soát.

**Đối với Android:**

- Trước màn hình cấp Notification Access, có giải thích đúng app nào sẽ được đọc, mục đích, dữ liệu giữ lại, kênh đồng bộ, nơi lưu, cách thu hồi.
- Không thu thập thông báo OTP, chat, hoặc thông báo ngoài danh sách ngân hàng người dùng chọn; mặc định parse on-device.
- Kiểm tra Play Console User Data / Data safety / Financial Features declarations và quyền đặc biệt; phải có privacy policy, xóa tài khoản và lựa chọn dừng theo dõi. [S15]

**Đối với Google:**

- Calendar hoặc Tasks chỉ cần scope tương ứng, không xin Gmail nếu chỉ cần nhắc lịch.
- Gmail read-only là quyền nhạy cảm/restricted tùy scope; xem xét OAuth verification và security assessment; không phát hành công khai trước khi được xác minh nếu cần. [S11] [S12]

**Ranh giới tài chính:** Quỹ chia sẻ là công cụ ghi chép và lập kế hoạch. Nếu tương lai app nhận/gửi tiền hộ, giữ tiền, thực hiện thanh toán hoặc là trung gian thanh toán, phải đánh giá quy định và hợp đồng với đơn vị được phép; không mặc định có thể vận hành như ngân hàng/ví điện tử.

## 15. MA TRẬN PHÂN QUYỀN

| Dữ liệu/chức năng | Chủ sở hữu | Thành viên gia đình | Quản trị gia đình | Người được giao việc |
|---|---|---|---|---|
| TK ngân hàng riêng | Đầy đủ | Không | Không | Không |
| Chi tiêu riêng | Đầy đủ | Không | Không | Không |
| Tổng kết được chia sẻ | Đầy đủ | Khi cho phép | Khi cho phép | Khi cho phép |
| Quỹ chung | Theo role quỹ | Xem theo role | Quản lý theo role | Theo role |
| Task được giao | Theo quyền | Người liên quan | Theo quyền dự án | Được xem |
| Lịch cá nhân | Đầy đủ | Không | Không | Không |
| Thông tin bận/rảnh | Nếu bật | Có thể chia sẻ | Có thể chia sẻ | Có thể chia sẻ |
| Thiết bị/xe riêng | Đầy đủ | Không | Không | Không |

Đây là bảng mục tiêu bảo mật; cần enforce bằng API ownership checks + DB RLS hoặc tương đương. Không dựa vào việc ẩn widget để bảo mật.

## 16. ĐÁNH GIÁ MÔ HÌNH VẬN HÀNH VÀ CHI PHÍ

- SePay bảng giá công khai hiện hiển thị gói FREE 0đ/tháng, 50 giao dịch/tháng và gói STARTUP từ 120.000đ/tháng, có cơ chế tính phí vượt. **Không được mặc định bảng giá bán lẻ này áp dụng cho Bank Hub partner**, cần hợp đồng riêng. [S16]
- Bank Hub có sandbox; credentials riêng cần làm việc với SePay. [S17]
- Chi phí của Life OS còn gồm PostgreSQL, Redis, object storage, push, email/OAuth verification và nếu có LLM phân loại. Dùng quy tắc/regex trước để giảm chi phí AI.
- Dùng modular monolith trước, tách workers sau khi có tải thực; kịch bản ngân hàng 429 hoặc timeout là bình thường, không polling mỗi vài giây cho mọi tài khoản.

## 17. BỘ KIỂM THỬ BẮT BUỘC

| ID | Tình huống | Kết quả phải đạt |
|---|---|---|
| T01 | IPN hợp lệ từ tài khoản đã liên kết | 200 + inbox/outbox ghi bền |
| T02 | IPN sai API key | 401, không lưu dữ liệu |
| T03 | IPN tài khoản chưa được mapping | Quarantine, không gán user |
| T04 | Nhận một IPN 5 lần | 1 event, 1 giao dịch kế toán |
| T05 | 2 IPN đồng thời cùng ID | Unique DB thắng race condition |
| T06 | 2 giao dịch cùng số tiền nhưng khác ref | 2 giao dịch |
| T07 | Android báo trước, Bank Hub đến sau | Nâng cấp provisional -> verified |
| T08 | Android notification nhầm merchant | Cho sửa, audit và cập nhật rules |
| T09 | 429 từ SePay API | Exponential backoff + Retry-After |
| T10 | DB crash trước commit | Không ack thành công |
| T11 | Worker crash sau commit | Retry từ outbox, không trùng |
| T12 | Link redirect thành công nhưng webhook thiếu | Không ACTIVE trước khi xác minh |
| T13 | Khách hủy liên kết | Dừng sync, không xóa lịch sử bất ngờ |
| T14 | Bank chỉ hỗ trợ credit | Không hiển thị toàn bộ chi tiêu |
| T15 | IPN `accumulated=0` | Không hiển thị TK có 0 VND |
| T16 | Giao dịch chuyển tiền giữa 2 ví | Không cộng vào chi tiêu |
| T17 | Thành viên A truy vấn TK B | 403/404, không lộ số dư |
| T18 | Admin gia đình đọc lịch riêng | Bị chặn |
| T19 | Rút quyền notification | Dừng listener/sync, giữ consent audit |
| T20 | Gmail permission revoked | Dừng watch, không retry vô hạn |
| T21 | Reconciliation nhiều pages | Không bỏ sót cursor |
| T22 | Secret rotation webhook | Không gián đoạn và không nhận giả |
| T23 | Đồng hồ thiết bị sai | Chuẩn hóa timestamp và phát hiện lệch |
| T24 | Quyền gia đình bị rút trong lúc request | Backend kiểm tra tại thời điểm đọc/ghi |

**Tăng cường:** contract tests chạy sandbox cho mọi adapter; fixture cố định theo phiên bản payload; load test 1000 giao dịch/phút (mục tiêu giả lập nội bộ, không phải cam kết SePay) và kiểm tra không có giao dịch mất; penetration test liên-tenant.

## 18. LỘ TRÌNH TRIỂN KHAI KHÔNG PHỤ THUỘC MỘT NHÀ CUNG CẤP

**Giai đoạn A - Core tài chính:** Authentication; tạo user; tài khoản/ ví tự khai; sổ giao dịch, ngân sách, danh mục, nhập CSV; nhận diện transfer; kiến trúc ledger, privacy.

**Giai đoạn B - Android:** Notification listener opt-in; thư viện parser từng ngân hàng; lưu local encrypted; đồng bộ event; gợi ý chi tiêu với trạng thái provisional.

**Giai đoạn C - SePay Sandbox:** Đăng ký partner/sandbox; Bank Hub connector; Hosted Link; link events; IPN; backfill; đối soát; event inbox/outbox.

**Giai đoạn D - Gia đình và quỹ:** Membership và roles; quỹ ảo; đóng góp; ghi nhận khoản chung; nhiệm vụ, lịch riêng, nhắc việc và visibility rules.

**Giai đoạn E - Google và nâng cao:** Calendar/Tasks OAuth; Gmail khi đã đủ điều kiện; nhắc hóa đơn; tài sản/xe; dashboard insights; export và xóa dữ liệu.

**Gate triển khai sản xuất:** Tất cả T01-T24 đạt, RLS và permissions được kiểm tra tự động, sandbox Bank Hub hoạt động, tài liệu cấp quyền dữ liệu hoàn chỉnh, kiểm tra tính đủ giao dịch không gây hiểu nhầm.

## 19. CÂU HỎI CẦN XÁC MINH VỚI SEPAY TRƯỚC KHI CHỐT THƯƠNG MẠI

1. Bank Hub có cho phép SaaS quản lý tài chính **cá nhân/gia đình** là đối tác hay chỉ công ty/merchant được phê duyệt?
2. Cách ánh xạ `company_xid` với end-user: một công ty cho mỗi user hay cấp tổ chức khác? Hạn mức và biểu phí từng model?
3. Với từng ngân hàng và loại tài khoản: có hỗ trợ debit, lịch sử tối đa bao lâu, balance endpoint và độ trễ cập nhật bao nhiêu?
4. IPN Bank Hub có hỗ trợ HMAC không, hay chỉ `Apikey` + allowlist? Danh sách IP chính thức ở production/sandbox?
5. Webhook trạng thái dùng đúng `POST /v1/webhook` và `X-Secret-Key` cho phiên bản hợp đồng hiện tại không?
6. Khi mất kết nối / tạm ngừng kích hoạt, nguồn nào hỗ trợ backfill và bao lâu?
7. Đơn vị có quyền hiển thị/ lưu dữ liệu tài chính lâu dài, cấp quyền cho thành viên gia đình, và chia sẻ phân tích dạng tổng hợp hay không?
8. SLA, rate limit Bank Hub, cơ chế hỗ trợ sự cố và thông báo breaking changes được cam kết thế nào?
9. Những loại quỹ/đóng góp qua QR nào được dùng mà không cần VA chuyên biệt hoặc payment gateway?
10. Giá Bank Hub, phí mở link, phí giao dịch, thử nghiệm, điều kiện hợp đồng và DPA bảo vệ dữ liệu?

## 20. HƯỚNG DẪN GIAO VIỆC CHO AI IDE / ĐỘI LẬP TRÌNH

> Thiết kế và triển khai module Financial Connectivity cho ứng dụng Life OS (Flutter Android/iOS + NestJS/PostgreSQL/Redis) theo đặc tả này. Không clone logo/nhãn hiệu SePay và không giả lập chức năng truy cập ngân hàng khi chưa có hợp đồng. Bắt đầu bằng nền tảng dữ liệu canonical, inbox/outbox, idempotency, ledger và quyền riêng tư. Xây `IBankConnectionProvider` độc lập với SePay; một adapter `SepayBankHubAdapter` có sandbox config và mock fixtures; một adapter `AndroidBankNotificationSource` chỉ giữ evidence provisional. Mỗi module phải có unit/integration/contract tests, migration rollback, OpenAPI và audit trail. Triển khai theo thứ tự giai đoạn A-E. Không coi redirect là xác minh link thành công, không dùng `accumulated=0` Bank Hub làm số dư thực, không nhân đôi chi tiêu khi đồng bộ đa nguồn, không để thành viên gia đình xem dữ liệu private. Bất kỳ trường nào không có trong tài liệu SePay phải đánh dấu UNVERIFIED và cô lập trong cấu hình; không hardcode hoặc tự đoán endpoint. Trước khi mở production yêu cầu toàn bộ T01-T24 qua và security review.

## 21. NGUỒN THAM KHẢO CHÍNH THỨC VÀ REPOSITORY

- **[S1]** SePay Developer - Tổng quan Bank Hub và ma trận ngân hàng: https://developer.sepay.vn/vi/bankhub/tong-quan
- **[S2]** Bank Hub - Tổng quan API và môi trường: https://developer.sepay.vn/vi/bankhub/api/tong-quan-api
- **[S3]** SePay API v2: https://developer.sepay.vn/vi/sepay-api/v2/gioi-thieu
- **[S4]** SePay Cổng thanh toán/SDK Node.js: https://developer.sepay.vn/vi/cong-thanh-toan/sdk/nodejs
- **[S5]** Bank Hub - IPN biến động số dư: https://developer.sepay.vn/vi/bankhub/thong-bao-bien-dong-so-du
- **[S6]** Bank Hub - 14 webhook events: https://developer.sepay.vn/vi/bankhub/webhook-event
- **[S7]** Bank Hub - Tạo Hosted Link Token: https://developer.sepay.vn/vi/bankhub/api/link-token/tao-link-token
- **[S8]** Bank Hub - API cấu hình webhook: https://developer.sepay.vn/vi/bankhub/api/api-webhook/cap-nhat-webhook
- **[S9]** SePay Webhooks thường - Xác thực, HMAC: https://developer.sepay.vn/vi/sepay-webhooks/xac-thuc
- **[S10]** Android NotificationManager/Notification Listener: https://developer.android.com/reference/android/app/NotificationManager
- **[S11]** Gmail API Push: https://developers.google.com/workspace/gmail/api/guides/push
- **[S12]** Restricted scopes / security assessment: https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- **[S13]** SePay API v2 - Danh sách giao dịch: https://developer.sepay.vn/vi/sepay-api/v2/giao-dich/danh-sach
- **[S14]** SePay - Hướng dẫn đối soát: https://developer.sepay.vn/vi/sepay-webhooks/doi-soat-giao-dich
- **[S15]** Google Play user data policy: https://support.google.com/googleplay/android-developer/answer/10144311
- **[S16]** SePay bảng giá bán lẻ: https://sepay.vn/bang-gia.html
- **[S17]** Bank Hub Sandbox: https://developer.sepay.vn/vi/bankhub/thong-tin-sandbox
- **[G1]** GitHub SePay chính thức Node Payment SDK: https://github.com/sepayvn/sepay-pg-node (chỉ cho Payment Gateway; MIT theo repo)
- **[G2]** GitHub SePay Laravel integration: https://github.com/sepayvn/laravel-sepay (tham khảo webhook, migration; MIT)
- **[G3]** Actual Budget: https://github.com/actualbudget/actual (tham khảo local-first + budgeting, không dùng làm connector ngân hàng)
- **[G4]** Firefly III: https://github.com/firefly-iii/firefly-iii (tham khảo expense taxonomy và budgets)
- **[G5]** HomeBox: https://github.com/sysadminsmedia/homebox (tham khảo lưu tài sản/bảo trì; cần xem giấy phép trước khi sao chép code)

**Phạm vi xác thực:** Đây là đặc tả tái tạo lớp chức năng và tích hợp công khai, không là bản chép mã nguồn hay reverse engineering hệ thống ngân hàng của SePay. Không có quyền truy cập hoặc kết quả chạy thực tế với merchant Bank Hub của người dùng; các API chưa được test trong tenant của người dùng.
