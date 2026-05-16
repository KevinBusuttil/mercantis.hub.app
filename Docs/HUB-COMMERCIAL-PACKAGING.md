# Hub — Commercial Packaging

_Last updated: 2026-05-05_

This is the planning artifact for how Mercantis Hub goes to market.
It maps the decision space — tiers, pricing model, activation,
distribution, support — and recommends a default path. Choices marked
**TBD** are explicit product-owner calls that haven't been made yet.

The technical scope this packaging applies to is in
[`HUB-PRODUCT-STRATEGY.md`](HUB-PRODUCT-STRATEGY.md); the per-DocType
state lives in [`HUB-STATUS.md`](HUB-STATUS.md); the implementation
order is in [`POST-WALL-ROADMAP.md`](POST-WALL-ROADMAP.md).

---

## 1. Positioning recap

Mercantis Hub targets **micro and small businesses** (1–25 employees)
that have outgrown spreadsheets but are below the budget / operational
scale of Dynamics 365 / SAP Business One / NetSuite. The product
identity per `HUB-PRODUCT-STRATEGY.md` §7:

> Subledger drill-down + WHT + offline-correctness + Mac-native UI,
> all in one artifact.

The packaging has to answer **why a small business pays for Hub
instead of using QuickBooks or ERPNext free**.

Honest answers:

- **vs ERPNext**: native macOS / iPadOS app, offline-first, no Python
  server to host, no docker, no learning curve for a non-IT operator.
- **vs QuickBooks**: real subledger drill-down + WHT support + stock
  + manufacturing reach + one-time-purchase tier (no perpetual
  subscription dependency), data stays on the user's device.
- **vs spreadsheets**: actual lifecycle (Submit / Cancel / Amend),
  actual audit log, real reports that an accountant can sign off on.

The Accounting Pro tier (subledgers + tax + posting profiles) is what
operationalises that positioning.

---

## 2. Tier structure

The technical strategy doc sketched three tiers. This section commits
to a default shape while leaving the boundary-line numbers open.

### Tier 1 — Mercantis Hub Core

**Audience**: 1-person businesses, freelancers, side projects, light-
usage shops with no external accountant.

**Functional scope** (everything currently shipped + cross-cutting
completeness, no subledger drill-down):

- CRM: Customer / Contact / Address / Lead (Walls 4 + 5 shipped).
- Selling: Item / Quotation / Sales Order / Sales Invoice
  (Walls 4 + 5 + 6 + 7 shipped).
- Buying: Supplier / Supplier Quotation / Purchase Order / Purchase
  Invoice.
- Stock: Warehouse / Stock Entry / Stock Ledger Entry / Bin
  (Phase 5.4).
- Accounting: Chart of Accounts / Journal Entry / Payment Entry / GL
  Entry (Wall 7 shipped).
- Setup: Currency / UOM / Brand / Cost Center / Customer Group /
  Supplier Group / Item Group / Territory / Warehouse / Price List /
  Item Price.
- Reports: Sales Register, Purchase Register, Stock Ledger View,
  Customer Aging, Trial Balance (Wall 9 shipped).
- Dashboards: Sales / Inventory / Accounting Overview (Wall 9 shipped).
- Permissions templates (Phase 5.1).
- Multi-company (Phase 5.2) — **one** company per install in this tier.
- ItemPrice lookup (Phase 5.3).
- Settings DocType (Phase 5.5).
- Localizations (Phase 5.6).

**Out of scope at this tier**: subledger drill-down, posting profiles,
explicit tax tables (still post Cr Tax via a generic "Tax Output"
account if the user wires it manually), HR, Manufacturing, Projects,
Assets, multi-device sync.

### Tier 2 — Mercantis Hub Accounting Pro

**Audience**: small businesses that file VAT returns, deal with an
external accountant, have a non-trivial supplier ledger.

**Adds**:

- Subledger transaction tables: CustTrans, VendTrans, InventTrans
  (rename + TransType enum), TaxTrans (Phase 5.7).
- Posting profiles: CustomerPostingProfile, SupplierPostingProfile
  (Phase 5.8).
