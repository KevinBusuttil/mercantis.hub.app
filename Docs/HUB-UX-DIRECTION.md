# Neuradix Atlas — ERP UX Direction & Native macOS Product Strategy

_Last updated: 2026-05-04_

## 1. Purpose

Neuradix Atlas is the first-party ERP application built exclusively on Mercantis Core's public APIs. Its UX has two responsibilities:

1. Demonstrate Core's metadata-driven platform capabilities through real business workflows.
2. Deliver a polished, native macOS ERP experience that business users find productive and trustworthy.

Hub does not own the shell, forms, lists, or renderer infrastructure — those belong to Core. Hub owns the ERP domain model (DocTypes, workflows, permissions, reports, dashboards), the module/navigation composition, and any domain-specific presentation not appropriate for Core.

This document is documentation-first. It guides future UX implementation and should not be read as a request to rewrite the UI in one pass.

---

## 2. Current Hub UX State

| Component | Current state |
|---|---|
| `UI/RootView.swift` | `NavigationSplitView` with a sidebar driven by `HubNavigation.allModules`. Collapsible groups via a toggle button. Detail pane routes to `HubDocTypeView`, or shows placeholder text for reports and dashboards. |
| `Navigation/HubNavigation.swift` | Clean module/group/item model: `HubModule → HubMenuGroup → HubMenuItem`. Items can be `.docType`, `.report`, or `.dashboard`. |
| `UI/CustomerFormView.swift` / `HubDocTypeView` | Core's `GenericFormView` with a Save button. Resets to a blank document after save. No record list, no browse mode, no record count. |
| `Dashboards/HubDashboards.swift` | Stub namespace with `fatalError` stubs for sales, inventory, accounting, and HR dashboards. Core has no `DashboardView` to render them yet. |
| `Manifest/HubManifest.swift` | Builds an `AppManifest` with real DocTypes but empty arrays for workflows, permissions, reports, automationRules, and dashboards. |

`Docs/HUB-STATUS.md` is the authoritative source on Hub's ERP module coverage — it currently grades Hub at approximately 5% of a usable ERP.

The current UI is correct for the stage of the project. It proves Core integration, the install pipeline, the navigation model, and the round-trip save flow. It is not yet product-grade.

---

## 3. Hub UX Diagnosis

Hub's architecture is heading in the right direction. The module/group/item navigation model is clean and extensible. Core integration is working. The module folder convention (`Modules/<Name>/`) scales to many ERP modules.

The current weaknesses are:

- **`RootView` is scaffolding.** The sidebar and detail split is correct, but the shell has no product character, no landing page, and no onboarding affordance for an early-stage app.
- **Detail views are form-only.** Selecting a DocType goes straight to a blank new-record form. There is no list of existing records, no browse mode, no record count, no workspace summary.
- **Empty states are placeholder strings.** Reports and dashboards show `Text("... not yet implemented")`. First-time users receive no signal about what the app is building toward.
- **No workspace identity.** Nothing distinguishes a Customer workspace from a Supplier workspace. Every DocType produces the same visual.
- **Hub owns a shell it should not need to maintain long-term.** If Core eventually exposes a configurable shell API, `RootView` should shrink to a configuration call — not duplicate shell behavior that Core already provides through `NavigationShell`.

---

## 4. Recommended Hub UX Direction

### 4.1 Use Core shell as the long-term host shell

Hub's current `RootView` is a necessary interim shell. As Core matures, the right direction is to reduce Hub's shell code to a configuration call:

```swift
NavigationShell(
    configuration: ShellConfiguration(
        appTitle: "Neuradix Atlas",
        modules: HubNavigation.allModules,
        defaultWorkspace: .dashboard("hub.home"),
        branding: .init(
            symbol: "shippingbox",
            accentRole: .business
        )
    )
)
```

This is a **conceptual target API only**. Do not implement it until Core exposes a configurable `ShellConfiguration` surface. Hub should keep its current `RootView` stable until that API is available.

The goal of this direction is to avoid Hub maintaining a permanent fork of shell behavior. Every shell feature built into `RootView` becomes technical debt if Core later provides it correctly through `NavigationShell`.

### 4.2 Preserve and extend Hub's module-driven navigation model

Keep:

- `HubModule` — top-level module with id, label, system image, and groups
- `HubMenuGroup` — optional-label grouping of items within a module
- `HubMenuItem` — `.docType`, `.report`, `.dashboard` cases

Enhance incrementally:

| Enhancement | When to add |
|---|---|
| Module accent tone (badges, icon backgrounds) | When Core design tokens land (Core Phase UX-2) |
| Item badge counts (e.g. draft invoices pending) | When `DocumentEngine.list` filter and count support is solid |
| Group collapsed-state persistence | Near-term, small Hub-side addition to `RootView` |
| Per-module home dashboards | When Core ships `GenericDashboardView` (Core Phase UX-4) |

Do not apply module accent tones as saturated full-sidebar colors. Use them in badges, icon backgrounds, and dashboard accents only.

### 4.3 Create a professional ERP landing page

Hub's current default detail pane shows a `ContentUnavailableView` with "Select an item." An early-stage product can do better without misrepresenting completeness.

Recommended home screen sections:

| Section | Content |
|---|---|
| **Welcome / Header** | App name, version, and brief description |
| **Quick Actions** | Most common new-record actions (New Customer, New Sales Order, etc.) |
| **Recent Records** | Last-modified documents across active DocTypes |
| **Module Status** | Honest per-module state — what works now, what is blocked, what is coming |
| **Setup Progress** | Visible checklist if Company, Fiscal Year, or other setup DocTypes are present |

