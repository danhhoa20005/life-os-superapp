# BÁO CÁO KẾT QUẢ KIỂM THỬ FIREBASE EMULATOR & CLOUD (FIREBASE TEST RESULTS)

**Ngày kiểm chứng:** 22/11/2026 | **Dự án Emulator:** `demo-life-os` | **Môi trường:** Flutter `3.47.0` + Firebase CLI `15.27.0`

---

## 1. Bảng Kiểm chứng 15 Kịch bản Bắt buộc (`PHẦN 12`)

Thực thi trực tiếp trên **Firebase Authentication Emulator (`127.0.0.1:9199`)** và **Cloud Firestore Standard Emulator (`127.0.0.1:8188`)** qua lệnh:
```powershell
firebase emulators:exec --only auth,firestore --project demo-life-os "node firebase/rules_tests/run_full_emulator_e2e.mjs"
```

| STT | Kịch bản Kiểm thử (`PHẦN 12`) | Kết quả | Bằng chứng Xác minh |
| :---: | --- | :---: | --- |
| 1 | Tạo tài khoản (`signUp` Email/Password) | **PASS** | IdentityToolkit `:signUp` trả `200`, sinh `localId`, `idToken`, `refreshToken`. |
| 2 | Đăng nhập & Khôi phục phiên (`signInWithPassword` + `securetoken`) | **PASS** | Đăng nhập & đổi `refreshToken` sang `id_token` mới trả `200`. |
| 3 | Tạo Profile người dùng (`/users/{uid}`) & chặn lưu `password` | **PASS** | Ghi profile hợp lệ trả `200`; cố ghi trường `password` bị `firestore.rules` chặn `403`. |
| 4 | Thêm Document (`wallets`, `transactions`, `private_events`, `families`, `split_bills`) | **PASS** | Toàn bộ thao tác tạo hợp lệ trả `200`. |
| 5 | Đọc Document (`GET /users/{uid}/transactions/op_tx_001`) | **PASS** | Đọc chính xác `amountMinor = 85000`, `currencyCode = 'VND'`. |
| 6 | Chỉnh sửa Document (`PATCH /users/{uid}/private_events/ev_priv_1`) | **PASS** | Chủ sở hữu cập nhật sự kiện riêng tư trả `200`. |
| 7 | Xóa Document theo quyền (`DELETE private_events` vs `DELETE transactions`) | **PASS** | Xóa `private_events` trả `200`; xóa cứng `transactions` bị khóa sổ bất biến trả `403`. |
| 8 | Đồng bộ phiên đa thiết bị & Realtime Streams | **PASS** | Phiên đăng nhập thiết bị thứ 2 đọc tức thì `split_bills/sb_01` do thành viên khác vừa tạo (`300.000 ₫`); xác minh thêm trong `all_feature_blocs_test.dart`. |
| 9 | Tài khoản khác không đọc được dữ liệu riêng | **PASS** | `User B` gọi `GET /users/{userA}/transactions` và `private_events` bị từ chối `403`. |
| 10 | Tài khoản khác không sửa được dữ liệu riêng | **PASS** | `User B` gọi `PATCH /users/{userA}/wallets/w_vcb` bị từ chối `403`. |
| 11 | Phân quyền thành viên gia đình (`Owner` / `Member` / `Outsider`) | **PASS** | Thành viên đọc/ghi `split_bills` & `funds` trả `200`; người lạ (`outsiderC`) nhận `403`; cấm `list` toàn bộ `family_invites` (`403`). |
| 12 | Ngăn tự nâng quyền (`Role Self-Escalation`) | **PASS** | `User B` dùng mã mời hợp lệ nhưng tự gán `role: 'admin'` hoặc `'owner'` nhận `403`; chỉ `role: 'member'` mới nhận `200`. |
| 13 | Ngăn ghi dữ liệu không hợp lệ | **PASS** | `amountMinor = -50000` hoặc `0`, hoặc giả mạo `ownerId` của người khác đều bị từ chối `403`. |
| 14 | Ngăn giao dịch trùng lặp (`Idempotency`) | **PASS** | Khóa `operationId` với `currentDocument.exists=false` trả `409 Conflict` khi gửi trùng; `TransactionRemoteDataSource` và `source_events` khử trùng 5x trong `mvp_vertical_slice_test.dart`. |
| 15 | Kiểm tra các truy vấn có Composite Indexes | **PASS** | `runQuery` lọc `monthKey == '2026-11'` kết hợp `ORDER BY occurredAt DESC` khớp `firestore.indexes.json` trả `200`. |

---

## 2. Kết quả Toàn bộ Bộ Kiểm thử Flutter & Build

- `flutter analyze`: **`0 issues`**
- `flutter test --reporter expanded`: **`21/21 PASS`** (bao gồm kiểm chứng `SparkSafeFileStorageService`, `SplashPage` & 8 tài nguyên Nano Banana, Clean Architecture Guard `0% Cubit`, BLoC Concurrency, Vertical Slice Integration).
- `flutter build web --release`: **PASS** (`build/web`)
- `flutter build apk --debug`: **PASS** (`build/app/outputs/flutter-apk/app-debug.apk`)
- **Kiểm thử trên Firebase Cloud thật (`firebase/verify_live_cloud_crud.mjs`):** Sẵn sàng thực thi ngay sau khi người dùng xác nhận đăng nhập lại `firebase login --reauth` (hiện đang ở trạng thái `BLOCKED` do OAuth refresh token hết hạn).