- Tax + Withholding Tax: Tax DocType, line-level tax tagging, VAT
  Return + WHT Certificate reports (Phase 5.9).
- Delivery Note + Purchase Receipt (Phase 6.1).
- Print formats with VAT lines (Phase 7.1).
- Three-way matching (PO → Receipt → Invoice).
- Multi-company **unlimited** (a deployment can operate any number of
  legal entities from one install).
- Customer Statement / Supplier Ledger reports drop in for free off
  the new subledger tables.

**Audience signal**: this tier is what an external accountant looks
at and recognises as "a proper system."

### Tier 3 — Mercantis Hub Operations Plus

**Audience**: 5–25 employee businesses with multi-device workflows
(shop floor + office), payroll, project billing, or asset depreciation.

**Adds**:

- HR module (Department / Employee / Leave Application / Attendance /
  Salary Structure / Payroll Entry — Phase 6.4).
- Manufacturing module (BOM / Work Order / Production Plan —
  Phase 6.5).
- Projects module (Project / Task / Timesheet — Phase 6.6).
- Assets module (Asset / Asset Category / Asset Maintenance / monthly
  depreciation derivation — Phase 6.7).
- CloudKit-backed CloudAdapter (Phase 7.3) — multi-device sync via
  iCloud.
- Global search (Phase 7.4).
- Chart widgets in dashboards (Phase 7.5).

**Per-module pricing** is an option here — a customer who only needs
Manufacturing shouldn't have to pay for HR. **TBD**: tier-pack vs
per-module-pack.

### Why this boundary

The single biggest commercial-value boundary is between Core and
Accounting Pro. The features in the gap (subledgers + VAT + WHT +
posting profiles) are **invisible** to a freelancer using Hub as a
better spreadsheet, but they are the **first thing** an external
accountant asks for when a small business hands over its books.

That's the natural upsell moment: "when your accountant joins the
conversation, upgrade to Pro."

---

## 3. Pricing model

### Decisions framework

Three orthogonal axes:

| Axis | Options |
|---|---|
| **Charge basis** | Per-device, per-user, per-company, per-installation |
| **Cadence** | One-time, annual, monthly subscription |
| **Tier ladder** | Three-tier ladder, modular packs, mixed |

### Recommended default

**Per-installation, annual, three-tier ladder.**

- **Per-installation** rather than per-user keeps activation simple
  (no auth backend), respects ADR-010 (no server), and matches the
  typical 1–25 employee deployment shape (one device, occasional
  multi-device via CloudKit).
- **Annual** rather than one-time gives a sustainable revenue base
  for an OS-vendor-paced update cycle (every macOS / iOS major
  release requires a Hub release).
- **Three-tier** matches the technical scope split. Modular packs
  inside Tier 3 are optional.

### Indicative prices (TBD)

Three reference points to inform the actual numbers:

- **QuickBooks Online Simple Start**: ~$30/month/business = ~$360/yr.
- **ERPNext Cloud Hosted**: ~$10/month/user = $120-$300/yr for a small team.
- **One-time desktop accounting (e.g. AccountEdge)**: $250-$500 once.

Plausible Hub pricing:

| Tier | Annual (per-installation) | Justification |
|---|---|---|
| **Core** | **Free** *or* **€49/yr** | Free maximises adoption; €49 monetises hobby users. **TBD.** |
| **Accounting Pro** | **€199/yr** | Below QuickBooks; above ERPNext free; matches the "accountant joined the conversation" upgrade. |
| **Operations Plus** | **€399/yr** *or* **€199 + €99/module** | Single-tier price is simpler; per-module respects asymmetric customer needs. **TBD.** |

### Free-tier consideration

The most consequential **TBD**:

**Option A** — Core is free, Pro / Plus are paid. Pros: maximises
adoption, gives accountants a way to recommend Hub before customers
pay. Cons: monetisation depends entirely on conversion, support load
for free users.

**Option B** — Core is paid (€49–€99), Pro / Plus are higher tiers.
Pros: every user pays something; lower support volume; clearer signal
that Hub is a commercial product. Cons: harder organic growth, App
Store discovery suffers.

