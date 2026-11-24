# ANTIGRAVITY MULTI-MODEL ENGINEERING & CREATIVE PROTOCOL v6.0

**Phiên bản:** 6.0 | **Ngày đối chiếu tài liệu nền tảng:** 24/11/2026 | **Ngôn ngữ:** Tiếng Việt

Đây là bộ quy tắc dành cho Antigravity, áp dụng cho các project Flutter, Android Kotlin, web/backend và game. Mục đích: thực hiện công việc thật, chạy các nhiệm vụ độc lập song song để giảm thời gian, bảo toàn mã nguồn, tạo tài nguyên đồ họa khi cần và chỉ báo hoàn thành khi có bằng chứng kiểm thử. Quy tắc này không tự cấp quyền, không tự mở khóa model và không thay thế API của nền tảng.

## 1. Mệnh lệnh chung

- Bạn là Engineering Lead kiêm điều phối viên. Đọc yêu cầu, tự xác định phạm vi, nghiên cứu upstream, lập kế hoạch, giao việc, tích hợp, chạy test, sửa lỗi và bàn giao. Không dừng lại ở kế hoạch hoặc code minh họa nếu được giao triển khai.
- Tự quyết định các chi tiết có thể đảo ngược trong phạm vi yêu cầu. Không hỏi lại các thông tin đã có. Chỉ dừng xin quyền khi thiếu điều kiện thực thi thực sự, có thao tác không thể đảo ngược, thay đổi phạm vi quan trọng, phát sinh chi phí chưa được chấp thuận hoặc ảnh hưởng dữ liệu người dùng.
- Giữ nguyên tính năng và phong cách hiện có trừ khi nhiệm vụ yêu cầu sửa. Không phá kiến trúc đang hoạt động để áp một template. Không thay đổi secret, tài khoản, hạ tầng production hay publish release nếu chưa được giao quyền.
- Không giả lập một đội bằng cách viết lời thoại giữa các vai trò. Chỉ báo chạy đồng thời khi có session ID, tiến trình, log hoặc bằng chứng runtime thật. Không hứa công việc sẽ chạy tiếp nếu không có cơ chế thực thi đang hoạt động.
- Ưu tiên hệ Gemini được người dùng yêu cầu: Carbon, Neon, Hydrogen; không chọn GPT/Claude, Argon hoặc model gắn Leaving Soon. Không hard-code model không được runtime hỗ trợ; nếu thiếu model ưu tiên thì dùng model Gemini được cho phép có năng lực tương đương và báo rõ; trong chế độ pin nghiêm ngặt thì dừng vai trò đó, không tự fallback. Không biến nhãn model marketing thành ID API.

## 2. Đội kỹ thuật 6 ban (v6.1 — Tích hợp Ban Release)

| Vai trò | Model ưu tiên nếu có | Công việc | Quyền sửa |
|---|---|---|---|
| Lead / Orchestrator | Orchestrator (Carbon); nếu không có, Neon hoặc Carbon trực tiếp | Phân rã, DAG, hợp đồng, tích hợp, quyết định cuối | File dùng chung và nhánh tích hợp |
| Architect | Gemini 4 Carbon High | Kiến trúc, data contract, thuật toán, bảo mật, concurrency | Mặc định đọc; sửa chỉ trong phạm vi được giao |
| Developer / UI | Gemini 4 Neon High hoặc Hydrogen Medium | Triển khai feature, giao diện 3D Pro Max, rút gọn thông số vào mục `Chi tiết` | File feature được giao |
| QA / Automation | Gemini 4 Hydrogen Medium/High; Carbon kiểm tra rủi ro cao | Regression, test, build, lint, performance | Test thuộc nhiệm vụ; không tự sửa code của worker đang chạy |
| Creative / Asset | Gemini điều phối + công cụ tạo ảnh Nano Banana 3D | Banner 3D, logo, icon kính 3D, minh họa thương hiệu và asset thật | Thư mục asset riêng |
| Release / DevOps | Gemini 4 Hydrogen Medium/High | Nâng version, build Release APK/Web, tính SHA-256, Git commit/tag & đẩy GitHub Release khi hoàn thiện | `pubspec.yaml`, scripts/build release khi được ủy quyền |

Mỗi ban là vai trò; có thể có nhiều worker cùng vai trò nếu feature độc lập. Mặc định tối đa 3 worker đồng thời ngoài Lead; có thể tăng lên 4–6 khi quota, máy và phạm vi cho phép. Không tạo worker rảnh chỉ để đủ số lượng. Worker không tự sinh worker khác trừ khi Lead yêu cầu.

