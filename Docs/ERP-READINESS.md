# ERP Readiness — Hub Module Coverage

_Last updated: 2026-05-04_

This doc is a brutally honest module-coverage scorecard for `mercantis.hub.app`
as an ERP application. It is the companion to
[`HUB-ON-CORE-PROGRESS.md`](HUB-ON-CORE-PROGRESS.md), which tracks the
plumbing between Hub and Core; this doc tracks the **business surface area** —
what ERP modules have been built, what's left, and which Core / Hub blockers
gate each one.

For Core's side of the same conversation see
[`mercantis.core.app/Docs/ERP-READINESS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/ERP-READINESS.md).

---

## 1. Headline grade

**Hub is ~5% of a usable ERP.** The platform plumbing (Core dependency, install
pipeline, manifest, navigation shell, per-module folder convention) is in
place, and a single CRM DocType (Customer, three fields) round-trips through
`GenericFormView`. Every other ERP module — Selling, Buying, Stock,
Accounting, HR, Manufacturing, Projects, Assets — is **empty**: not just
unimplemented, but not declared either.

This is not a criticism of the work to date — it is the correct state for an
incremental, wall-driven adoption strategy (see HUB-ON-CORE-PROGRESS §"Known
walls ahead"). It does mean any timeline conversation about "Hub as an ERP"
needs to start from "we have built the runway, not the plane."

---

## 2. What's done

| Layer | State |
|---|---|
| Core dependency | ✅ `MercantisCore` + `MercantisCoreUI` resolved via Xcode SwiftPM |
| Install pipeline | ✅ Runs at `mercantis_hubApp.init()`; `apps` table has Hub row |
| Manifest scaffold | ✅ `HubManifest.build()` returns a real `AppManifest` (id `app.mercantis.hub`, version `0.1.0`) |
| Navigation shell | ✅ Module → menu group → menu item, driven by `HubNavigation.allModules` |
| Module folder convention | ✅ `Modules/<Name>/<Name>DocTypes.swift` + `<Name>Navigation.swift` |
| First DocType (Customer) | ✅ 3 fields (name, email, phone), `naming_series:CUST-.YYYY.-.####`, `lastWriteWins` |
| Form rendering | ✅ `UI/CustomerFormView.swift` uses Core's `GenericFormView` |
| Database | ✅ SQLite at `Application Support/MercantisHub/hub.sqlite`, migrations v1–v6 applied |
| Hub-side dashboards declaration | ⚠️ `Dashboards/HubDashboards.swift` declares dashboards but Core has no `DashboardView` to render them |

That is the entire shipped surface. `HubManifest.build()` passes empty arrays
for `workflows`, `permissions`, `reports`, `automationRules`, `dashboards`, and
`localizations`.

---

## 3. Module-coverage scorecard

Modules are listed in roughly the dependency order an ERP would need them.
"Core walls" reference the W4–W9 series in
[`HUB-ON-CORE-PROGRESS.md §"Known walls ahead"`](HUB-ON-CORE-PROGRESS.md).

Legend: ✅ shipped · 🟡 declared but incomplete · ❌ not started

### CRM — partial

| DocType | State | Notes |
|---|---|---|
| Customer | 🟡 | 3 fields only. Missing: address, tax id, currency, credit limit, payment terms, customer group, territory, default price list, default cost center. |
| Contact | ❌ | Needs Wall 4 (link fields) + Wall 5 (links child table) before it's worth modelling. |
| Address | ❌ | The whole point of Address is `linked_to: Customer/Supplier`. Hard-blocked on Wall 4. |
| Lead | ❌ | Flat for now; later needs Wall 6 (workflow). |
| Opportunity | ❌ | Needs Wall 4 (link to Lead/Customer) + Wall 6 (workflow). |

### Selling — not started

| DocType | State | Blocking walls |
|---|---|---|
| Item | ❌ | W4 (item_group link), W5 (UOMs / barcodes child tables), W8 (item group tree) |
| Item Group | ❌ | W8 (tree) |
| Price List | ❌ | W5 (price rows) |
| Quotation | ❌ | W4, W5, W6 |
| Sales Order | ❌ | W4, W5, W6 |
| Delivery Note | ❌ | W4, W5, W6, W7 (stock ledger entries) |
| Sales Invoice | ❌ | W4, W5, W6, W7 (GL entries) |

### Buying — not started

| DocType | State | Blocking walls |
|---|---|---|
| Supplier | ❌ | W4 (supplier_group), W5 (addresses) |
| Supplier Group | ❌ | W8 (tree) |
| Supplier Quotation | ❌ | W4, W5 |
| Purchase Order | ❌ | W4, W5, W6 |
| Purchase Receipt | ❌ | W4, W5, W6, W7 |
| Purchase Invoice | ❌ | W4, W5, W6, W7 |

### Stock — not started

| DocType | State | Blocking walls |
|---|---|---|
| Warehouse | ❌ | W8 (warehouse tree) |
| Stock Entry | ❌ | W4, W5, W6, W7 |
| Stock Ledger Entry | ❌ | W7 (derived ledger), append-only |
| Bin | ❌ | W7 (derived from Stock Ledger) |
| Stock Reconciliation | ❌ | W4, W5, W6, W7 |

### Accounting — not started

| DocType | State | Blocking walls |
|---|---|---|
| Account | ❌ | W8 (Chart of Accounts is a tree) |
| Cost Center | ❌ | W8 (tree) |
| Fiscal Year | ❌ | Flat — no walls, but pointless without other accounting DocTypes |
| Journal Entry | ❌ | W4, W5 (debit/credit rows), W6, W7 (GL entries) |
| Payment Entry | ❌ | W4, W5 (allocation rows), W6, W7 |
| GL Entry | ❌ | W7 (derived from Journal Entry, Sales Invoice, Purchase Invoice, Payment Entry) |

### HR — not started

| DocType | State | Blocking walls |
|---|---|---|
| Employee | ❌ | W4 (department, designation links), W5 (addresses) |
| Department | ❌ | W8 (tree) |
| Salary Structure | ❌ | W5 (component rows) |
| Payroll Entry | ❌ | W5, W6, W7 |
| Leave Application | ❌ | W4, W6 |
| Attendance | ❌ | W4 |

### Manufacturing — not started

| DocType | State | Blocking walls |
|---|---|---|
| BOM | ❌ | W4, W5 (item rows + operation rows), W6 |
| Work Order | ❌ | W4, W5, W6, W7 |
| Production Plan | ❌ | W4, W5, W6 |

### Projects — not started

| DocType | State | Blocking walls |
|---|---|---|
| Project | ❌ | W4 (customer link), W5 (task list), W6 |
| Task | ❌ | W4 (parent project), W6, W8 (sub-tasks) |
| Timesheet | ❌ | W4, W5, W6 |

### Assets — not started

| DocType | State | Blocking walls |
|---|---|---|
| Asset | ❌ | W4, W6, W7 (depreciation GL entries) |
| Asset Category | ❌ | Flat |
| Asset Maintenance | ❌ | W4, W5, W6 |

---

## 4. Cross-cutting Hub gaps

Beyond per-module DocTypes, the manifest itself currently passes empty arrays
for several cross-cutting concerns:

| Concern | State | Notes |
|---|---|---|
| Workflow definitions | ❌ | None declared. Every transactional DocType (Sales Invoice, PO, Stock Entry, Journal Entry) needs Draft → Submitted → Cancelled. Blocked on Wall 6. |
| Permission rules | ❌ | Manifest passes `permissions: []`. Roles like Accounts Manager, Sales User, Stock Manager, Purchase User need to be defined and bound to DocTypes. Not blocked on Core. |
| Reports | ❌ | None declared. Trial Balance, Customer Aging, Stock Ledger View, Sales Register all need Wall 9 (report engine + renderer). |
| Automation rules | ❌ | None declared. "On Sales Invoice submit, create GL entries" is the canonical use case — needs Wall 7. |
| Dashboards | 🟡 | `Dashboards/HubDashboards.swift` declares some, but Core has no `DashboardView` (Core gap §3.10 in Core's ERP-READINESS.md). |
| Localizations | ❌ | `localizations: []`. English-only today. |
| Multi-company | ❌ | `Document.company` is currently the constant `"Default Company"` (Wall 2 in HUB-ON-CORE-PROGRESS). |

---

## 5. Suggested implementation order

This expands HUB-ON-CORE-PROGRESS §"Module roadmap" with the practical
sequencing implied by the wall ordering. Each row assumes the prior rows
have landed.

### Phase 1 — Finish CRM and prove relational + child-table plumbing

1. **Wall 4 lands in Core (link fields).** Then Hub adds Address, Contact,
   and fleshes Customer out with `customer_group`, `territory`, `currency`,
   default price list, default cost center.
2. **Wall 5 lands in Core (child tables).** Then Hub adds Customer's
   `addresses` / `contacts` child tables, Item with UOM rows, Price List
   with item_price rows.
3. **Wall 8 lands in Core (tree DocTypes).** Slot here so Item Group,
   Customer Group, Territory, Department, Warehouse, Account, Cost Center
   are unblocked together.

### Phase 2 — Submittables: minimal Selling + Buying

4. **Wall 6 lands in Core (submittable + workflow).** Then Hub adds
   Quotation → Sales Order → Sales Invoice for Selling, and the symmetric
   Supplier Quotation → Purchase Order → Purchase Invoice for Buying. At
   this point Hub looks like an ERP for the first time.

### Phase 3 — Stock and Accounting backbones

5. **Wall 7 lands in Core (derived ledgers).** Then Hub adds Stock Entry,
   Delivery Note, Purchase Receipt → Stock Ledger Entry derivation; and
   Sales Invoice, Purchase Invoice, Payment Entry, Journal Entry → GL
   Entry derivation. This is where Hub becomes _useful_ for a real
   business.

### Phase 4 — Reports and dashboards

6. **Wall 9 lands in Core (report engine renderer).** Then Hub declares
   Sales Register, Customer Aging, Stock Ledger View, Trial Balance.
7. **Core ships `GenericDashboardView`.** Then Hub's `HubDashboards.swift`
   declarations actually render.

### Phase 5 — Production breadth

8. HR module (Employee, Leave Application, Attendance, Salary Structure,
   Payroll Entry).
9. Manufacturing (BOM, Work Order, Production Plan).
10. Projects (Project, Task, Timesheet).
11. Assets (Asset, Asset Category, Asset Maintenance).

---

## 6. What is _not_ Hub's responsibility

To keep this doc honest about scope, the following live in Core, not Hub:

- The submittable lifecycle, workflow engine, validation pipeline.
- The expression engine, naming strategies, sync / conflict resolution.
- Audit log writer, attachments, print/PDF, import/export.
- The metadata-driven form / list / dashboard / report renderers.

When Hub is "blocked" on a wall, the fix lands in Core. See
[`mercantis.core.app/Docs/ERP-READINESS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/ERP-READINESS.md)
for the corresponding Core-side gap list and suggested fix order.

---

## 7. Cross-references

- [`HUB-ON-CORE-PROGRESS.md`](HUB-ON-CORE-PROGRESS.md) — Hub's plumbing
  progress and the canonical wall (W4–W9) descriptions.
- Core-side: [`ERP-READINESS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/ERP-READINESS.md)
  — engine-level scorecard and fix order.
- Core-side: [`IMPLEMENTATION-STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/IMPLEMENTATION-STATUS.md)
  — full doc-vs-code reconciliation for Core.
- Core-side: [`ARCHITECTURE.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/ARCHITECTURE.md)
  — full Core architecture.
