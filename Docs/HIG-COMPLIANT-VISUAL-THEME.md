# Mercantis Hub — HIG-Compliant Visual Theme

> Visual direction for Mercantis Hub: a polished, native-macOS small-business
> ERP. This document explains how the "clean business dashboard" reference was
> translated into native macOS, which pieces live in Core UI vs. Hub, and the
> rules that keep the app HIG-compliant in light **and** dark mode.

---

## 1. Visual direction

Mercantis Hub should read as a **premium desktop ERP for micro / small
businesses**: calm, high-trust, scan-friendly, and dense enough to be
productive for data-entry users — but never cramped.

The reference imagery shows three surfaces (a dashboard, an ERP document
workspace, and a retail POS screen). We take the reference as **direction, not
a spec**:

- soft rounded cards, airy spacing, subtle blue/indigo accent
- clear KPI cards, polished tables, readable status badges
- right-side contextual (inspector) panels
- a professional POS grid

We explicitly **do not** copy it pixel-for-pixel, and we **do not** turn the app
into a web dashboard. macOS HIG wins whenever the reference conflicts with
native behaviour.

## 2. How the reference was translated into native macOS

| Reference idea | Native macOS translation |
|---|---|
| Left navigation sidebar | `NavigationSplitView` + `List(.sidebar)` with `MercantisSidebarRow` / module headers |
| Compact top toolbar | Native window toolbar (`ToolbarItem`) + `MercantisToolbarSearchField` |
| KPI cards | `MercantisMetricCard` (icon, value, optional delta + comparison) |
| Soft content cards | `MercantisCard` (hairline border, optional one-layer soft shadow) |
| Status badges | `MercantisStatusBadge` (text + SF Symbol + tonal fill) |
| Right contextual panel | `MercantisInspectorCard` / `MercantisInspectorRow`, ideally in a `.inspector` |
| Polished table | `Table` / `List` with right-aligned numerics, hover/selection tokens |
| POS product grid | `LazyVGrid` of `MercantisCard` tiles (`HubPOSView` shell) |
| Empty states | `MercantisEmptyState` (SF Symbol + title + one-line help + optional CTA) |

No fake browser/web chrome, no CSS-style layouts, no oversized marketing
buttons. SF Symbols carry iconography throughout.

## 3. Core UI primitives (live in `MercantisCoreUI`)

These are generic and reusable; Hub keeps the labels/data, Core owns the look.
Source: `mercantis core/UIShell/Components/` and `…/DesignTokens/`.

- **`MercantisCard`** — rounded business card; padding variants (`none`,
  `compact`, `standard`, `roomy`), optional brand tint, optional single soft
  shadow (`elevated`). Prefer the hairline border over shadows.
- **`MercantisMetricCard`** — KPI card. Title, monospaced value, optional delta
  chip (with directional arrow + tone), comparison caption, icon. Pure helpers
  `formatDeltaPercent(_:)` / `Trend(change:)` are unit-tested.
- **`MercantisPanelHeader`** — card/section title row with optional subtitle,
  icon, and a trailing control slot.
- **`MercantisInspectorCard` / `MercantisInspectorRow`** — right-side
  customer / supplier / summary cards; rows support right-aligned monospaced
  numerics.
- **`MercantisStatusBadge`** — business status badge (preserves the existing
  lifecycle / display-policy work; never colour-only).
- **`MercantisToolbarSearchField`** — compact, native-feeling search capsule
  with a focus ring and clear button.
- **`MercantisEmptyState`** — soft, useful empty state for dashboards / lists /
  reports.
- **Sidebar primitives** — `MercantisSidebarRow`, `MercantisSidebarModuleHeader`,
  `MercantisSidebarGroupHeader`, `MercantisSidebarBrandHeader`.

## 4. Hub-specific components

- **`HubDashboardView`** — composes Core primitives into the dashboard layout
  (KPI row from `count` widgets → card grid for list / chart / shortcut
  widgets). Stays data-driven via `DashboardEngine`; no hard-coded business
  numbers.
- **`HubPOSView`** — the POS **visual shell** (see §POS).
- Navigation (`HubNavigation` / module `*Navigation.swift`), list/report
  containers, and lifecycle/business-status wording remain Hub-owned.

## 5. Colour / token rules

Tokens live in `MercantisTheme`. **Every colour is adaptive** (light/dark) —
there is no light-only path.

- **Surfaces:** `appBackground`, `sidebarBackground`, `surfaceCard`,
  `surfaceElevated`, `surfaceMuted`. **Border:** `hairline` (calm) / `border`.
  **Shadow:** `cardShadow` (soft in light, suppressed in dark).