**Option C** — Hybrid: Core is free for ≤ 100 documents / month, paid
above. The freemium SaaS pattern adapted to a per-installation app.
Pros: free trial built in; conversion pressure built in. Cons: feels
gating; document-count limit is hard to explain.

**Recommended default**: Option A (Core free) for the first 12 months
to prove adoption, then revisit if conversion is below 2–3%.

### Activation mechanism

| Mechanism | Pros | Cons |
|---|---|---|
| **Mac App Store IAP** | Built-in payment, App Store discovery, no piracy risk worth worrying about | Apple takes 15–30%, App Store Review can block updates, restricts distribution to App Store-using customers |
| **Direct download + license key** | Higher margin (no Apple cut), free to update on our schedule, can sell through resellers | Need a license-key generator and validator (small but non-zero infra), no App Store discovery |
| **Both** | Discovery + margin headroom | Two activation paths to maintain |

**Recommended default**: Mac App Store for Core (free) and the entry-
price Pro tier (lower margin matters less); direct license for the
higher-margin Operations Plus tier where the App Store cut is more
painful.

ADR-008 (no executable plugins) + ADR-010 (no server) already align
with App Store sandboxing. No structural blockers.

---

## 4. Distribution

### Channels

| Channel | Audience | Status |
|---|---|---|
| **Mac App Store** | Mac-using small businesses, organic discovery via App Store search | Default channel, **TBD** for activation |
| **Direct download (mercantis.app)** | Customers who want to bypass App Store, accountants reselling | Required for license-key path |
| **Accountant resellers** | Bookkeepers who recommend Hub to their micro-business clients | Long-tail growth channel; **TBD** for reseller pricing |
| **Localized resellers** (Malta-first?) | Country-specific distribution where local VAT/WHT compliance is the key value | **TBD**; depends on whether we ship per-jurisdiction tax DocType packs |

### Jurisdiction packs

VAT / WHT rates differ per jurisdiction. The technical strategy
already supports this via the `Tax.jurisdiction` field. The packaging
question:

- **Single SKU**, tax rates are configured by each customer. Simplest.
- **Per-jurisdiction SKU** (e.g. "Hub MT", "Hub IT", "Hub UK") that
  ships pre-configured tax rates + standard chart of accounts +
  localized strings. Higher value, harder to maintain.

**Recommended default**: single SKU + a "Malta starter pack" (or
whichever first market) shipped as an opt-in setup wizard that imports
a Tax catalog + standard CoA + localized strings on first run. Same
binary; jurisdiction-specific *data*.

---

## 5. Trial / evaluation

- **Mac App Store**: Core is free → in-app upgrade to Pro / Plus. No
  separate trial mechanism needed.
- **Direct download**: 30-day full-feature trial after which Pro / Plus
  features lock back to Core. Document deletion is **not** part of the
  trial expiry — the data the customer entered stays accessible at the
  Core tier even after Pro features lock.

The lock-down has to be designed carefully. A submitted Sales Invoice
on Pro has subledger rows + WHT rows; after lock-down the user should
still be able to *view* those rows (audit trail integrity per ADR-039)
but not *create* new ones at the Core tier. The simplest implementation:
the LedgerDerivationService skips the subledger / tax routines when
the active tier is Core.

---

## 6. Upgrade / downgrade paths

| Move | What happens |
|---|---|
| **Core → Pro** | Subledger derivation routines start firing on new submits. Historical Core-era invoices have no CustTrans / VendTrans / TaxTrans rows — that's OK; subledger reports begin from the upgrade date. **Optionally** offer a "backfill subledgers" maintenance action that walks every submitted invoice and runs derivation idempotently. |
| **Pro → Operations Plus** | HR / Manufacturing / Projects / Assets modules unlock; navigation gains the new sidebar entries; no schema migration needed because the DocTypes were always declared but the modules were gated. |
| **Operations Plus → Pro** | HR / Manufacturing / Projects / Assets modules lock; existing documents stay viewable in a read-only mode; nothing is deleted. Same audit-trail-integrity principle. |
| **Pro → Core** | Subledger / tax features lock. Historical CustTrans / VendTrans / TaxTrans rows stay queryable for audit; no new ones get written. Customer Statement / Supplier Ledger / VAT Return reports stay accessible read-only. |

