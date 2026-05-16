# Hub — Product Strategy: ERPNext + Dynamics AX 2012 R3 for Micro/Small Business

_Last updated: 2026-05-05_

This document captures the strategic direction for Mercantis Hub: take
ERPNext's metadata-driven DocType architecture as the foundation, then
selectively import the subledger / posting / tax patterns from Dynamics
AX 2012 R3 that materially improve life for micro and small business
deployments — while deliberately skipping the AX features that exist to
serve enterprise complexity.

This is a **scoping and direction** document. The implementation lands
through [`POST-WALL-ROADMAP.md`](POST-WALL-ROADMAP.md); the per-DocType
state lives in [`HUB-STATUS.md`](HUB-STATUS.md). Commercial tier
positioning is sketched at the end and will be expanded in
`HUB-COMMERCIAL-PACKAGING.md` (not yet written).

---

## 1. Positioning

**Mercantis Hub is an offline-first, metadata-driven ERP for
businesses that have outgrown spreadsheets but are far below the budget
or operational scale of Dynamics 365 / SAP Business One / NetSuite.**

Concretely:

- 1–25 employees.
- One to a small number of legal entities.
- An external accountant who reviews books quarterly or annually.
- Operate at home, in a shop, on a vessel — wherever connectivity is
  unreliable. Offline correctness is the table-stakes feature.
- Need real VAT / Withholding Tax / customer-statement output for tax
  filing and chasing receivables; do *not* need multi-dimensional
  cost-centre allocation or 6-step approval workflows.

We are not building "ERPNext with a Mac UI." We are taking the
*architectural shape* of ERPNext (metadata + manifest + DocType +
GL Entry as source-of-truth) and selectively adopting AX patterns
where they make the daily life of a small-business operator or their
accountant materially simpler.

---

## 2. The architectural inheritance

### From ERPNext (already in place)

- **Metadata-driven DocTypes.** Every entity is a `DocType` with
  fields, validation rules, naming series, workflow. No hand-coded
  forms.
- **Submittable lifecycle.** Draft → Submitted → Cancelled, with
  `docStatus` as the gate and `allowOnSubmit` per field. Cancelled
  documents are not deleted; they sit in the table for audit.
- **Single GL Entry table.** All financial postings — receivables,
  payables, cash, inventory revaluation, depreciation — live in one
  `GLEntry` table. Reports walk that table.
- **Children inside parents.** Line items, debit/credit rows,
  allocations live as `Document.children`. Saved atomically.
- **Naming series.** `SINV-.YYYY.-.####` style series for human-
  readable IDs. Per-device block reservation (Phase B) makes them
  multi-device-safe.

### From Dynamics AX 2012 R3 (to import)

The four AX features that solve real problems ERPNext leaves rough:

| AX feature | What it solves | Hub adoption |
|---|---|---|
| **Subledger trans tables** (CustTrans / VendTrans / InventTrans / TaxTrans) | Drill-down reporting per subledger — customer statement, supplier ledger, stock movement, tax return — without joining 5 tables | Yes, with TransType enum |
| **Posting profiles** | One declaration maps `(customer_group, posting_type) → GL account` instead of `debit_to` / `income_account` per invoice | Yes, simple two-level (CustomerPostingProfile, SupplierPostingProfile) |
| **Settlement table** | Explicit "Payment X settled Invoice Y for amount Z" rows make customer-statement reports trivial | Yes; promote PaymentEntryReference to a first-class table |
| **TaxTrans + Withholding Tax** | Tax posting separated from invoice line; supports VAT, sales tax, and supplier-side WHT all from one shape | Yes, with VAT + WHT scope |

### From AX, deliberately skipped