- **Brand:** `brandPrimary` (professional indigo) + `brandPrimaryHover/Pressed`,
  `brandPrimarySoft` (tinted fills), `brandPrimaryBorder`. Used for product
  identity and primary business highlights.
- **Status:** `success`, `warning`, `danger`, `info` — saturated only inside
  small badges/indicators, never across large surfaces.
- **Text:** `textPrimary`, `textSecondary` (= muted), `textTertiary`.
- **Tables:** `tableRowHover`, `tableRowSelection`, `tableHeaderBackground`.
- **KPI:** `kpiPositive`, `kpiNegative`, `kpiNeutral`.
- **System accent:** `Color.accentColor` is intentionally retained for native
  selection / focus tint, so the app still respects the user's macOS accent.
  Mercantis brand indigo is reserved for product identity & primary actions.

## 6. Dashboard layout rules

1. Compact header: page title + one-line subtitle + lightweight refresh.
2. **KPI row** at the top from `count` widgets, via `MercantisMetricCard`
   (adaptive grid, ~180–280pt cards).
3. **Card grid** below for list / chart / shortcut widgets, via `MercantisCard`
   + `MercantisPanelHeader` (~260–420pt cards).
4. List cards read like compact business tables: primary label left, value or
   **status badge** right; numerics right-aligned + monospaced; hairline row
   separators; max ~8 rows then defer to the full list.
5. No data → `MercantisEmptyState`, never a raw "no data" string or fake
   numbers. Sample values are allowed only in previews / explicit demo mode.

## 7. Document workspace layout rules

Reusable across Sales Invoice / Sales Order / Purchase Order / Purchase Invoice
/ Stock Entry / Payment Entry — built on the **generic** Core form
infrastructure (custom fields, child tables, link fields, and lifecycle actions
must keep working).

1. **Header:** document id/title, business `MercantisStatusBadge`, primary
   action, secondary actions, subtle metadata.
2. **Summary grid:** the few important fields up top in a compact two-column /
   responsive layout — avoid long unstructured forms for transactional docs.
3. **Sections:** tabbed/segmented (Details · Items & Pricing · Taxes ·
   Shipping · Terms · More Info) where appropriate.
4. **Items / child tables:** real ERP line tables — recognisable, clickable
   link fields; numeric columns right-aligned; totals aligned; compact but
   readable row density.
5. **Inspector** (right, collapsible via `.inspector`): `MercantisInspectorCard`
   stack — Details, Activity, Attachments, Customer/Supplier contact, Summary
   totals — shown only when linked data is available.

## 8. POS layout rules

`HubPOSView` is a **design-ready shell only** — it locks the layout/look using
Core primitives and is **not** wired to a POS engine.

Layout: category rail (left `List(.sidebar)`) · search/barcode field (top) ·
product grid (`MercantisCard` tiles, large enough for trackpad but
desktop-efficient) · cart panel + payment panel (right) with a prominent total
and a large primary **Complete Payment** action.

**Not yet implemented (do not ship a checkout on this):** real catalogue /
barcode lookup, pricing/tax/discount rules, tender + change + receipt, stock
decrement / Sales Invoice creation, offline session/shift handling. The cart
maths in the shell are display-only sums, not authoritative business logic.

## 9. Accessibility, light & dark mode

- Light mode reads close in spirit to the reference; dark mode stays polished
  and readable (borders carry elevation where shadows fade).
- Status uses **text + icon**, never colour alone.
- Focus rings preserved (native controls / `@FocusState`); selection visible in
  sidebar and tables.
- Buttons carry accessible labels/hints; cards combine children sensibly for
  VoiceOver.
- Financial / KPI values use **monospaced digits**; small secondary text stays
  at `textSecondary` (not fainter) so it doesn't disappear.
- System fonts only — no custom fonts.

## 10. Do / Don't

**Do**
- Use the native sidebar, toolbar, materials, SF Symbols, and `.inspector`.
- Use `MercantisCard` and calm business status colours.
- Right-align and monospace numbers; keep ERP rows compact.
- Use adaptive tokens for every colour.

**Don't**
- Copy web chrome or build fake nav/browser bars.
- Hard-code light-only colours or fake production business values.
- Make ERP rows tall or fields over-spaced.
- Overuse shadows, gradients, or translucency.
- Expose technical internals (audit ledgers, manufacturing) by default —
  preserve Advanced / Accountant visibility rules.
