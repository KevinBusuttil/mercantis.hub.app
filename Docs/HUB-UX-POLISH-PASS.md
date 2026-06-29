# Neuradix Atlas — UX / Product Polish Pass

_Last updated: 2026-05-30_

## 1. What changed

This pass reframes Neuradix Atlas's first-run experience from an engineering
preview into a business-ready workspace, without removing any working
functionality or the metadata-driven architecture. All changes are Hub-side;
Core was not modified.

| Area | File | Change |
|---|---|---|
| Local identity | `mercantis hub/mercantis_hubApp.swift` | Added `enum HubIdentity` that generates and persists a `"local-<uuid>"` user id (and the existing device id) in `UserDefaults`. Replaced the hard-coded `userId: "kevin"`. |
| Workflow identity | `mercantis hub/UI/RootView.swift` | Replaced the three remaining `userId: "kevin"` literals in the submit / cancel / workflow-transition paths with `HubIdentity.userId()`. |
| Home screen | `mercantis hub/UI/Home/HubHomeView.swift` | Full redesign (see §2). |
| Dashboard empty state | `mercantis hub/UI/Dashboards/HubDashboardView.swift` | Friendlier, action-oriented empty / error copy. |
| Report empty state | `mercantis hub/UI/Reports/HubReportContainerView.swift` | Friendlier, action-oriented empty / error copy. |
| Docs | `Docs/HUB-UX-POLISH-PASS.md` | This document. |

### Home screen, section by section

1. **Welcome / value proposition** — confident business language
   ("Run quotes, orders, invoices, stock, payments, and ledgers from a native,
   offline-first business workspace.") replaces the previous
   "many modules are still under construction" headline.
2. **Load sample business** — shown only when the database is empty (§4).
3. **Getting Started checklist** — replaces "Onboarding checklist coming soon".
   Rows are derived from DocTypes that actually exist, with statuses based on
   **real record counts** (`Ready` / `Needs setup`) or `Coming soon` for
   capabilities not in this build (Business profile, Fiscal Year, Tax — there
   are no `Company` / `FiscalYear` / `Tax` DocTypes yet). Each row has a title,
   short explanation, status, and an Open / Set up action where applicable.
4. **Quick Start** — business-flow actions grouped as Masters / Sell / Buy & Pay.
   Only actions whose DocType exists in `HubManifest` are shown.
5. **Business Snapshot** — real counts (Customers, Items, Open Invoices,
   Suppliers, Stock Entries, Payments). When everything is zero it shows
   guidance instead of a wall of `0`s. "Open Invoices" = submitted
   (`docStatus == 1`) and not `Paid`/`Cancelled` — computed from top-level
   `Document` fields only, so no figure is fabricated.
6. **Recent Activity** — unchanged behaviour, business-friendly wording.
7. **What You Can Do Today** — replaces "Module Status". Plain-language
   capabilities instead of internal implementation state.

## 2. Why the first-run experience changed

A user-perspective review found the foundation strong but the first 15 minutes
weak: the home screen read like a developer status board ("Module Status",
"coming soon", "under construction"), there was no onboarding, and empty data
produced bare zeros and raw error strings. The goal here was confidence and
clarity for a small-business user, while staying honest about what isn't
finished.

## 3. What remains intentionally incomplete

- **No Business profile / Fiscal Year / Tax DocTypes.** These appear in the
  checklist as `Coming soon`, not as configurable steps.
- **No account login.** Identity is a stable local id only; there is no sign-in,
  subscription, CloudKit, or multi-company work in this pass (by design).
- **Manufacturing, tax, and multi-company** are acknowledged as still being
  refined, in a deliberately secondary footnote on the home screen.
- **`HubDocumentEditor`** already existed (inline in `RootView.swift`, in the
  Xcode target) and was verified, not rewritten. It wraps Core's
  `GenericFormView` and contributes Save (via Core's host) plus
  Submit / Cancel / Amend, available workflow transitions, inline error
  messages, and a docStatus/status badge — all through `DocumentEngine` and
  `WorkflowEngine`. No behavioural change beyond the `userId` fix.

## 4. How demo / sample data works

- The **Load Sample Business** card appears only when the database looks empty
  (no `Customer` / `Supplier` / `Item` / `Warehouse` / `Account` records).
- Loading requires explicit confirmation, so a real database is never silently
  polluted.
- Records created: **2 customers, 2 suppliers**, supporting masters
  (`UOM` "Unit", `ItemGroup` "Sample Products", `Warehouse` "Main Store"),
  and **3 items**. Every record is tagged **"(Sample)"** and carries a
  "safe to delete" note.
- Saves go through `DocumentEngine.save` — **validation is not bypassed.** Each
  save is best-effort: if a record can't be created (e.g. a required link
  target is missing on a strict build) it is skipped and the result message
  reflects what was actually created.
- **Master data only.** Transactional documents (Quotation / Sales Order /
  Sales Invoice) are intentionally not generated: they are submittable and
  require posting accounts (`debit_to` / `income_account`) plus a configured
  Chart of Accounts that an empty database lacks. Creating them blindly would
  fail validation or post unsafe ledger entries.

## 5. Manual QA checklist

Build/run on macOS with Xcode (the project is an Xcode app target, not SPM):

1. **Clean build** — open `mercantis hub.xcodeproj`, Product → Clean Build
   Folder, then Build (⌘B). Or:
   `xcodebuild -project "mercantis hub.xcodeproj" -scheme "mercantis hub" build`
2. **Empty database** — delete
   `~/Library/Application Support/MercantisHub/hub.sqlite`, then launch.
3. Confirm the home screen reads as a product, not a dev preview (no
   "Module Status" / "under construction" headline).
4. Confirm checklist statuses reflect real data (all `Needs setup` / `Coming
   soon` on an empty DB).
5. Create a Customer, a Supplier, and an Item from Quick Start.
6. Return Home — confirm Recent Activity and Snapshot counts updated.
7. On an empty DB, tap **Load Sample Business…**, confirm, and verify the
   sample records appear and counts update.
8. Open the Selling, Buying, Stock, and Accounting workspaces from the sidebar.
9. Edit and **Save** a record — confirm it persists.
10. For a submittable DocType (e.g. Quotation), confirm **Submit** then
    **Cancel** work and the status badge updates.
11. Confirm the user id is no longer `"kevin"`: workflow-transition / audit
    rows are attributed to a `local-<uuid>` id (inspect `audit_log` /
    `workflow_transitions`, or `UserDefaults` key `MercantisHub.userId`).
