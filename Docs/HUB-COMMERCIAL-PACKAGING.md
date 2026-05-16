# Mercantis Hub — Commercial Packaging Strategy

_Last updated: 2026-05-16_

---

## 1. Purpose

This document defines how Mercantis Hub should be commercially packaged, priced, and positioned for micro and small businesses.

It covers the subscription-tier model, App Store strategy, business preset system, and the design rules that govern how capability is bundled and sold.

**This is a product and commercial strategy document. It is not an immediate implementation task.** It exists to align future App Store setup, marketing, onboarding design, and Hub feature gating with a coherent commercial model before those decisions are made inconsistently across the codebase or storefront.

---

## 2. Product Family Model

Mercantis Hub is the first-party ERP/business application built on Mercantis Core. Core owns the reusable platform runtime: the metadata engine, document engine, workflow engine, generic UI, sync, permissions, reporting foundation, and related infrastructure. Hub owns the ERP/business domain model, DocTypes, workflows, reports, dashboards, navigation composition, and the business-specific product experience.

| Layer | Meaning |
|---|---|
| Product | Mercantis Hub |
| App Store app | One app called **Mercantis Hub** |
| Subscription group | **Mercantis Hub Plans** |
| Subscription tier | Essential / Stock / Trade / Complete |
| Business preset | Retail / Distribution / Warehouse / Service / Finance / Light Manufacturing |
| Module | Internal functional area such as CRM, Selling, Buying, Stock, Accounting |
| Core | Technical runtime/platform (Mercantis Core) |

### Product family overview

- **Product family:** Mercantis Hub
- **App Store app:** Mercantis Hub (one app)
- **Internal platform:** Mercantis Core
- **Business presets:** Retail, Distribution, Warehouse, Service, Light Manufacturing, Finance
- **Capability tiers:** Essential, Stock, Trade, Complete
- **Future specialist capabilities:** Manufacturing, Field Sales, Multi-Company, Advanced Reports

Tier and preset are orthogonal. A customer chooses a tier (what depth of capability they need) and a preset (how the app is configured for their type of business). They are not the same thing and must not be conflated in App Store design.

---

## 3. One App, Multiple Configurations

Mercantis Hub must be distributed as **one App Store app**, not a collection of separate apps.

The following would be the wrong model:

- Mercantis Hub Distribution
- Mercantis Hub Finance
- Mercantis Hub Warehouse
- Mercantis Hub Retail

Those names may appear in marketing copy or onboarding flows, but commercially and technically the product is one app: **Mercantis Hub**.

The correct model is:

> `Mercantis Hub + subscription tier + business preset`

### Configuration examples

| Customer profile | Tier | Preset |
|---|---|---|
| Small importer/wholesaler | Trade | Distribution |
| Stock-heavy business | Stock | Warehouse |
| Retail shop | Complete | Retail |
| Sole trader / service business | Essential | Service |
| Accountant-driven SME | Complete | Finance |

For example:

- `Mercantis Hub — Trade tier — Distribution preset`
- `Mercantis Hub — Stock tier — Warehouse preset`
- `Mercantis Hub — Complete tier — Retail preset`
- `Mercantis Hub — Essential tier — Service preset`

The shared Hub data model and single company/workspace database underpin all configurations. A preset does not fork the data model or create a separate database.

---

## 4. Subscription Group Strategy

Apple's App Store groups related subscription products into a **subscription group**. Within a group, a user can normally hold only one active subscription at a time. This is the correct structure for capability tiers — a customer should have one active Hub plan.

### Recommended group

**Group name:** `Mercantis Hub Plans`

**Subscription products inside the group:**

| Product | Billing |
|---|---|
| Essential Monthly | Monthly |
| Essential Annual | Annual |
| Stock Monthly | Monthly |
| Stock Annual | Annual |
| Trade Monthly | Monthly |
| Trade Annual | Annual |
| Complete Monthly | Monthly |
| Complete Annual | Annual |

The user holds **one active plan** at a time. Upgrading or downgrading moves them between tier products within the same group.

### What not to do

Do **not** create separate subscription groups for Distribution, Warehouse, Finance, Retail, or other business presets. That would force customers to purchase multiple overlapping subscriptions and create support and data nightmares.

