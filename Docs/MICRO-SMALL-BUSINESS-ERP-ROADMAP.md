# Neuradix Atlas — Micro/Small-Business ERP Roadmap

## Product direction

Neuradix Atlas is not intended to be an ERPNext clone or a simplified enterprise ERP.

It should be:
- simple for micro/small-business users;
- operationally focused;
- native macOS;
- clear and friendly in navigation;
- serious internally, with audit-grade ledgers;
- powered by AX-style transaction concepts internally;
- not overloaded with enterprise complexity by default.

## Product principle

User-facing model:

- Contacts
- Sell
- Buy
- Stock
- POS
- Deliveries
- Money
- Reports
- Setup

Internal/audit model:

- GL Entry
- Customer Transactions
- Supplier Transactions
- Stock Ledger Entries
- Settlements
- Tax Transactions
- Reversal entries
- Audit trails

Rule:
Normal users should work with documents, payments, POS, deliveries, and reports.
Accountants/admins can access the internal transaction spine through Advanced / Accountant mode.

## Default modules

Normal mode:

- Home
- Contacts
  - Customers
  - Suppliers
  - Contacts
  - Addresses
  - Leads
- Sell
  - Quotes
  - Sales Orders
  - Sales Invoices
  - Receive Payment
- Buy
  - Purchase Orders
  - Purchase Receipts
  - Bills
  - Pay Supplier
- Stock
  - Items
  - Warehouses
  - Stock Movements
  - Stock Balance
- POS
  - POS Terminal
  - POS Sessions
  - POS Receipts / Sales
- Deliveries
  - Sales Deliveries
  - Delivery Routes
  - Vehicles
  - Drivers
- Money
  - Payments
  - Customer Balances
  - Supplier Balances
  - Bank / Cash
  - Chart of Accounts
- Reports
  - Sales
  - Purchases
  - Stock
  - Deliveries
  - VAT
  - Profit &amp; Loss
- Setup
  - Business Profile
  - Fiscal Year
  - Numbering
  - Taxes
  - Defaults
  - Configuration masters

Advanced / Accountant mode:

- Journal Entry
- GL Entry
- Customer Transactions
- Supplier Transactions
- Settlement
- TaxTrans
- Stock Ledger Entry
- Trial Balance
- Manufacturing

## Implementation phases

### Phase 1 — Business Setup Foundation

Purpose:
Create the base company/accounting configuration needed before real transactions, POS, VAT, and delivery flows can work.

Scope:
- Business Profile / Company
- Fiscal Year / Accounting Period
- Numbering Settings
- Default Accounts
- Default Warehouse
- Default Currency

Acceptance criteria:
- User can create/edit one Business Profile.
- Business Profile stores business name, VAT/tax number, registration number, address, email, phone, logo placeholder.
- User can set default currency and fiscal year.
- User can configure numbering series for invoices, bills, deliveries, POS receipts.
- User can select default receivable, payable, income, expense, cash/bank, stock, and VAT accounts.
- Sales/Purchase documents can eventually use defaults instead of forcing posting accounts every time.

Out of scope:
- Multi-company
- Complex accounting period locking
- Full localization engine

### Phase 2 — VAT / Tax Foundation

Purpose:
Make sales, purchases, and POS tax-aware.

Scope:
- Tax Code
- Tax Rate
- Tax Category
- Invoice tax rows
- Tax calculation service
- VAT Summary Report
- TaxTrans derivation

Acceptance criteria:
- User can create VAT codes: Standard, Reduced, Zero, Exempt.
- Item/customer/supplier can have tax defaults.
- Sales Invoice and Purchase Invoice can calculate tax rows.
- VAT amount is included in totals.
- TaxTrans rows are derived on submit/cancel.
- VAT Summary Report exists.
- POS can reuse the same tax engine later.

Out of scope:
- Full EU localization engine
- Intrastat
- Complex reverse charge handling unless explicitly added later

### Phase 3 — Stock Balance / Inventory Availability

Purpose:
Give users a simple stock-on-hand view instead of requiring them to inspect ledger rows.

Scope:
- Stock Balance / Bin
- Stock on Hand report
- Item + warehouse quantity lookup
- Stock value summary

Acceptance criteria:
- Stock Balance shows item, warehouse, actual quantity, stock value, and last movement date.
- Stock Balance derives from StockLedgerEntry.
- Stock Movement submit/cancel updates or recomputes balances.
- Item workspace can show current stock.
- POS and Deliveries can query available stock.

Out of scope:
- Complex reservation engine
- Serial/batch stock
- Forecasting

### Phase 4 — Purchase Receipt and Sales Delivery

