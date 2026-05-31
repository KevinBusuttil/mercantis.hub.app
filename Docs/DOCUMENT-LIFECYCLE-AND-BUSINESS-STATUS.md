# Mercantis Hub — Document Lifecycle & Business Status

_Last updated: 2026-05-31_

This document explains how Mercantis Hub separates **Core's internal document
lifecycle** (used for posting, audit, immutability and reversal) from the
**business-facing wording** a small-business user actually sees, and how the
internal AX-style transaction spine stays hidden until it's wanted.

> Guiding principle: keep Core's lifecycle discipline intact. We only change
> user-facing wording, action labels, status display, and navigation
> visibility — never the persisted state names, the posting pipeline, or the
> ledger derivation.

---

## 1. The three layers

| Layer | Stored in | Owner | Audience |
|-------|-----------|-------|----------|
| **Core lifecycle** | `Document.docStatus` (`0` Draft / `1` Submitted / `2` Cancelled) | Core | Internal — posting, audit, immutability, reversal |
| **Workflow / business status** | `Document.status` (string, e.g. `Submitted`, `Paid`, `Ordered`) | Hub workflows | User-facing operational state |
| **Display wording** | `HubWorkflowDisplayPolicy` (aliases only) | Hub | Pure presentation |

### 1a. Core lifecycle (`docStatus`)

`DocumentEngine.submit` / `cancel` / `amend` move a submittable document
through `0 → 1 → 2`. This drives immutability, the audit log, workflow-history
rows, and — critically — the `DocumentSubmittedEvent` /
`DocumentCancelledEvent` that `LedgerDerivationService` listens to. **None of
this changed.** The internal vocabulary is deliberately still
Draft / Submitted / Cancelled.

### 1b. Workflow / business status (`Document.status`)

`HubWorkflows` defines one workflow per transactional DocType. The string
states (`Draft`, `Submitted`, `Paid`, `Overdue`, `Ordered`, `InProgress`, …)
are **persisted** and unchanged — no migration is required.

### 1c. Display wording (aliases)

`HubWorkflowDisplayPolicy` is a pure data table mapping
`(docTypeId, state/action)` onto business labels, tones, confirmation copy and
help text. It is injected into Core's generic UI via the new
`DocumentDisplayPolicy` type. **It never renames a persisted value** — it only
changes what's drawn on screen.

---

## 2. Why internal `Submitted` is retained

`Submitted` (`docStatus == 1`) is the single hinge the entire posting/audit
spine pivots on:

- it locks the document (immutability),
- it emits the event that creates GL / CustTrans / VendTrans / Stock Ledger /
  Settlement / Tax rows,
- its reversal (`Cancelled`) emits the compensating event.

Renaming it would either break that contract or force a data migration. So we
keep `Submitted` internally and **alias it per document type** for display.

---

## 3. Why user-facing labels differ by document type

"Submit" means very different things to a user depending on the document. A
small business says *post an invoice*, *confirm an order*, *send a quote*,
*activate a BOM* — never "submit". The display policy gives each DocType its
own wording while the engine call underneath is always the same
`DocumentEngine.submit(...)`.

### Mapping reference

| DocType | `docStatus 1` shows | Submit action label | Cancel action label |
|---------|--------------------|---------------------|---------------------|
| Sales Invoice | **Posted** | Post Invoice | Cancel Invoice |
| Purchase Invoice | **Posted** | Post Bill | Cancel Bill |
| Payment Entry | **Posted** | Post Payment | Cancel Payment |
| Journal Entry | **Posted** | Post Journal | Reverse Journal |
| Stock Entry | **Posted** | Post Stock Movement | Reverse Stock Movement |
| Sales Order | **Confirmed** | Confirm Order | Cancel Order |
| Purchase Order | **Confirmed** | Confirm Order | Cancel Order |
| Quotation | **Sent** | Send Quote | Cancel Quote |
| Supplier Quotation | **Received** | Record Supplier Quote | Cancel |
| BOM | **Active** | Activate BOM | Cancel |
| Work Order | **Released** | Release Work Order | Cancel |
| Job Card | **Completed** | Complete Job | Cancel |
| Production Plan | **Planned** | Release Plan | Cancel |

Operational (business) statuses such as **Paid**, **Overdue**, **Accepted**,
**Lost**, **In Progress**, **Completed**, **Reconciled**, **Closed** are
separate from the lifecycle and shown as a second badge when they add
information beyond the lifecycle label.

### Status badge tones

Colour is **never** the only signal — the label text always shows, and each
badge carries a glyph. Tones (light/dark safe):