Do **not** create subscription products like:
- `Mercantis Hub Distribution`
- `Mercantis Hub Finance + Warehouse`
- `Mercantis Hub Retail Pro`

Business presets are **in-app configurations**, not App Store subscription products.

---

## 5. Capability Tiers

Tiering is based on **capability depth and operational sophistication**, not on artificially withholding documents that small businesses need every day.

Sales Orders and Purchase Orders are included from the **lowest paid tier**. Many micro businesses use these as normal daily workflow documents — removing them from Essential would cripple the app for the very customers it targets.

| Functionality | Essential | Stock | Trade | Complete |
|---|:---:|:---:|:---:|:---:|
| Company setup | ✅ | ✅ | ✅ | ✅ |
| Customers | ✅ | ✅ | ✅ | ✅ |
| Suppliers | ✅ | ✅ | ✅ | ✅ |
| Items | ✅ | ✅ | ✅ | ✅ |
| UOM | ✅ | ✅ | ✅ | ✅ |
| Price Lists | ✅ | ✅ | ✅ | ✅ |
| Quotations | ✅ | ✅ | ✅ | ✅ |
| Sales Orders | ✅ | ✅ | ✅ | ✅ |
| Purchase Orders | ✅ | ✅ | ✅ | ✅ |
| Sales Invoices | ✅ | ✅ | ✅ | ✅ |
| Purchase Invoices | ✅ | ✅ | ✅ | ✅ |
| Payments | ✅ | ✅ | ✅ | ✅ |
| Basic VAT / tax | ✅ | ✅ | ✅ | ✅ |
| Basic GL posting | ✅ | ✅ | ✅ | ✅ |
| Basic customer/supplier balances | ✅ | ✅ | ✅ | ✅ |
| Basic stock balance | ✅ | ✅ | ✅ | ✅ |
| Stock Ledger Entry | — | ✅ | ✅ | ✅ |
| Warehouse transfers | — | ✅ | ✅ | ✅ |
| Stock counts | — | ✅ | ✅ | ✅ |
| Stock reconciliation | — | ✅ | ✅ | ✅ |
| Purchase Receipt | — | ✅ | ✅ | ✅ |
| Delivery / Picking | — | ✅ | ✅ | ✅ |
| Barcode workflows | — | ✅ | ✅ | ✅ |
| Multi-warehouse | — | ✅ | ✅ | ✅ |
| Stock reservation / allocation | — | — | ✅ | ✅ |
| Picking / packing workflow | — | — | ✅ | ✅ |
| Returns / credit notes / debit notes | — | — | ✅ | ✅ |
| AR/AP aging | — | — | ✅ | ✅ |
| Trial Balance | — | — | — | ✅ |
| Profit & Loss | — | — | — | ✅ |
| Balance Sheet | — | — | — | ✅ |
| Advanced VAT reports | — | — | — | ✅ |
| Dashboards | — | — | — | ✅ |
| Advanced approvals | — | — | — | ✅ |
| Batch / serial control | — | — | — | ✅ |
| Multi-company | — | — | — | ✅ |
| Manufacturing | — | — | — | ✅ |

---

## 6. Tier Descriptions

### Essential

**For micro businesses that need normal business documents and basic control.**

Essential is for the smallest businesses: sole traders, small service firms, and micro-retailers who need to issue quotes, take orders, raise invoices, pay suppliers, and track what they owe and are owed. It is not a crippled free tier — it is a complete starter business system.

Includes:

- Customers, suppliers, items
- Quotations, Sales Orders, Purchase Orders
- Sales Invoices, Purchase Invoices, Payments
- Basic VAT/tax
- Basic GL posting
- Basic customer/supplier balances
- Simple stock balance

> **Important:** Do not remove Sales Orders or Purchase Orders from Essential. Many small businesses treat them as normal daily documents — they are not an advanced feature. Removing them would force customers who need them into a higher tier for no substantive reason.

What Essential does **not** include:

- Deep warehouse management (stock ledger, transfers, counts)
- Barcode workflows
- Batch/serial tracking
- Advanced finance reports (Trial Balance, P&L, Balance Sheet)
- Manufacturing
- Multi-company