| AX feature | Why we skip it |
|---|---|
| Financial Dimensions | Multi-dimensional cost analysis is overkill for 1–25 employee businesses. A single `cost_center` link per posting is enough. |
| Inventory cost layers (FIFO bucket per receipt) | Adds substantial complexity for marginal accuracy. Hub stays with weighted-average valuation. |
| Multi-level approval workflows | Wall 6's single-step workflows match the decision velocity of small businesses. |
| Sales Tax Hierarchy / Sales Tax Group | One `Tax` link per line is sufficient until proven otherwise. |
| Number sequences as separate DocType | `naming_series` (ERPNext) + Phase B block reservation already cover it. |
| AIF (Application Integration Framework) | The `CloudAdapter` protocol seam (ADR-018) is the equivalent and is appropriately scoped. |

---

## 3. The architectural moves

### 3.1 Subledger transaction tables

**New DocTypes** (all append-only, `isSubmittable: false`):

```
CustTrans (Customer subledger)
├── transType: enum { Invoice, Payment, CreditNote, Settlement,
│                     WriteOff, Adjustment, Interest, Fee }
├── customer: link → Customer
├── posting_date: date
├── due_date: date?
├── amount: currency (signed; positive = debit-the-customer)
├── currency: link → Currency
├── voucher_doctype: text
├── voucher_no: text
├── settled_amount: currency (running)
├── outstanding_amount: currency
└── is_reversal: bool

VendTrans (Supplier subledger) — symmetric

InventTrans (Inventory subledger) — supersedes StockLedgerEntry
├── transType: enum { Receipt, Issue, Transfer, Counting, Adjustment,
│                     Reservation, Production }
├── item, warehouse, qty_change, valuation_rate, amount, voucher_*, is_reversal

TaxTrans (Tax subledger)
├── tax: link → Tax
├── tax_type: enum { VAT, SalesTax, WHT }
├── posting_date: date
├── base_amount: currency  (taxable base)
├── tax_amount: currency
├── customer | supplier: link
├── voucher_*
└── is_reversal: bool
```

**Derivation** (`LedgerDerivationService`):

Every submit that today writes GL Entry rows also writes:

- **SalesInvoice submit** → CustTrans `Invoice` row + TaxTrans rows for
  each taxed line + existing GL rows.
- **PurchaseInvoice submit** → VendTrans `Invoice` row + TaxTrans rows
  + GL rows.
- **PaymentEntry submit** (receive from customer) → CustTrans `Payment`
  row + Settlement rows for each referenced invoice + GL rows.
- **PaymentEntry submit** (pay supplier) → VendTrans `Payment` row +
  WHT TaxTrans row if supplier has WHT + Settlement rows + GL rows.
- **StockEntry submit** → InventTrans rows (already InventTrans-shaped
  under the StockLedgerEntry name today; rename + add TransType).
- **JournalEntry submit** — same GL rows; no subledger rows unless the
  user explicitly tags a row with party/item.

The derivation rules expand naturally:

```
SalesInvoice submit:
  for each line in invoice.items:
    if line.tax:
      write TaxTrans(tax=line.tax, base=line.amount, tax_amount=line.amount * tax.rate, ...)
      write GL(Dr tax.account, Cr Income, ...)
    write GL(Cr Income, ...)  // already exists
  write CustTrans(transType=Invoice, customer=invoice.customer,
                  amount=invoice.grand_total, outstanding=invoice.grand_total, ...)
  write GL(Dr Receivable, ...)  // already exists
```

**Indices** for drill-down performance:

```
CustTrans: (customer), (voucher_no), (posting_date), (customer, outstanding_amount)
VendTrans: same shape
InventTrans: (item), (warehouse), (voucher_no), (posting_date)
TaxTrans: (tax), (posting_date), (voucher_no)
```

**Idempotency**: deterministic IDs the same way GL Entry rows already
work (`CT-<voucherId>-<leg>` etc.). Re-firing the derivation is a no-op.

### 3.2 Posting profiles

**New Setup DocTypes**:

```
CustomerPostingProfile
├── customer_group: link → CustomerGroup
├── receivable_account: link → Account
├── default_income_account: link → Account
└── default_tax_account: link → Account?

SupplierPostingProfile
├── supplier_group: link → SupplierGroup
├── payable_account: link → Account
├── default_expense_account: link → Account
├── default_wht_payable_account: link → Account?
└── default_tax_input_account: link → Account?
```