Purpose:
Add physical fulfilment documents so stock and deliveries can be tracked separately from financial invoices.

Scope:
- Purchase Receipt
- Purchase Receipt Item
- Sales Delivery / Delivery Note
- Sales Delivery Item

Acceptance criteria:
- Purchase Order can create Purchase Receipt.
- Purchase Receipt can update stock.
- Sales Order or Sales Invoice can create Sales Delivery.
- Sales Delivery supports statuses: Draft, Scheduled, Loaded, Out for Delivery, Delivered, Failed, Cancelled.
- User can see undelivered sales.
- Delivery document becomes the foundation for routes.

Out of scope:
- Route optimisation
- Proof of delivery photos/signatures
- Complex partial shipment logic beyond simple delivered quantities

### Phase 5 — Guided Payments

Purpose:
Make Receive Payment / Pay Supplier usable for normal users without exposing technical allocation fields.

Scope:
- Guided Receive Payment flow
- Guided Pay Supplier flow
- Outstanding invoice/bill selector
- Allocation helper
- Underlying Payment Entry creation

Acceptance criteria:
- Receive Payment opens a customer-focused flow.
- Pay Supplier opens a supplier-focused flow.
- User selects customer/supplier from a proper picker.
- Outstanding invoices/bills are shown.
- User ticks invoices/bills to allocate.
- Allocated amount is auto-filled.
- Payment Entry is created underneath.
- GL, CustTrans/VendTrans, and Settlement behaviour remains intact.

Out of scope:
- Bank reconciliation
- Payment gateway integration
- Complex multi-currency settlement

### Phase 6 — POS v1

Purpose:
Turn the current POS visual shell into a real, usable POS for small retail businesses.

Scope:
- POS Profile
- POS Session
- POS Sale / POS Invoice
- POS Sale Item
- Payment Tender
- Item search / barcode input
- Pricing lookup
- VAT calculation
- Payment capture
- Stock decrement
- Receipt placeholder

Acceptance criteria:
- POS appears only when Retail/POS preset is enabled.
- User can open a POS Session.
- User can search/scan real Item records.
- POS uses item price / price list.
- POS calculates VAT through the shared tax engine.
- User can take cash/card/manual payment.
- Completing sale creates posted POS Sale or Sales Invoice.
- Payment is recorded.
- Stock is decremented.
- Receipt print/email placeholder exists.
- No demo data is used in production.

Out of scope for v1:
- Returns
- Loyalty
- Gift cards
- Hardware printer integration
- Cash drawer integration
- Complex discounts/promotions
- Offline sync conflict resolution beyond existing Core behaviour

### Phase 7 — Delivery Routes and Tracking

Purpose:
Support businesses that deliver goods to customers and need route assignment/tracking.

Scope:
- Driver
- Vehicle
- Delivery Route
- Delivery Route Stop
- Delivery Status Event

Acceptance criteria:
- User can create a Delivery Route for a date.
- User can assign driver and vehicle.
- User can add Sales Deliveries as route stops.
- User can manually sequence stops.
- Stop statuses include Pending, Loaded, Out for Delivery, Delivered, Failed, Rescheduled.
- Delivery Route dashboard shows today’s routes.
- Sales Delivery shows linked route and current delivery status.
- Proof of delivery placeholder exists.

Out of scope for v1:
- Route optimisation
- Map provider integration
- GPS live tracking
- Mobile driver app
- Signature/photo proof of delivery

### Phase 8 — Presets and Onboarding

Purpose:
Avoid overwhelming users by showing only the modules relevant to their business type.

Scope:
- Services preset
- Trade / Distribution preset
- Retail / POS preset
- Light Manufacturing preset
- First-run setup wizard
- Module visibility by preset

Acceptance criteria:
- First-run wizard asks business type.
- Preset controls visible modules.
- Manufacturing remains hidden unless Light Manufacturing is enabled.
- POS hidden unless Retail/POS is enabled.
- Deliveries hidden unless Trade/Distribution or enabled manually.
- Setup wizard creates initial currency, fiscal year, warehouse, default accounts.
- Presets can be changed later.

Out of scope:
- Full role-based security UI
- Industry-specific localizations

## Implementation rules

- One epic may have multiple PRs.
- One PR should have one clear outcome.
- No feature PR should modify Core unless the change is genuinely reusable.
- Hub-specific ERP rules belong in Hub.
- Core should remain generic.
- Do not rename existing DocType ids unless explicitly approved.
- Preserve document lifecycle and ledger derivation.
- Preserve Advanced / Accountant visibility.
- No hard-coded fake production data.
- Use tests and manual QA checklists for every feature PR.
- Every AI coding session must read this roadmap and the implementation tracker before coding.
