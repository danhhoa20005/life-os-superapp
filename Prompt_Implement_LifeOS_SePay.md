# PROMPT TRIỂN KHAI FINANCIAL CONNECTIVITY CHO LIFE OS

## Vai trò
Bạn là Lead Software Architect kiêm Security Engineer và Full-stack Engineer. Xây dựng module quản lý giao dịch, kết nối ngân hàng, phân loại chi tiêu và quản lý quỹ gia đình theo tài liệu đính kèm `SePay_LifeOS_Blueprint_2026.md`. Không được tự coi code mẫu là code chạy production hoặc điền bừa credentials.

## Công nghệ mục tiêu
- Flutter + Riverpod/Drift cho mobile.
- Kotlin Android `NotificationListenerService` cho nguồn notification có opt-in.
- NestJS TypeScript cho backend; PostgreSQL, Redis/BullMQ, Prisma hoặc Drizzle (chọn một ORM và nhất quán).
- REST OpenAPI + Zod/DTO validation; Docker Compose cho local; GitHub Actions CI.

## Luật bất biến
1. Không scrape ngân hàng, lưu password, cookie, OTP. Liên kết qua SePay Hosted Link được cấp theo hợp đồng.
2. Client không được giữ SePay client_secret, API key webhook, refresh token, merchant secret.
3. Phân biệt `BankHub IPN`, `BankHub lifecycle webhook`, `SePay User API webhook`, và `Payment Gateway IPN`: route/schema/auth khác nhau.
4. Mọi sự kiện lưu vào `source_events` bằng unique key trong transaction SQL; ghi `outbox` cùng transaction, worker retry idempotent.
5. Không cộng trùng giao dịch từ Android và Bank Hub; không đếm chuyển tiền nội bộ là chi tiêu.
6. `accumulated=0` từ Bank Hub IPN không có nghĩa số dư tài khoản bằng 0.
7. Giao dịch lấy từ notification/Gmail là `PROVISIONAL`; chỉ đổi VERIFIED khi có nguồn kiểm chứng ngân hàng.
8. Family admin không tự có quyền xem tài khoản, giao dịch hoặc lịch PRIVATE của thành viên.
9. Quỹ gia đình là ledger/budget, không nắm giữ tiền thực hoặc tự chuyển tiền.
10. Secrets từ môi trường/vault, log redaction, user consent, audit, soft-delete và export.

## Công việc theo thứ tự

### Milestone 0 - Audit và kiến trúc
- Đọc toàn repo và lập inventory package/module; không làm hỏng phần code đã có.
- ADR cho normalized transaction, ingestion pipeline, ledger double-entry, ownership/visibility, offline sync.
- Danh mục giả định phải xác minh với SePay. Mọi endpoint chưa kiểm chứng đánh dấu `UNVERIFIED`.

### Milestone 1 - Core Finance
- Migrations: users, family memberships, accounts, bank connections, source_events, outbox, transactions, transaction evidence, ledger, categories, budgets, fund ledger, audit, consents.
- Seed data giả lập và idempotent imports.
- API CRUD giao dịch, split/refund/internal transfers, source verification and privacy guards.
- Unit/integration test cho invariants.

### Milestone 2 - Android Observation
- Native NotificationListenerService with settings onboarding, opt-in allowlist by bank package.
- On-device parsers and encrypted local queue; reject OTP/other apps.
- Evidence sync with idempotency and user confirmation UX.
- Golden fixtures and tests cho thông báo bị gộp, mất và nội dung thay đổi.

### Milestone 3 - SePay Bank Hub adapter
- Adapter interface/provider factory; sandbox/prod env separation.
- Server-only token acquisition and TTL caching; link token creation, hosted flow, status polling/recheck; lifecycle webhooks.
- Dedicated authenticated Bank Hub IPN endpoint; payload validation, inbox/outbox; mapping by bank_account_xid.
- Transaction pagination, retry 429, reconciliation cursors and overlap windows.
- Capability matrix by bank, no unsupported balance or debit claims.
- Mocked contract tests; sandbox tests when credentials available.

### Milestone 4 - Household and Fund
- Member join/leave, role ACL/RLS, shared funds (virtual ledger), contribution audit, privacy summaries.
- Task assignment without exposing calendars, optional free/busy sharing.
- Dashboard per user with source reliability badges.

### Milestone 5 - Google, Vehicles and Operations
- Google Calendar/Tasks OAuth only for selected scopes; Gmail feature flag behind policy/verification.
- Vehicles, maintenance, bills, recurring spend classification, reminders.
- Monitoring metrics, webhook replay UI, backup/restore, observability and security check.

## Test & Acceptance Gate
- Implement all test scenarios T01-T24 in `SePay_LifeOS_Blueprint_2026.md` and add concurrency tests.
- Demonstrate duplicate webhook 5x -> 1 ledger posting; two same-amount legitimate payments -> 2 postings.
- Demonstrate cross-user/houshold denied access at API and DB layers.
- Demonstrate request ack only after event persisted, and worker retry after crash.
- Demonstrate Android provisional transaction upgraded to Bank API verified without duplicate.
- Run lint, typecheck, unit, integration, build, migration up/down before declaring a milestone complete.

## Cách làm việc
- Tiếp tục triển khai theo thứ tự, không dừng chỉ để xin xác nhận về chi tiết kỹ thuật có thể quyết định bằng quy tắc đã nêu.
- Với blocker thực sự (chưa có SePay partner credentials, chưa có OAuth verification), tạo mock connector và đóng gói `BLOCKED_BY_EXTERNAL_DEPENDENCY.md` với hành động chính xác người dùng cần làm. Không khẳng định đã kiểm chứng live.
- Ghi lại mọi thay đổi, migration, test results và known limitations ở `docs/IMPLEMENTATION_STATUS.md`.
- Không thay thế code hiện hữu trên GitHub hoặc push/deploy production nếu không có quyền được cấp.
- Kết quả cuối cần có mã nguồn sạch, môi trường local chạy được bằng Docker Compose, OpenAPI docs và hướng dẫn thử SePay sandbox.