**Resolution** (in `LedgerDerivationService`):

1. Use the invoice's explicit fields if set (`SalesInvoice.debit_to` etc.) — covers one-off overrides.
2. Otherwise resolve `customer.customer_group → CustomerPostingProfile.receivable_account` etc.
3. Otherwise fall back to `HubSettings.default_*` (Phase 5.5).
4. Throw if still unresolved (with a "configure posting profile for customer group X" error message).

**SalesInvoice / PurchaseInvoice cleanup**:
- `debit_to` / `income_account` etc. become **optional override fields**
  instead of required.
- For most documents the user picks a Customer; the profile fills in
  the accounts; the form shows them read-only.

### 3.3 Settlement table

**New DocType** (replaces `PaymentEntryReference` as a free-standing
record):

```
Settlement
├── payment_voucher: link → PaymentEntry
├── invoice_voucher_doctype: text  (SalesInvoice | PurchaseInvoice | JournalEntry)
├── invoice_voucher_no: text
├── allocated_amount: currency
├── posting_date: date
└── is_reversal: bool
```

`PaymentEntry.references` child table stays as the UI input; on submit,
the LedgerDerivationService writes one Settlement row per reference
plus the CustTrans/VendTrans `Settlement` row that drives the invoice's
`outstanding_amount` recompute.

**Why this matters**: customer-statement reports become

```
SELECT * FROM cust_trans WHERE customer = ? ORDER BY posting_date;
-- with running outstanding from invoice rows minus settled rows
```

instead of joining PaymentEntry + PaymentEntryReference + SalesInvoice.

### 3.4 Tax + Withholding Tax

**New DocTypes**:

```
Tax (Setup)
├── tax_name: text  e.g. "VAT 18%"
├── tax_type: select [VAT, SalesTax, WHT, ExciseDuty]
├── rate: decimal  e.g. 18.0
├── account: link → Account  (where the tax posts)
├── reverse_charge: bool  (e.g. EU B2B services VAT)
└── jurisdiction: text  (free-form: "MT" / "EU" / "ZA-VAT")
```

**Field additions**:
- `SalesItem.tax: link → Tax?`
- `PurchaseItem.tax: link → Tax?`
- `Supplier.wht_applicable: bool` + `Supplier.wht_rate: decimal?` — for WHT-applicable suppliers (often consultants/freelancers).

**On submit**:
- `SalesInvoice` derives TaxTrans rows (one per taxed line) +
  GL rows (Cr Tax Output Account).
- `PurchaseInvoice` derives TaxTrans rows + GL rows (Dr Tax Input
  Account).
