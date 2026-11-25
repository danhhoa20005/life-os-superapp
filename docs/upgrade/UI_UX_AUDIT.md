# UI / UX & DESIGN SYSTEM AUDIT — LIFE OS

## 1. Preserved Identity & Hard Test Invariants
- **Visual Identity:** Tammy × Apple emerald palette (`#0B7A2A` Light / `#19C23E` Dark), 3D Nano Banana glass icons (`32` core icons + `7` bank skins), clean Material 3 surfaces with restrained Liquid Glass on top/bottom chrome only.
- **Navigation Shell:** 5 bottom destinations (`Hôm nay | Tài chính | Lịch & Việc | Gia đình | Menu`) with `LiquidGlassSlidingDock` and center `+` Quick Action Hub.
- **Strict Guards Verified by Automated Tests:**
  - Zero `TextOverflow` usage anywhere in `lib/` (prevents clipped text; use `softWrap: true`, `Wrap`, `Expanded`, `FittedBox`).
  - Zero `.showSnackBar(` (always use `LifeOsTopToast`).
  - Zero 1-word-per-line vertical text stacking at `360×800 @ 112%` font scale across all routes.
  - Non-color-only status indicators (always pair semantic color with directional sign `+`/`-`, icon, and explicit label).
  - Respect OS Reduce Motion (`LifeOsMotionScope` / `TickerMode` disabled on offstage tabs).

## 2. Planned UX Upgrades
1. **Dashboard (`TodayPage` — Section 30):** Enforce clear 9-zone information hierarchy (Date & Greeting -> Financial Overview -> Safe-to-Spend Today -> 4 Quick Actions -> Smart Inbox Preview -> Today's Schedule -> Priority Tasks -> Attention Alerts -> Customizable Pinned Widgets).
2. **Global Command Palette (`Section 18`):** Upgrade `showLifeOsOmniSearchSheet` so users can both search 12 domains and execute quick commands (`Thêm giao dịch`, `Tạo lịch`, `Chia tiền`, `Mở quỹ gia đình`, `Tìm giao dịch tháng trước`) in 1–2 taps.
3. **Explicit Sync & Verification Badges (`Section 27, 36`):** Surface clear `Cục bộ / Chờ đồng bộ / Đang đồng bộ / Đã đồng bộ / Xung đột / Lỗi` and `Tạm ghi / Đã xác nhận / Đối soát NH / Đã từ chối / Đã đảo` states.