This landing page must be honest. Modules that are stubs should say so. Use `ContentUnavailableView`-style states that explain what each area will do and what Core capability unlocks it. Do not create fake metrics or populated dashboard tiles that contain no real data.

### 4.4 Improve ERP record screens

Once Core's `RecordCollectionHostView` is the workspace container for each DocType, each module workspace should provide:

- a workspace header (icon, title, subtitle, record count, primary action);
- a list/table view of existing records with sort and filter;
- a browse mode (list + detail preview side by side);
- a detail/edit view with grouped form sections and metadata;
- domain-specific status badges;
- save confirmation and inline error display;
- validation summary near save actions.

The current `HubDocTypeView` (a blank new-record form) is appropriate as a bootstrap but should evolve toward `RecordCollectionHostView` once that component's navigation integration supports Hub's routing model.

### 4.5 Use subtle domain colors

Hub's ERP modules naturally map to domain tones. These should be used sparingly — in badges, icon backgrounds, selected indicators, and dashboard accents only.

| Module | Suggested tone | Rationale |
|---|---|---|
| CRM | Blue | People, relationships |
| Selling | Green | Revenue, growth |
| Buying | Orange | Procurement, supply chain |
| Stock | Purple | Warehouse, inventory |
| Accounting | Indigo | Ledger, finance |
| HR | Teal | People operations |
| Manufacturing | Brown | Production |
| Projects | Yellow | Work tracking |
| Setup | Gray | Configuration, tools |

Do not apply these tones as full-screen backgrounds, fully colored sidebars, or heavy decorative gradients. Color-only status indication (without icon or label text) is prohibited by macOS accessibility guidelines.

### 4.6 Treat empty modules as onboarding, not blanks

Hub is early-stage and many module areas will be empty for the foreseeable future. Every empty report, dashboard, or module area should show a properly designed empty state that communicates:

- what this area will do when the module is implemented;
- what is available right now;
- what Core capability or implementation wall unlocks it (e.g. "Requires `GenericDashboardView` — Core Phase UX-4");
- what the suggested next action is.

Do not ship bare `Text("not yet implemented")` strings. `ContentUnavailableView` with a SF Symbol, title, and description is the native macOS pattern and is always better than a blank pane.

---

## 5. Hub UX Roadmap

### Phase HUX-1 — Documentation and shell alignment *(current)*

- Add this document.
- Cross-link from `HUB-STATUS.md`.
- Keep `RootView` stable; do not add domain colors or workspace headers yet.
- Cross-reference Core's UX direction.

### Phase HUX-2 — Better landing page and empty states

- Replace the default detail pane placeholder with an ERP home view.
- Add per-module honest-state cards: what each module contains now, what is coming.
- Add setup progress if Company / Fiscal Year setup DocTypes are declared.
- Replace all `Text("... not yet implemented")` placeholders with proper `ContentUnavailableView` empty states.

### Phase HUX-3 — Module navigation polish

- Add record count badges to sidebar items where `DocumentEngine.list` count support exists.
- Add group collapsed-state persistence to `RootView`.
- Introduce module accent tones once Core design tokens land (Core Phase UX-2).
- Add a Setup module with a proper onboarding checklist.

### Phase HUX-4 — Core shell adoption

- Once Core exposes a configurable `ShellConfiguration` API (Core UX Roadmap Phase UX-2 or later), refactor `RootView` to use it.
- Reduce Hub's shell maintenance surface to configuration and module composition.
- Preserve `HubNavigation.allModules` as the module data source.
- Remove any shell behavior duplicated from Core's `NavigationShell`.

### Phase HUX-5 — ERP workspace polish

- Adopt `RecordCollectionHostView` as the workspace container for key DocTypes.
- Add workspace hero headers to Customer, Supplier, Item, and other high-traffic DocTypes.
- Add CRM dashboard once Core ships `GenericDashboardView` (Core Phase UX-4).
- Add native list/detail browse mode for Customer and Item.
- Add richer grouped forms once Core Phase UX-3 lands.

---

## 6. Non-goals

- Do not build all ERP modules speculatively to make the sidebar appear full.
- Do not create fake production functionality (stub dashboards that claim to show real data).
- Do not fork Core UI components. If a component is missing, add it to Core's roadmap.
- Do not turn Hub into a web dashboard; the target is native macOS ERP.
- Do not maintain a permanent `RootView` shell that competes with Core's `NavigationShell`.
- Do not pre-declare DocTypes for modules that are blocked on unresolved Core walls — Hub adoption is incremental and wall-driven.

---

## Cross-references

- [`Docs/HUB-STATUS.md`](HUB-STATUS.md) — Hub implementation status, ERP module coverage, and known Core walls.
- [`Docs/HUB-COMMERCIAL-PACKAGING.md`](HUB-COMMERCIAL-PACKAGING.md) — Commercial packaging strategy, subscription tiers, business presets, and App Store design.
- Core UX direction: [`mercantis.core.app/Docs/UX-DIRECTION.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/UX-DIRECTION.md)
- Core implementation status: [`mercantis.core.app/Docs/STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/STATUS.md)
- Core architecture: [`mercantis.core.app/ARCHITECTURE.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/ARCHITECTURE.md)