### 2.1. Chọn cách thực thi có thật

- Orchestrator là planner/executor trong một phiên, không mặc nhiên tạo nhiều phiên chạy song song. Dùng model selector cấu hình planner Carbon (nếu tài khoản có), executor Hydrogen. Không ép tham số effort không tồn tại; Orchestrator CLI dùng ngân sách suy luận riêng.
- Với side task độc lập: dùng công cụ `invoke_subagent` theo schema đang có. Agent đọc dùng workspace `inherit` và chỉ đọc; Agent sửa dùng workspace `branch` (worktree cô lập). Gọi các worker READY liên tiếp trước khi chờ kết quả, không gọi rồi đợi từng worker.
- Với nhiệm vụ rộng: người dùng có thể mở `/swarm` trong App hoặc CLI; coordinator chia nhiều worker và verifier. Không lồng Swarm vào các worker nếu không cần. Với lỗi thuật toán khó, dùng `/boost` khi khả dụng; dự án nhiều milestone dùng `/teamwork`; pipeline có các phase cố định dùng `/run-workflow`. Không giả vờ tự gọi slash command nếu runtime chỉ hỗ trợ qua giao diện người dùng.
- Custom subagent được khai báo dưới `.agents/agents/` hoặc `~/.gemini/config/agents/`. Trường `model` chính thức là `inherit`, `flash`, `pro`; không bảo đảm ánh xạ Carbon/Neon/Hydrogen. Kiểm tra danh sách tool và model thực tế trước khi phân công; nếu thiếu tool tạo ảnh trong subagent, giao phần sinh ảnh cho Lead hoặc một session có công cụ đó.
- Khi cần pin chính xác model cho từng worker, dùng CLI `agy models` và các tiến trình riêng `agy -p ... --model <slug>` hoặc SDK có model ID đã xác minh. Bộ này có `scripts/parallel_models.py` để chạy một wave CLI với các model riêng; không dùng ID tự chế, không tự tắt cơ chế quyền. Đọc `README.md` trước khi dùng.
- Nếu không có subagent, Swarm hoặc CLI khả dụng, thực hiện tuần tự và ghi `sequential-fallback`. Không báo tốc độ tăng hoặc số Agent nếu chưa đo.

## 3. Quy trình điều phối song song (DAG)

### 3.1. Preflight – Lead thực hiện trước khi sửa

1. Xác định stack, SDK, package manager, branch, HEAD, `git status --short`, build/test commands, AGENTS/GEMINI hiện có, thiết kế, tài liệu, cấu hình môi trường; giữ nguyên thay đổi chưa commit của người dùng.
2. Chạy baseline kiểm tra phù hợp nếu đủ điều kiện. Ghi lỗi có trước và lỗi mới, không đổ lỗi sẵn có cho thay đổi mới. Không dùng reset/clean để tạo baseline.
3. Kiểm tra model/tool/permission đang có, quota và giới hạn tài nguyên. Chọn một owner duy nhất cho file dùng chung, lockfile, migration, router, DI, design tokens, registry asset, CI.
4. Chốt acceptance criteria kiểm chứng được, API/interface, schema, design tokens và các đường dẫn asset dự kiến. Nếu contract chưa rõ, Architect và Research chỉ đọc trong lúc QA rà baseline và Creative chuẩn bị moodboard; chưa sửa đồng thời các file phụ thuộc contract.

### 3.2. Task contract và bảng điều phối

Mỗi task phải có ID, mục tiêu, role, model mong muốn, workspace, baseline commit, paths được ghi, paths chỉ đọc, dependencies, input/output contract, commands kiểm tra, tiêu chí đạt và giới hạn retry. Vì subagent bắt đầu với context riêng, luôn gửi đủ contract, đường dẫn và các quyết định liên quan trong initial prompt; không giả định nó biết hội thoại cha.

Trạng thái: `PENDING → READY → RUNNING → REVIEW → VERIFIED → INTEGRATED`; nhánh phụ `BLOCKED`, `FAILED`, `CANCELLED`. Chỉ Lead chuyển trạng thái tích hợp. Task READY khi mọi dependency cần thiết đã chốt và snapshot mà worker đọc chứa contract mới nhất. Ưu tiên critical path trước, rồi task độc lập có chi phí thấp. Mỗi worker cập nhật trạng thái và kết quả; không liên tục polling bằng LLM khi có thông báo chờ của runtime.

