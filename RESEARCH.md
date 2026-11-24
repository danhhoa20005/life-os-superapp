# Cơ sở nghiên cứu v6.0 — nguồn và quyết định kỹ thuật

Đối chiếu tài liệu nền tảng ngày 24/11/2026. Danh mục GitHub dưới đây là nguồn để agent tra cứu implementation liên quan; không tuyên bố đã kiểm toán toàn bộ repository hay tất cả tag. Trước khi áp dụng, xác minh license, SDK constraints, commit/tag và API tại thời điểm làm việc.

## A. Multi-model: hỗ trợ thực tế

| Nguồn chính thức | Quyết định thiết kế |
|---|---|
| [Choose a model](https://antigravity.google/docs/models) | Planner và executor có thể chọn theo gói; Orchestrator là luân chuyển trong một phiên, không mặc nhiên song song. Nano Banana 2 thuộc công cụ ảnh, không phải reasoning model cho worker. |
| [Custom subagents](https://antigravity.google/docs/subagents) | Custom Markdown frontmatter, tier inherit/flash/pro, context riêng, workspace branch, chạy async. Không đưa slug Carbon tùy ý vào YAML. |
| [Swarm](https://antigravity.google/docs/swarm) | Điều phối nhiều worker cùng board cho công việc phân rã độc lập; quota tiêu thụ nhanh hơn. |
| [Boost](https://antigravity.google/docs/boost/) | Tập trung vào bài toán khó và kiểm chứng qua vòng lặp. |
| [Teamwork](https://antigravity.google/docs/teamwork/) | Dự án nhiều milestone và audit gate. |
| [Dynamic Workflows](https://antigravity.google/docs/dynamic-workflows) | Chạy pipeline có phase tuần tự hoặc song song, với phê duyệt script và kết quả có cấu trúc. |
| [Rules](https://antigravity.google/docs/rules/) | AGENTS.md và global/workspace paths chính thức. |
| [Headless CLI](https://antigravity.google/docs/cli/headless/) | `agy models`, `agy -p --model`, `--output-format`, `--print-timeout`; pin model và phát hiện lỗi. |
| [CLI reference](https://antigravity.google/docs/cli/reference/) | Chế độ plan/accept-edits, sandbox; runner không bỏ qua quyền. |
| [SDK](https://antigravity.google/docs/sdk/overview/) | Nếu xây orchestrator riêng, dùng SDK chính thức và xác minh schema; không dùng API suy đoán. |
| [Git worktree](https://git-scm.com/docs/git-worktree) | Worktree cô lập working directory; vẫn chia sẻ repository storage, nên commit/branch/cache chung cần quản lý. |

Các model slug mẫu được lấy từ tài liệu CLI: `gemini-4-carbon-high`, `gemini-4-neon-high`, `gemini-4-hydrogen-medium`. Chỉ dùng sau khi kiểm tra danh sách tài khoản. Không yêu cầu toàn bộ model High/Max; dùng đúng effort mà runtime công bố. Với model ảnh, [Gemini image generation](https://ai.google.dev/gemini-api/docs/image-generation) là tài liệu kiểm tra model ID, khả năng ảnh và điều kiện API nếu cần pipeline ngoài IDE.

## B. Flutter và Android

| Nguồn | File/thư mục hoặc chủ đề cần đọc | Điều không được suy diễn |
|---|---|---|
| [Flutter architecture guide](https://docs.flutter.dev/app-architecture/guide) và [recommendations](https://docs.flutter.dev/app-architecture/recommendations) | UI/Data, repository, UDF, domain tùy độ phức tạp | Google không bắt buộc BLoC hoặc Clean Architecture ba tầng mọi feature. |
| [flutter/samples](https://github.com/flutter/samples/tree/main/compass_app) | Compass app, repository, DI, test | Không sao chép state manager nếu repo chọn BLoC. |
| [very_good_cli](https://github.com/VeryGoodOpenSource/very_good_cli) | Templates, `AGENTS.md`, test scaffolding | Template không tự chứng minh kiến trúc enterprise. |
| [very_good_analysis](https://github.com/VeryGoodOpenSource/very_good_analysis) | Lint rules | Kiểm tra SDK và quy tắc dự án trước khi thêm. |
| [very_good_workflows](https://github.com/VeryGoodOpenSource/very_good_workflows) | CI workflows | Không tự cài pipeline/deploy có phí. |
| [felangel/bloc](https://github.com/felangel/bloc) | `packages/bloc`, `flutter_bloc`, `bloc_concurrency`, `bloc_test`; event transformer source/test | Transformer không bảo đảm transaction, cancellation I/O hoặc khóa toàn hệ thống. |
| [get_it](https://github.com/flutter-it/get_it) | Registration, scope, disposal, release notes | Kiểm tra version trước khi khẳng định LIFO hoặc circular guard. |
| [fpdart](https://github.com/SandroMaglione/fpdart) | Either, TaskEither | Không bắt buộc migration toàn repo, không gọi thư viện khác lỗi thời chỉ vì khác lựa chọn. |
| [Flutter performance](https://docs.flutter.dev/perf) và [DevTools](https://github.com/flutter/devtools) | Frame profiling, memory, rebuild | 120 FPS là mục tiêu trên thiết bị phù hợp, không phải guarantee. |
| [Android architecture](https://developer.android.com/topic/architecture) | UDF, lifecycle, Compose, data layer | Không áp Fragment-only cho ứng dụng Compose. |
| [Now in Android](https://github.com/android/nowinandroid) | Compose, modularization, offline-first, testing | Dùng làm tham chiếu, không áp mọi module vào app nhỏ. |
| [Turbine](https://github.com/cashapp/turbine) | Flow test, cancellation | Không thay integration tests. |
| [OWASP MASVS](https://github.com/OWASP/owasp-masvs) | Mobile security verification | Chỉ được gọi là đạt các control đã kiểm tra. |

Các mốc package để đối chiếu: [flutter_bloc](https://pub.dev/packages/flutter_bloc), [bloc_concurrency](https://pub.dev/packages/bloc_concurrency), [get_it](https://pub.dev/packages/get_it), [fpdart](https://pub.dev/packages/fpdart). Không cố định toàn hệ thống vào một bộ version không đổi.

## C. Đồ họa, animation và asset pipeline

| Nguồn | Áp dụng |
|---|---|
| [Flutter framework](https://github.com/flutter/flutter), [Impeller](https://docs.flutter.dev/perf/impeller) | CustomPainter, GPU render, profiling theo platform. |
| [perfect-freehand](https://github.com/steveruizok/perfect-freehand), [perfect-freehand-dart](https://github.com/steveruizok/perfect-freehand-dart) | Stroke geometry, pressure và smoothing; kiểm tra license/fixture. |
| [Material Design](https://m3.material.io/), [Flutter animation](https://docs.flutter.dev/ui/animations) | Motion tokens, transitions, tương tác và accessibility. |
| [ComfyUI](https://github.com/Comfy-Org/ComfyUI) | Workflow ảnh local, GPU, queue; kiểm tra license từng checkpoint/node. |
| [Material Symbols](https://github.com/google/material-design-icons), [Lucide](https://github.com/lucide-icons/lucide) | Icon vector theo bộ; không trộn nhiều phong cách tùy tiện. |
| [SVGO](https://github.com/svg/svgo), [Pillow](https://github.com/python-pillow/Pillow), [rembg](https://github.com/danielgatis/rembg) | Tối ưu SVG, kiểm tra dimension/alpha, hậu kỳ ảnh; kiểm tra model license nếu tách nền bằng AI. |
| [Aseprite](https://github.com/aseprite/aseprite), [Aseprite docs](https://github.com/aseprite/docs) | Atlas/frame metadata/CLI; xem điều khoản license trước khi dùng bản build. |
| [Flame](https://github.com/flame-engine/flame) | Sprite animation, game loop, asset loading. |
| [flutter_launcher_icons](https://github.com/fluttercommunity/flutter_launcher_icons) | App icon generation theo platform. |
| [Blender Python API](https://docs.blender.org/api/current/), [glTF Validator](https://github.com/KhronosGroup/glTF-Validator) | Mesh thật, UV/material, export GLB và validation. |
| [Lottie](https://github.com/airbnb/lottie-android), [Rive Flutter](https://github.com/rive-app/rive-flutter) | Animation runtime, kiểm tra asset thật và version compatibility. |

## D. Ví dụ phân rã cho app và game

**LifeOS – thêm dashboard ngân sách:** Carbon chốt money model, idempotency và contract; Neon dựng UI, Hydrogen triển khai query/mapper/test theo interface; Creative tạo banner/empty state phù hợp brand; Lead quản lý router/DI, QA kiểm tra transaction và dark mode trên bản tích hợp. Không dùng dữ liệu ngân hàng thật làm prompt/test fixture.

**Color World – thêm brush:** Carbon chốt stroke geometry, document contract; Developer A làm thuật toán, Developer B UI điều khiển; Creative tạo brush tip và preview khi license cho phép; QA lập fixture ABR/pressure và đo frame trên thiết bị. Không chỉnh engine/cache chung đồng thời khi chưa chốt owner.

**Game Unity/Flutter:** Carbon chốt asset contract và gameplay interface; Neon triển khai HUD/gameplay, Hydrogen viết test/import automation; Creative làm sprite/texture/model song song. Integration gate kiểm tra atlas/pivot, scene, memory, input và build. Không dùng ảnh 3D render thay mesh.

## E. Các điểm sửa từ v5.0

- Chuyển từ prompt phân vai tượng trưng sang cơ chế runtime có bằng chứng; thêm worktree, DAG, single-writer và pin slug tùy chọn.
- Thêm Ban Creative và pipeline sinh, hậu kỳ, kiểm tra asset thật.
- Bỏ yêu cầu độ trễ 0 ms, 120 FPS vô điều kiện, mọi GPU task vào isolate, Fragment-only, xóa toàn bộ branch phụ, cố định version và max effort cho mọi tác vụ.
- Giữ chuẩn BLoC không Cubit, identifier tiếng Anh, comment nghiệp vụ tiếng Việt, main/developer là nhánh dài hạn nếu đang áp dụng.
- Bổ sung retry bounded, baseline, acceptance, security, license và phân biệt chưa kiểm thử với đã đạt.