---

### Stock

**For businesses where stock accuracy matters.**

Stock is for businesses that need to know exactly what they have, where it is, and how it moves — but do not yet need the full trading and distribution sophistication of Trade.

Includes everything in Essential, plus:

- Stock Ledger Entry (real-time inventory position)
- Warehouses and multi-warehouse
- Warehouse transfers
- Stock counts and stock reconciliation
- Purchase Receipt
- Basic Delivery and Picking
- Barcode item lookup
- Stock movement history

Stock does **not** include advanced stock reservation/allocation, sophisticated picking/packing workflows, or returns management. Those come with Trade.

---

### Trade

**For wholesalers, importers, distributors, and stock-based traders.**

Trade is the flagship tier. It is designed for small businesses that buy, hold, and sell physical stock across a supply chain. The full order-to-delivery and procure-to-pay flow is supported.

Includes everything in Stock, plus:

- Stronger sales and purchasing workflow (full quote-to-cash, procure-to-pay)
- Stock reservation and allocation
- Picking/packing workflow
- Returns, credit notes, debit notes
- Customer/supplier aging (AR/AP)
- Stronger operational and warehouse reports

Trade is the natural home for distributors, importers, wholesalers, and stock-based SMEs. It should be the most commercially prominent plan.

---

### Complete

**For small businesses using Mercantis Hub as their full operational and financial system.**

Complete is for businesses that need not just trading capability but a full accounting and financial reporting picture — together with advanced operational controls.

Includes everything in Trade, plus:

- Advanced finance (full accounting reports)
- Trial Balance, Profit & Loss, Balance Sheet
- Advanced VAT/tax reports
- Dashboards
- Advanced approvals
- Batch/serial tracking
- Multi-company
- Advanced audit and reversal controls
- Future manufacturing capabilities (BOMs, Work Orders, Production Plans)

---

## 7. Business Presets

Business presets are **not App Store subscription products**. They are in-app configurations that adapt Mercantis Hub's navigation, terminology, setup checklist, reports, dashboards, and workflow emphasis to a specific type of business.

A customer does not buy a preset. They choose a tier (what capabilities they need), and then choose a preset (how they want the app configured for their business type).

| Preset | Best for | Changes the app by |
|---|---|---|
| Retail | Shops and small retailers | Retail-focused navigation, item/barcode focus, quick sales, stock, purchasing, VAT |
| Distribution | Wholesalers, importers, distributors | Sales orders, purchase orders, receiving, picking, delivery, invoicing |
| Warehouse | Stock-heavy businesses | Stock counts, transfers, receiving, picking, movement history |
| Service | Service and repair businesses | Customers, quotations, jobs, invoicing, payments |
| Finance | Accounting-focused businesses | Invoices, payments, VAT, GL, customer/supplier balances, finance reports |
| Light Manufacturing | Small assemblers/manufacturers | BOMs, work orders, material issue, finished goods receipt |

A preset controls:

- **Navigation** — which modules and items appear in the sidebar
- **Default dashboard** — the home screen and key metric tiles
- **Terminology** — labels and field names adapted to the industry (e.g. "Job" vs "Sales Order")
- **Setup checklist** — the first-run wizard steps relevant to this business type
- **Visible reports** — which reports are surfaced by default
- **Workflow emphasis** — which workflows are prominent
- **Quick actions** — the top-level actions available from the home screen

A preset does **not**:

- Create a separate database
- Create a separate company workspace
- Represent a separate product or subscription
- Prevent a business from accessing capabilities included in their tier

A customer should be able to change their preset later without data loss.

---

## 8. Recommended Launch Packaging

### Subscription tiers at launch

- Essential
- Stock
- Trade *(flagship — most commercially prominent)*
- Complete

### Business presets at launch

Initially:

- Retail
- Distribution
- Warehouse
- Finance

Later (post-launch):

- Service
- Light Manufacturing

### Flagship positioning

`Trade` should be the flagship commercial plan. It aligns directly with the core Hub target customer: small distributors, importers, wholesalers, and stock-based SMEs who need a real operational system — not just invoicing, and not a full enterprise ERP.