- `PaymentEntry (Pay)` to a WHT-applicable supplier additionally
  derives a TaxTrans `WHT` row and reduces the `paid_amount` posted
  to the bank by the WHT amount (so the bank-side debit = invoice
  total − WHT, and the WHT payable account is Cr'd).

**Reports unlocked**:
- **VAT Return** — sum of TaxTrans rows by `(tax_type=VAT, posting_date range)` grouped by tax.
- **WHT Certificate** — for any supplier, list every TaxTrans WHT row that supports a payment to them.

### 3.5 Three-way matching (optional follow-on)

**Not in the initial AX-import push**, but enabled by the above:

PurchaseInvoice gains optional links to `PurchaseOrder` + `PurchaseReceipt`. A submit-time validation rule walks the matched PO + Receipt and enforces:

```
sum(invoice.lines.qty * invoice.lines.rate)
  <= sum(receipt.lines.qty) * matched_PO.lines.rate
```

with a tolerance percentage in HubSettings. Catches double-billing.

Skipped from initial scope because (a) it requires Delivery Note / Purchase Receipt to land first (Phase 6.1), and (b) micro businesses without separate Receiving and AP staff don't need it on day one.

---

## 4. Revised roadmap (delta from `POST-WALL-ROADMAP.md`)

Insert these between the existing Phase 5 and Phase 6 items:

### 5.7 Subledger transaction tables

**Effort**: M (mostly DocType declarations + LedgerDerivationService extension)
**Depends on**: 5.1 Permissions, 5.2 Multi-company (Wall 2)
**Touches**:
- `Modules/Accounting/CustTrans.swift`, `Modules/Accounting/VendTrans.swift`
- `Modules/Stock/InventTrans.swift` (rename + augment `StockLedgerEntry` with TransType)
- `Modules/Accounting/TaxTrans.swift`
- `LedgerDerivation/LedgerDerivationService.swift` (extend each existing routine to write subledger rows alongside GL rows)
- `Reports/HubReports.swift` — Customer Statement, Supplier Ledger, Stock Movement, VAT Return reports drop in trivially against the new subledger tables.

**Acceptance**:
- Submitting any Sales Invoice writes one CustTrans `Invoice` row + GL rows.
- Submitting a Payment Entry against that invoice writes a CustTrans `Payment` + Settlement row, and the invoice's `outstanding_amount` decreases.
- A "Customer Statement" report renders for a chosen customer: every CustTrans row in date order with a running outstanding.
- Re-running the derivation is idempotent (deterministic IDs, fetch-first guard).

### 5.8 Posting profiles

**Effort**: M
**Depends on**: 5.7
**Touches**:
- `Modules/Setup/CustomerPostingProfile.swift`, `Modules/Setup/SupplierPostingProfile.swift`
- `LedgerDerivation/LedgerDerivationService.swift` (resolve order: explicit field → group profile → HubSettings)
- `SalesInvoice` / `PurchaseInvoice` — `debit_to` / `income_account` / etc. become **optional** fields (was: required)

**Acceptance**:
- Configuring a CustomerPostingProfile for the `Default` customer group means new Sales Invoices submit without the user setting `debit_to` or `income_account`.
- Setting an explicit `debit_to` on a specific invoice overrides the profile for that one document.
- An invoice with no resolvable profile + no override throws a clear "no posting profile configured" error on submit.

### 5.9 Tax + Withholding Tax

**Effort**: M (one new master + line-field additions + derivation extension)
**Depends on**: 5.7
**Touches**:
- `Modules/Setup/Tax.swift`
- `Modules/Selling/SellingDocTypes.swift` (SalesItem.tax)
- `Modules/Buying/BuyingDocTypes.swift` (PurchaseItem.tax + Supplier.wht_*)
- `LedgerDerivation/LedgerDerivationService.swift`
- `Reports/HubReports.swift` — add `VATReturn` and `WHTCertificate`

**Acceptance**:
- Sales Invoice with a line tagged "VAT 18%" writes Cr Income + Cr Tax Output + TaxTrans row on submit.
- Purchase Invoice with a tax tag writes Dr Expense + Dr Tax Input + TaxTrans row.
- Paying a WHT-applicable supplier writes Cr Bank (Invoice − WHT amount) + Cr WHT Payable + Dr Payable.
- "VAT Return" report for a date range sums TaxTrans rows grouped by tax.

### Re-sequencing recommendation

The new items slot between Phase 5.4 (Bin) and Phase 6.1 (Delivery Note):

1. 5.1 Permissions
2. 5.2 Multi-company
3. 5.3 ItemPrice lookup
4. 5.4 Bin
5. **5.7 Subledger transactions**
6. **5.8 Posting profiles**
7. **5.9 Tax + WHT**
8. 5.5 Settings DocType
9. 5.6 Localizations
10. 6.1 Delivery Note + Purchase Receipt
11. 7.1 Print formats (now with VAT lines)
12. … (remaining Phase 6 / Phase 7 items)

---

## 5. Commercial-packaging sketch

_This section is a placeholder. The detailed positioning belongs in
`Docs/HUB-COMMERCIAL-PACKAGING.md` once that doc is written. The tiers
sketched here exist only to inform the technical roadmap above._

A plausible three-tier structure given the technical scope:

### Mercantis Hub Core

- **Audience**: 1-person businesses, freelancers, side projects.
- **Functional scope**: Walls 4 + 5 + 6 + 7 + 9 (already shipped) + Phase 5.1 Permissions + 5.2 Multi-company + 5.3 ItemPrice + 5.4 Bin + 5.5 Settings + 5.6 Localizations.
- **What this gives**: CRM, basic Selling, basic Buying, basic Stock, basic Accounting (single GL Entry table), one company, single user, the four canonical reports + dashboards.

### Mercantis Hub Accounting Pro

- **Adds**: 5.7 Subledger transactions + 5.8 Posting profiles + 5.9 Tax/WHT + 6.1 Delivery Note + Purchase Receipt + 7.1 Print formats with VAT lines + the three-way match (Phase 6 follow-on).
- **Audience**: small businesses that file VAT returns and need supplier ledgers / customer statements / WHT certificates for tax authorities or external accountants.
- **What this gives**: production-grade financial output. The kind of thing an external accountant can sign off on without spreadsheet exports.

### Mercantis Hub Operations Plus

- **Adds**: HR (6.4) + Manufacturing (6.5) + Projects (6.6) + Assets (6.7) + 7.3 CloudKit multi-device + 7.4 Global search.
- **Audience**: 5-25 employee businesses with a single physical operation — workshops, services firms with multiple consultants, light manufacturing.
- **What this gives**: payroll, BOM-driven manufacturing, project billing, depreciation, multi-device sync.

The tier boundary that makes commercial sense is **between Core and Accounting Pro**: subledgers + tax + posting profiles are the features a paying customer (or their accountant) actually feels the value of. Core is what gets adoption; Accounting Pro is what justifies pricing.

The packaging doc when written should fill in:
- Pricing model (per-seat / per-company / per-device?).
- Activation mechanism (license file? in-app purchase via App Store?).
- Upgrade / downgrade paths (what happens to existing data when a customer drops a tier?).
- App Review compliance (no executable plugins per ADR-008, no external server per ADR-010 — these are already aligned).

---

## 6. Non-goals (reaffirmed)

To keep the synthesis honest, the deliberate non-goals from
`POST-WALL-ROADMAP.md` §"What's deliberately not on this list" all
stand:

- No multi-dimensional cost analysis (financial dimensions).
- No inventory cost layers — weighted-average only.
- No multi-level approvals — Wall 6 single-step workflows are enough.
- No server-side anything — ADR-010 stands; CloudAdapter is the only
  cross-device path.
- No mobile-first redesign — that's a separate UX track.
- No "auto-create journal entry for every business event" — automation
  rules are opt-in per the existing Phase B model.

The AX patterns we *are* importing are the ones that pay off for a
small business with a real accountant. Everything else from AX stays
on the enterprise side of the line.

---

## 7. What this changes about the project's identity

Mercantis Hub remains:

1. **Offline-first.** SQLite-backed, ADR-002 / ADR-010. The subledger
   tables are just more local tables.
2. **Declarative.** DocType-driven; the new subledger DocTypes are
   metadata, not hand-rolled code. The derivation rules live in one
   Hub-side service that's small, testable, and idempotent.
3. **Audit-clean.** Audit log (ADR-039) + workflow_transitions
   (ADR-038) + subledger reversal rows + GL reversal rows give an
   external accountant the trail they need.
4. **Micro-shaped.** Single user, single company, single currency by
   default. Multi-company + multi-tax-jurisdiction are *available* in
   the higher tier, not *required* for the base flow.

What changes: the product is no longer "we did ERPNext for the Mac."
It is "we picked the best parts of ERPNext + AX 2012 for businesses
that don't need enterprise plumbing but do need a working set of
books." That positioning is the answer when someone asks "why not
just use ERPNext or QuickBooks?" — the answer is **subledger
drill-down + WHT + offline-correctness + Mac-native UI, all in one
artifact**.
