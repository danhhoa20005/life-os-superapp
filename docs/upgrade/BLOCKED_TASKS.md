# BLOCKED TASKS & EXTERNAL DEPENDENCIES

Only tasks genuinely blocked by missing physical hardware, external partner credentials, or ungranted production deployment permissions are recorded here:

| ID | Task | Blocker Reason | Evidence | Implemented Fallback / Mitigation |
|---|---|---|---|---|
| `BLK-001` | Physical Android Device Sensor & OEM ROM Runtime Test (Live Mic, Camera viewfinder, Reboot `BOOT_COMPLETED`, Doze mode) | No physical Android device or AVD emulator is currently attached to the host machine. | `adb devices` / host environment has no connected handset. | Implemented full MethodChannel contracts, unit/widget driver simulations, and debug/release APK compilation verification; marked `NOT_TESTED` on physical hardware. |
| `BLK-002` | Live SePay Production Webhook & Real Bank Account Verification | Requires real partner SePay webhook secret, public domain routing, and live bank account credentials. | `.env.example` / `docs/BLOCKED_BY_EXTERNAL_DEPENDENCY.md` — no production banking credentials in workspace. | Hardened `functions/src/bankingEngine.ts` + contract/sandbox tests clearly labeled as Sandbox/Mock; never falsely marks notification-inferred transactions as `VERIFIED`. |
| `BLK-003` | Production Firebase Deployment & GitHub Release Push | Master Prompt Section 2 & 49 explicitly forbid pushing, tagging, or deploying to Production without explicit user authorization. | Prompt directive: *"Tuyệt đối không tự động push, force-push, deploy Production hoặc phát hành bản mới khi chưa có quyền rõ ràng."* | All rules, Cloud Functions, Web release, and APK artifacts are built and verified locally against the real Firebase Emulator and local build pipeline. |