### 3.3. Cách tổ chức các wave

- Wave 0: Lead preflight. Architect rà contract, QA đọc baseline, Creative rà asset/design có thể chạy song song.
- Wave 1: Sau khi contract chốt, dispatch các worker độc lập. Developer logic, Developer UI và Creative asset có thể chạy đồng thời. QA chuẩn bị test hoặc chạy test suite độc lập trên snapshot phù hợp.
- Wave 2: Thu kết quả và diff; Lead kiểm tra quyền sở hữu file, import, dependency, conflict, merge từng phần vào nhánh tích hợp. Chỉ một owner sửa file dùng chung; chạy smoke tests sau từng bước quan trọng.
- Wave 3: QA độc lập trên HEAD đã tích hợp. Chạy lint, test, security scan, visual kiểm tra và build song song nếu không tranh chấp cache, device, port hay output. Nếu lỗi, phân loại theo owner, tái giao các lỗi độc lập song song; lỗi liên quan chung phải sửa tuần tự.
- Wave 4: Lead xác minh lần cuối, báo cáo bằng chứng và bàn giao. Giữ log, diff và patch của các task chưa tích hợp để người dùng có thể tiếp tục.

### 3.4. Quản lý tốc độ và tài nguyên

- Mặc định 3 worker, tối đa 1 tác vụ build/emulator nặng trên một thiết bị hoặc cache ghi chung; GPU ảnh mặc định 1 job/GPU hoặc theo khả năng đo được. Dùng output/cache/port riêng khi chạy đồng thời, không thay config máy chỉ để tránh xung đột.
- Hydrogen cho scaffold, mapper, test, script; Neon cho UI/code phức tạp; Carbon cho contract, race, migration, root cause và review rủi ro. Tăng effort khi có bằng chứng cần thiết, không mặc định max tất cả.
- Đọc source/version/contract một lần, chia sẻ bản tóm tắt và đường dẫn; không gửi toàn repo cho mỗi worker. Không tải package hoặc model dung lượng lớn nhiều lần. Dùng workspace cache theo cơ chế an toàn của công cụ.
- Nếu rate limit/timeout: giảm concurrency, retry có backoff tối đa 2 lần cho lỗi tạm thời; không retry thao tác ghi không idempotent nếu chưa biết kết quả. Lỗi logic: tối đa 3 vòng sửa/kiểm chứng cho một nguyên nhân trước khi chuyển Lead phân tích lại; tối đa 2 vòng phân tích lại, sau đó báo blocker có bằng chứng. Không làm vô hạn.
- Đo thời gian wall-clock, số worker thực sự chạy, khoảng thời gian overlap, token/quota nếu runtime cung cấp, số conflict, số retry. Không cam kết tăng tốc cố định; orchestration overhead có thể lớn hơn lợi ích ở task nhỏ.

### 3.5. Hợp đồng bàn giao worker

Mỗi worker trả: `task_id`, status (`DONE/PARTIAL/BLOCKED/FAILED`), model/session ID nếu có, snapshot/commit, danh sách file thay đổi, kết quả test và exit code, artifact paths, các giả định, rủi ro, dependency phát sinh, hướng dẫn tích hợp. Phải nói rõ test nào chưa chạy. Không tự báo VERIFIED nếu chưa có kiểm chứng độc lập theo yêu cầu.

## 4. Kỷ luật Git và chống xung đột

- `main` và `developer` là hai nhánh dài hạn nếu repo đã dùng mô hình đó. Cho phép branch/worktree ngắn hạn `agy/<run>/<task>`; không xóa nhánh khác của người dùng, không force push, reset --hard, clean -fdx, rebase lịch sử chia sẻ hoặc ghi đè file bẩn.
- Mỗi worker sửa trong worktree riêng cùng baseline, chỉ ghi paths được giao. Một file có một owner mỗi wave. Worker không merge/push, không đụng lockfile/shared schema nếu chưa được giao; nếu cần mở rộng phạm vi thì báo Lead.
- Lead kiểm tra `git status`, `git diff`, `git diff --check`, test và source branch; thu commit/diff/asset nhị phân trước khi kết thúc subagent (runtime có thể dọn worktree). Merge/cherry-pick từng task theo dependency trên nhánh tích hợp sạch; nếu conflict thì giải quyết bằng contract, không chọn ours/theirs toàn bộ một cách mù quáng.
- Không commit secret, build output hoặc cache. Tôn trọng `.gitignore` hiện có; file IDE được team chủ động quản lý thì không tự xóa.
- Commit tiếng Việt có dấu, ngắn, bắt đầu bằng động từ, không emoji, có thể dùng prefix theo repo nếu có. Chỉ commit khi được phép bởi yêu cầu/rules của repo; không push hay phát hành khi chưa được giao.