**Principle**: a downgrade never destroys data. The lower tier hides
capability but preserves the trail. This matches how the Adobe / Sketch
ecosystem handles license lapse — your old files open, you just can't
edit with the pro features.

---

## 7. Support model

### Self-service

- In-app **Help** menu → opens this Docs/ folder shipped with the app
  binary (no internet required for documentation).
- Each empty-state (`ContentUnavailableView`) carries a one-line "what
  this is" plus a deeper link into Help.
- **TBD**: a knowledge-base site (mercantis.app/docs) for SEO + linkable
  customer-support answers.

### Direct support

| Tier | Support shape |
|---|---|
| Core | Community (GitHub Discussions / forum) only |
| Accounting Pro | Email support, response within 2 business days |
| Operations Plus | Email support within 1 business day + scheduled monthly office-hours call |

**TBD**: do we offer onboarding services (paid consulting for chart-of-
accounts setup, jurisdiction tax configuration, payroll structure) as
an add-on?

---

## 8. Compliance + legal

### App Store Review

- ADR-008 (no downloaded executable plugins) means we pass the
  no-arbitrary-code-execution check.
- ADR-010 (no server component) means no "where does the data go" anxiety
  during Review.
- ADR-018 (CloudAdapter as protocol boundary) means CloudKit sync uses
  Apple's own framework — no third-party cloud SDKs in the binary.

These are existing decisions that happen to align cleanly with App
Store requirements. No retrofit needed.

### Data protection (GDPR, etc.)

- Hub data lives on the customer's device.
- CloudKit sync, when enabled, stores in the customer's own iCloud
  Private Database — not on a Mercantis-owned server.
- Mercantis as a vendor sees no customer data unless the customer
  voluntarily submits a support transcript.

This is the cleanest GDPR posture available: we are not a Data
Controller or Processor for customer business data.

### Accounting / audit certifications

Some jurisdictions (Malta, Italy, etc.) certify accounting software
for use in regulated tax filings. Whether to pursue certification per-
jurisdiction is **TBD**; it's a per-market investment that may be worth
it for jurisdictions where the certification doubles as marketing
("the only certified accounting app on Mac for Maltese VAT").

---

## 9. Update cadence

- **Quarterly minor releases** (new DocTypes, new reports, polish).
- **Annual major releases** aligned to macOS / iOS major version (Hub
  major versions track Apple's, e.g. Hub 26 ships against macOS 26).
- **Patch releases** as needed for bugs and tax-rate updates that
  matter to operating customers.

Annual subscription customers receive every release for the term.
One-time-purchase customers (if we ever sell that way) receive minor +
patch releases for the major version they bought; major upgrades are a
separate purchase. **TBD**: do we sell one-time at all, or annual-only?

---

## 10. Decision checklist

When the time comes to finalise packaging, these are the calls in
order of urgency:

1. **Free vs paid Core tier.** Most consequential single decision.
2. **Annual vs one-time** at each tier.
3. **App Store vs direct download** distribution mix.
4. **Tier 3 single-price vs modular** packs.
5. **Per-jurisdiction starter packs** (Malta-first, then?).
6. **Onboarding services** as a paid add-on.
7. **Accounting certification** per-jurisdiction.
8. **Pricing levels** — the actual numbers in §3.

Items 1, 2, and 3 are the path-defining choices. Items 4–8 can be
deferred until adoption signal arrives.

---

## 11. Open questions for the product owner

These don't have a default — they need a decision:

- Are we targeting Malta first, or a broader EU / English-speaking
  market from day one?
- Do we sell directly through accountants who advise small businesses,
  or do we go customer-direct via App Store?
- Is "Mercantis Hub" the user-facing product name, or do we want a
  cleaner consumer-friendly name for Core (e.g. "Mercantis Books") and
  reserve "Hub" for the Pro / Plus tiers?
- Do we accept the App Store 15-30% cut on Core if we make it free,
  on the theory that App Store discovery is the cheapest acquisition
  channel?
- Is there an existing accountant network we'd partner with (Maltese
  bookkeeper association, etc.) for early reseller relationships?

Pin answers to these before the first paid release.