- Draft → muted
- Posted / Confirmed / Sent / Released / Received → brand or info
- Paid / Completed / Reconciled / Active / Accepted → success
- Overdue / Stopped → warning
- Cancelled / Lost / Reversed → danger
- Closed / Inactive → muted
- Unknown status → falls back to the raw string, tone-classified safely.

---

## 4. Posting and the AX-style transaction spine

Posting a document is what creates the internal accounting/audit rows. This is
a strength of Mercantis and is fully preserved:

| Internal table | Created from | Purpose |
|----------------|--------------|---------|
| **GL Entry** | posted invoices, payments, journals, stock | double-entry general ledger |
| **CustTrans** | posted sales invoices / customer payments | customer subledger → statements, aging |
| **VendTrans** | posted purchase invoices / supplier payments | supplier subledger → ledger, aging |
| **StockLedgerEntry** | posted stock movements | append-only stock history → balances |
| **Settlement** | payment ↔ invoice matching | open-item settlement |
| **TaxTrans** | posted documents with tax | tax reporting |

`LedgerDerivationService` (and `ManufacturingDerivationService`) derive these
from submit/cancel/transition events with **deterministic ids** so the
operation is replay-safe. Cancelling a posted document creates **reversal**
rows rather than deleting history.

User-facing copy explains this simply, e.g. on posting:
*"Posting this document locks most fields and automatically creates the
matching accounting and audit entries."* and on cancel: *"Cancelling this
posted document creates reversal entries. The original document and its audit
trail are retained."*

---

## 5. User-facing vs internal DocTypes

**User-facing (always visible):** Customer, Supplier, Contact, Address, Item,
Quotation, Sales Order, Sales Invoice, Supplier Quotation, Purchase Order,
Purchase Invoice, Stock Entry (Stock Movement), Payment Entry, Account, plus
the master-data in Setup (Currency, UOM, Brand, Warehouse, groups, Price List,
Cost Center) and the user-facing reports (Sales/Purchase Register, Customer
Aging, Customer Statement, Supplier Ledger, Stock Ledger View).

**Internal / accountant-facing (hidden by default):** GL Entry, CustTrans,
VendTrans, Settlement, Tax Transaction, Stock Ledger Entry, Journal Entry,
Trial Balance, and the whole Manufacturing module.

---

## 6. Advanced / Accountant visibility

There is no role system in this pass (Hub is offline-first, single-user), so
visibility is a local preference:

- `UserDefaults` key `MercantisHub.showAdvancedAccounting` (default **false**),
  wrapped by `HubVisibilitySettings`.
- Navigation items carry a `HubVisibility` (`.normal` / `.advanced`). Groups
  and whole modules can be tagged `.advanced`.
- The sidebar shows a **"Advanced / Accountant view"** toggle. When off, the
  internal ledger groups and Manufacturing are hidden; when on, they appear.

This keeps the everyday surface simple while leaving the full audit spine one
switch away for an accountant.

---

## 7. Rules for future DocTypes

1. **Master data is never submittable.** Customer, Supplier, Item, Contact,
   Address, Currency, UOM, Brand, Warehouse, the `*Group` types, Account,
   CostCenter, PriceList, Workstation, Operation must use only
   Active/Inactive, Enabled/Disabled, or Archived — **never** Draft/Submitted.
2. **Documents with ledger/stock/tax effects must be postable/cancellable**
   (`isSubmittable: true`) so the derivation spine fires.
3. **Business statuses stay separate from the audit lifecycle.** Add operational
   states on `Document.status`; never overload `docStatus`.
4. **Add display wording, don't rename states.** New DocTypes get an entry in
   `HubWorkflowDisplayPolicy` rather than new persisted state strings.

---

## 8. Where this lives in code

| Concern | File |
|---------|------|
| Generic policy types | `mercantis core/Metadata/DocumentDisplayPolicy.swift` (MercantisCore) |
| Badge tone bridge / badge | `mercantis core/UIShell/DesignTokens/MercantisTheme.swift` |
| List status labels/chips | `mercantis core/UIShell/GenericListView.swift` |
| Hub wording table | `mercantis hub/Workflows/HubWorkflowDisplayPolicy.swift` |
| Editor actions/badges/confirmations | `mercantis hub/UI/RootView.swift` (`HubDocumentEditor`) |
| Navigation visibility | `mercantis hub/Navigation/HubVisibility.swift` + module navigation files |
| Tests (generic engine) | `Tests/MercantisCoreUITests/DocumentDisplayPolicyTests.swift` |