Marketing copy should lead with Trade and position Essential as the entry point and Complete as the advanced upgrade, rather than trying to position all four tiers equally.

---

## 9. Implementation Implications

This section describes a conceptual model for how commercial configuration could be implemented in the future. **Do not implement this yet.** It exists to establish shared vocabulary and avoid architectural decisions that would foreclose the right model.

The active commercial configuration determines what is visible, enabled, and licensed — not just the raw list of DocTypes in `HubManifest`. The current `HubManifest` may continue to aggregate all DocTypes, but a commercial configuration layer should gate what is surfaced to the user.

```swift
enum HubSubscriptionTier: String, Codable {
    case essential
    case stock
    case trade
    case complete
}

enum HubBusinessPreset: String, Codable {
    case retail
    case distribution
    case warehouse
    case service
    case finance
    case lightManufacturing
}

struct HubCommercialConfiguration: Codable {
    let subscriptionTier: HubSubscriptionTier
    let businessPreset: HubBusinessPreset
    let enabledModules: Set<String>
    let enabledDocTypes: Set<String>
    let enabledReports: Set<String>
    let enabledDashboards: Set<String>
    let enabledWorkflows: Set<String>
}
```

The `HubCommercialConfiguration` is resolved at runtime from the active App Store subscription and the customer's chosen preset. It determines which features of the installed Hub are unlocked for use.

The underlying data model — tables, schema, DocType definitions — remains shared. There is no per-preset or per-tier database forking.

---

## 10. Design Rules

These rules govern all future decisions about commercial packaging, tiering, and preset design.

1. **Never create separate databases for different presets.** All configurations share one company workspace.
2. **Never force customers to buy multiple overlapping subscriptions.** One tier covers everything the customer needs at that capability level.
3. **Never make normal business documents premium-only if micro/small businesses need them daily.** Sales Orders and Purchase Orders belong in Essential.
4. **Use tiering for depth, scale, automation, reporting, and advanced controls** — not for gating everyday workflow documents.
5. **Keep customer-facing terminology simple.** Avoid enterprise ERP language such as "modular suite", "ledger engine", "DocType", or "workflow engine" in any customer-facing copy.
6. **Keep internal modules separate from commercial packaging.** The CRM, Selling, Buying, Stock, and Accounting modules are internal implementation groupings. They must not map one-to-one to commercial tier names.
7. **Allow a business to change preset later without data loss.** A preset is a view configuration, not a data migration.
8. **Allow upgrade/downgrade of subscription tier without changing the underlying company data model.** Tier changes affect what is visible and enabled, not the schema.
9. **Avoid enterprise ERP language in customer-facing copy.** The product should feel like a practical business tool, not a modular enterprise suite.
10. **The product should feel like a complete business system at every tier,** not a minimal core with expensive add-ons bolted on.

---

## 11. Summary

Mercantis Hub is one App Store app, one product family, and one shared data model.

Customers subscribe to a **capability tier** — Essential, Stock, Trade, or Complete — and choose a **business preset** — Retail, Distribution, Warehouse, Service, Finance, or Light Manufacturing — that configures the in-app experience for their type of business.

The lowest paid tier must support normal small-business documents including Sales Orders and Purchase Orders. Tiering exists to unlock operational depth, warehouse sophistication, advanced distribution flows, stronger finance, dashboards, multi-company, batch/serial, and manufacturing — not to gatekeep documents that every small business needs.

The technical implementation is always one shared Hub data model and one shared company/workspace database, regardless of which tier or preset the customer has chosen.

---

## Cross-references

- [`Docs/HUB-STATUS.md`](HUB-STATUS.md) — Hub implementation status, ERP module coverage, and known Core walls.
- [`Docs/HUB-UX-DIRECTION.md`](HUB-UX-DIRECTION.md) — Hub ERP UX direction, product strategy, and phased UX roadmap.
- Core architecture: [`mercantis.core.app/ARCHITECTURE.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/ARCHITECTURE.md)
- Core implementation status: [`mercantis.core.app/Docs/STATUS.md`](https://github.com/KevinBusuttil/mercantis.core.app/blob/main/Docs/STATUS.md)