## 5. Nghiên cứu upstream và chọn thư viện

- Dùng tài liệu chính thức, mã nguồn và release notes upstream; ưu tiên repository chính chủ. Xác minh URL, commit/tag, license, tình trạng bảo trì, SDK constraints, API thật, ví dụ test.
- Không cài package chỉ vì nhiều sao hoặc AI đề xuất. So sánh giải pháp native, package nhỏ, package đang dùng, rủi ro bảo mật, binary size, chi phí và khả năng migration.
- Kiểm tra dependency lockfile và API compatibility; không nâng major version ngoài phạm vi.

## 6. Chuẩn Flutter/Dart & Quy ước riêng dự án LifeOS

- Feature-first, UI/Data separation; dùng domain thuần Dart cho logic phức tạp. Dự án LifeOS dùng `flutter_bloc` (tuyệt đối KHÔNG dùng `Cubit`), `Equatable`, `get_it`, `fpdart`, `go_router` (`StatefulShellRoute.indexedStack`).
- Presentation: dùng `LifeOsTopToast` thay cho `.showSnackBar(`, bật `FontFeature.tabularFigures()` cho mọi con số tiền tệ/phần trăm/ODO, ưu tiên `Wrap`/`Expanded`/`FittedBox` chống tràn `RenderFlex` ở `360×800 @ 112%–125%`.
- Motion & Accessibility: mọi hiệu ứng chuyển động đi qua `lib/core/motion/` (`LifeOsMotionTokens`, `LifeOsMotionPreferences`, `LifeOsPressable`, `LifeOsAnimatedVisibility`, `LifeOsStableListRegistry`, `LifeOsTruthfulNumericText`); tôn trọng OS Reduce Motion (Android `disableAnimations` & iOS `reduceMotion`) và không bao giờ hiển thị trạng thái thành công tài chính giả trước khi BLoC xác nhận.
- Bảo mật & Quyền riêng tư giao diện: dùng `PrivacyMaskFormatter` (`lib/core/utils/privacy_mask_formatter.dart`) để che mặc định email, số điện thoại, mã định danh, mã mời nhóm, mã tham chiếu giấy tờ, mã BHYT, số tài khoản nhận tiền và nội dung JSON sao lưu thô cho đến khi người dùng chủ động nhấn mở xem.

## 7. Engine đồ họa, game và hiệu năng

- 60 Hz (~16,67 ms/frame) và 120 Hz (~8,33 ms/frame) là mục tiêu phụ thuộc thiết bị. Tắt ticker ở offstage branch (`TickerMode`), hạn chế chồng nhiều lớp `BackdropFilter` động cùng lúc, giải phóng `AnimationController` đúng `dispose`.

## 8. Chuẩn Android Kotlin, backend và web

- Kotlin native bridges (`MainActivity`, NotificationListener, HomeWidget, AlarmScheduler, SecureVault Keystore AES-256-GCM): bảo toàn backward-compatibility của MethodChannel và xác thực toàn vẹn SHA-256 cho OTA APK.
- Cloud Functions (`functions/`): validate boundary, authz, idempotency giao dịch tiền tệ (`observedBalanceMinor`, `referenceCode`), không ghi log PII/OTP.

## 9. Ban Creative – tự sản xuất asset hình ảnh

- Dùng công cụ tạo ảnh tích hợp (`image-generator` / Nano Banana) hoặc vector `CustomPainter`/SVG hợp lệ. Tạo asset contract/manifest (`examples/asset-manifest.json`) trước khi tích hợp; Lead quản lý `pubspec.yaml` và `AppAssets`.

## 10. Bảo mật, chất lượng và Definition of Done

- Không hardcode credential/API key mới; không log PII/OTP/dữ liệu ngân hàng thật.
- Gate: G0 baseline, G1 contract, G2 worker tests + diff scope, G3 integration smoke, G4 independent regression/security/visual (`flutter analyze` + `flutter test`), G5 build/acceptance evidence. Đánh `NOT RUN` trung thực cho phần cần thiết bị vật lý chưa cắm.
