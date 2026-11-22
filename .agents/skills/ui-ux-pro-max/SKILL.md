---
name: ui-ux-pro-max
description: >-
  Flagship 2026 UI/UX Pro Max Design Intelligence System for Flutter, Web & Mobile Super Apps.
  Enforces Bento Grid layouts, Apple Wallet / Revolut fintech card craftsmanship, Liquid Glass
  navigation chrome, Tabular Numerals, CustomPainter data visualizations, tactile micro-depth,
  48dp touch ergonomics, and WCAG 2.2 AA contrast across Light & Dark modes.
---

# UI/UX Pro Max — Flagship Design Intelligence System

Activate and apply these rules whenever designing, building, or upgrading user interfaces to achieve **App Store Design Award / Linear / Revolut / Apple Wallet** visual quality.

---

## 1. Visual Hierarchy & Spatial Architecture

1. **Hero Focal Point Rule:** Every primary screen must have **one unmistakable focal point** above the fold (e.g. a deep mesh-gradient Net Worth / Space Summary Hero Card with translucent inner KPI pills and 1-tap primary actions).
2. **2×2 Bento Grid Over Stacked Lists:** Never stack 4+ uniform full-width summary rows vertically on mobile when a **2×2 Bento Grid** communicates status in half the vertical height and zero scrolling.
3. **3-Tier Surface Depth (Light & Dark):**
   - **Canvas (`background`):** Soft neutral tint (`#F2F4F7` Light / `#000000` True OLED Dark) so elevated white/charcoal cards pop naturally without heavy dark borders.
   - **Elevated Card (`surface`):** Crisp solid fill (`#FFFFFF` / `#1C1C1E`), `20px` corner radius, hairline border (`0.8px`), and ultra-soft ambient shadow (`blur: 20, offset: (0, 6), alpha: 0.04`).
   - **Floating Chrome (`LiquidGlass`):** Reserve `BackdropFilter(blur: 18)` strictly for top bars and floating bottom navigation docks — never blur dense text or financial tables.

---

## 2. Fintech & Data Visualization Precision

1. **Mandatory Tabular Numerals:** Every currency figure, percentage, odometer reading, and KPI metric MUST enable `FontFeature.tabularFigures()` so digits align vertically without jitter.
2. **Tactile Wallet Cards:** Render accounts/wallets as recognizable physical-digital cards with distinct material palettes per type (Emerald Mesh for Cash, Deep Cobalt-Slate for Bank, Obsidian Graphite-Gold for Credit Card), EMV chip motif, and clear `Estimated` vs `Verified` trust pill.
3. **Semantic Category Iconography:** Never use the same generic icon for every transaction row. Map domain categories (*Ăn uống*, *Việc nhà*, *Nhà cửa*, *Điện nước*, *Xe cộ*, *Mua sắm*, *Sức khỏe*, *Tiết kiệm*) to distinct squircle icon badges with harmonious tinted backgrounds.
4. **Zero-Dependency Native Charts (`CustomPainter`):** Prefer crisp, 60 FPS GPU-rendered `CustomPainter` Donut/Ring charts and diverging net-balance bars with center KPI readouts over raw text-only breakdowns.

---

## 3. Navigation, Controls & Ergonomics

1. **Pill Segmented Controls over Underline Tabs:** Style secondary `TabBar`s as modern sunken pill containers (`surfaceRaised`, `radius: 14`) with a solid or elevated active pill indicator (`dividerColor: Colors.transparent`, `TabBarIndicatorSize.tab`).
2. **Touch Target & Overflow Safety:**
   - Maintain `>= 44×44 pt` (`48dp` preferred) hit targets on all interactive controls.
   - Always set `isExpanded: true` on `DropdownButtonFormField` and use `Wrap` or `Expanded` for dynamic Vietnamese labels and VND amounts so zero `RenderFlex` overflows occur at any font scale.
3. **Accessible Status Communication (WCAG 2.2 AA):** Never rely on color alone — every status badge pairs a semantic icon with a concise Vietnamese label (`>= 4.5:1` contrast).
