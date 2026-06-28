# Mercantis Hub — Accounting Autopilot Gap Analysis

> Target user: a **non-accounting-aware micro/small-business CEO**. The product
> goal is that the owner chooses country, business type, tax registration, and
> accounting basis, and the app automatically creates a sensible chart of
> accounts, tax setup, posting defaults, document defaults, reports, and safe
> accounting workflows — without the owner ever understanding debit/credit, a
> chart of accounts, VAT posting, receivables, payables, GRNI, or retained
> earnings.
>
> This analysis is grounded in a static review of the actual source of both
> repositories (`mercantis.core.app`, `mercantis.hub.app`), cross-checked by an
> adversarial multi-agent investigation (24 agents). Where a conclusion rests on
> behaviour that can only be confirmed by running the app, that is stated
> explicitly.

---

## 1. Executive summary

**Verdict: Not yet a turnkey product for a non-accountant CEO — but much closer on the *transaction* side than the *setup* side, and the failure mode is specific, not systemic.**

The codebase already contains a working **single-company account-autopilot for day-to-day operations**: documents carry their ledger accounts as *required* fields auto-filled from a Business-Profile default map, posting is atomic and fail-closed, and the four core financial statements (Trial Balance, Balance Sheet, P&L, VAT Summary) are GL-derived and provably balanced. The often-fatal "user must pick debit/credit accounts on every invoice" problem is **already solved at the company-default level**, and "a transaction can post with no accounts" is **already prevented**.

What is missing is the layer above and around that engine:

> **The app has accounting infrastructure but lacks a jurisdiction-aware accounting setup layer. It seeds only a minimal 9-account starter chart and does not provide the "accounting autopilot" setup experience a non-accountant owner expects.**

The single biggest missing layer is the **Jurisdiction-Aware Accounting Setup (Country → COA template + Tax template + posting defaults)**. Two concrete consequences make the product feel "not ready" on day one:

1. **Zero tax codes are seeded.** A VAT/GST/sales-tax-registered owner gets *no* tax codes and must hand-build Standard/Reduced/Zero/Exempt — the exact accounting work the product promises to remove.
2. **The 9-account COA has no equity at all** — no Owner Capital, Owner Drawings, or Retained Earnings — and almost no expense detail. The Balance Sheet cannot carry equity beyond on-the-fly current-year earnings, year-end can't roll forward, and the P&L is a single COGS line with no operating expenses.

**Risk if not implemented:** the owner hits a wall at the two moments that matter most — *first invoice with tax* and *first year-end / accountant handover*. The danger is silent: the app produces a "balanced" Trial Balance that is nonetheless **wrong for filing** because tax codes and equity were never set up.

---

## 2. Evidence from source code

**Files reviewed (Hub):** `Modules/Onboarding/HubOnboardingSeeder.swift`, `UI/Onboarding/HubOnboardingView.swift`, `Navigation/HubVisibility.swift` & `HubPreset.swift`, `Modules/Setup/SetupDocTypes.swift`, `Modules/Accounting/AccountingDocTypes.swift`, `Modules/Tax/*` + `HubTaxEngine`/`HubTaxCalculationPolicy`, `Modules/Selling/SellingDocTypes.swift`, `Modules/Buying/BuyingDocTypes.swift`, `Modules/POS/POSDocTypes.swift`, `HubBusinessProfileDefaultsPolicy.swift`, `HubFiscalYearValidationPolicy.swift`, `PostingCoordinator.swift`, `Reports/HubReports.swift`, `HubManifest`, `UI/Home/HubHomeView.swift`, `HubGlossary.swift`, `HubPostingIntegrationTests.swift`. **Core:** `DocumentEngine/DocumentEngine.swift` (+ `ValidationPipeline`/`RequiredFieldStage`), `Posting/*` (`PostingCoordinator`, `GLEntry`, `PostingBatch`), `Metadata/FieldDefinition.swift`, `Reporting/ReportEngine` + `ReportResultCSV`, `ImportExport/DataImporter`/`DataExporter`, `DocumentEngine/AuditLog.swift`, `Naming/NamingSeriesStrategy`. **Docs:** `HUB-STATUS.md`, `HUB-UX-DIRECTION.md`, `ARCHITECTURE.md`.

| Conclusion | Evidence |
|---|---|
| Onboarding seeds exactly 9 accounts + currency + fiscal year + warehouse + Company, idempotently | `HubOnboardingSeeder.swift:21-31, 51-95, 100-109, 111-141` |
| Wizard asks only business name + currency (EUR/USD/GBP) + preset; **no country/tax-reg/basis** | `HubOnboardingView.swift:45-62, 66-72` |
| Presets configure **module visibility only**, not accounting | `HubVisibility.swift:49-51`; `HubPreset` enum |
| **No tax codes seeded**; TaxCode model exists but unconfigured | seeder creates no TaxCode; `Modules/Tax/*` |
| Account model = tree (name/parent/is_group/account_type/root_type/currency/disabled); **no number, opening balance, normal-balance, report-line, tax-control flags** | `AccountingDocTypes.swift` Account def |
| Accounts are **required fields**, auto-filled, fail-closed | `SellingDocTypes.swift:363-366`, `HubBusinessProfileDefaultsPolicy`, `DocumentEngine.save` RequiredFieldStage, `PostingCoordinator.salesInvoiceRows()` |
| Resolution is **two-tier (doc fields + Company defaults) + POS third tier**; no per-Customer/Supplier/Item/Tax/PaymentMethod/Bank profiles | `HubBusinessProfileDefaultsPolicy`; masters have no account fields |
| TB / BS / P&L / VAT Summary exist, GL-derived, **balance** (atomic posting, tested) | `HubReports.swift:170-178, 212-250, 835-922`; `HubPostingIntegrationTests.swift:143-150` |
| Period **lock** exists (is_closed blocks posting); **no auto-close / retained-earnings carry-forward** | `PostingCoordinator.swift:199-213` |
| **No** opening-balance flow, bank master/statement import/reconciliation, payment-method master | only generic `DataImporter`/`DataExporter` |
| **No** accountant export pack / review-lock; audit log + per-report CSV exist | `AuditLog.swift`, `ReportResultCSV`, `DataExporter:26-44` |
| Owner-friendliness: Advanced toggle + glossary + guided payment flows exist; **jargon labels on owner forms; accountant role not enforced** | `HubVisibility` .normal/.advanced; `HubGlossary`; `SellingDocTypes` labels |

*Adversarial calibration:* two would-be gaps were **refuted** — "documents can post without accounts" (they cannot; required + fail-closed) and "reports don't balance" (they do, tested).

---

## 3. Functional gap matrix

| Area | Current capability | Missing functionality | Business impact | Priority | Suggested objects |
|---|---|---|---|---|---|
| Jurisdiction setup | name + currency + preset | country, tax-registration, accounting-basis driving setup | wrong/generic local setup | **P0** | `JurisdictionSetupWizard`, `Jurisdiction` |
| COA template | fixed 9 accounts, no equity | template library + equity/expense/clearing detail | BS can't carry equity; P&L has no expenses | **P0** | `COATemplate(Library)`, `COASeeder` |
| Tax template | models + engine, **no codes seeded** | country tax codes; reverse charge/EU B2B/exempt; US state+local; CA GST/HST/PST; input vs output + settlement; return boxes | VAT-registered owner has no codes day one | **P0** | `TaxTemplate(Library)` |
| Posting profiles | doc fields + company defaults | per-Customer/Supplier/Item/Tax/PaymentMethod/Bank overrides; central resolver | no product/service P&L split | **P1** | `PostingProfile`, `AccountResolver` |
| Owner vs Accountant mode | advanced toggle + glossary | role-enforced field hide/relabel; owner vocabulary | owner sees "Debit To", "GRNI" | **P1** | `OwnerMode`, `FieldVisibilityPolicy` |
| Opening balances | manual journal only | guided wizard → auto opening journal + review | can't migrate from Excel/QB/Xero | **P0** | `OpeningBalanceWizard`, `OpeningBalanceSet` |
| Bank & processors | PaymentEntry direct GL | bank/cash/card/Stripe/PayPal accounts; CSV import; reconciliation; merchant-fee leg | no bank truth; fees mis-posted | **P1** | `BankAccount`, `BankStatementLine`, `BankReconciliation` |
| Business presets (accounting) | module visibility only | preset → COA variant, tax defaults, payment methods, item groups, POS/stock behaviour | retail vs service identical (wrong) | **P1** | `BusinessProfileTemplate` |
| Year-end close | is_closed lock | auto close → Retained Earnings, carry forward, lock-after-review, prior-year warning | no legal year-end; equity never settles | **P1** | `YearEndCloseService`, `ClosingEntry` |
| Accountant collaboration | audit log + per-report CSV | one-click pack; review status; lock-after-review; notes | can't hand a clean file to accountant | **P1** | `AccountantExportPack`, `ReviewStatus` |
| Tax return / compliance | VAT Summary (rolled up) | return preview with boxes; tax periods + lock | can't file confidently | **P2** | `TaxReturn`, `TaxPeriod` |

---

## 4. Required new functional modules

(Each: Purpose · User story · Screens · DocTypes/models · Services · Validations · Reports · Tests.)

1. **Jurisdiction Setup Wizard** — turn 4 answers (country, business type, tax registration, accounting basis) into a complete correct setup. Models: `Jurisdiction`; new `Company` fields (country, tax_regime, tax_registered, tax_id, accounting_basis). Service: `AccountingSetupService` orchestrating COA/Tax/FiscalYear/Numbering seeders. Tests: each country → balanced zero opening TB, expected tax-code count, equity present.
2. **COA Template Library** — business-ready charts per jurisdiction/basis. Model: `COATemplate { accounts:[{code,name,root_type,account_type,parent_code,is_group,tax_control,normal_balance}] }`; library: Generic-IFRS-SME, EU-VAT, Malta, UK, Ireland, US, Canada, Cash/No-tax. Service: `COASeeder`. Adds Owner Capital/Drawings/Retained Earnings/Opening-Balance-Equity/Suspense.
3. **Tax Template Library** — country tax codes + control accounts. Model: `TaxTemplate`; separate Input/Output VAT + Settlement. Extends `HubTaxCalculationPolicy` to honour treatment (reverse charge, zero, exempt).
4. **Posting Profile Engine** — layered overrides via a central `AccountResolver` (item → item-group → party → party-group → company default → fail). Refactors `HubBusinessProfileDefaultsPolicy` + `PostingCoordinator` to call it.
5. **Opening Balance Wizard** — guided day-one migration → balanced opening journal + review report. Model: `OpeningBalanceSet`.
6. **Bank Reconciliation** — `BankAccount`/`BankStatementLine`/`BankReconciliation`; CSV/OFX import; matching; fee auto-leg; clearing accounts.
7. **Owner Mode vs Accountant Mode** — `FieldVisibilityPolicy` (role/mode hide+relabel of account fields); enforce `accountant`/`systemManager` roles; owner-language reports.
8. **Business-Type Accounting Presets** — extend `HubPreset` → `BusinessProfileTemplate` (COA variant, tax defaults, payment methods, item groups, stock/POS behaviour).
9. **Year-End Close** — `YearEndCloseService`/`ClosingEntry`: net income → Retained Earnings, carry forward, lock-after-review, prior-year guard.
10. **Accountant Export Pack** — `AccountantExportPack` (TB+GL+VAT+aging+stock-val+bank-rec); `ReviewStatus`; lock-after-review; notes.

---

## 5. Suggested Swift architecture

Most of this is jurisdiction/domain logic → **Hub**, with a few generic primitives in **Core**.

```
mercantis hub/Modules/
  Setup/Jurisdiction.swift                       // model + library (countries)
  Setup/JurisdictionSetupWizard/                 // UI + AccountingSetupService
  Accounting/Templates/COATemplate.swift         // model + COATemplateLibrary + COASeeder
  Accounting/Templates/TaxTemplate.swift         // model + TaxTemplateLibrary + TaxSeeder
  Accounting/HubAccountResolver.swift            // central resolver (generalises default lookups)
  Accounting/PostingProfiles/PostingProfile.swift
  Accounting/OpeningBalances/...                 // OpeningBalanceSet + service + wizard
  Accounting/BankReconciliation/...              // BankAccount/Statement/Reconciliation
  Accounting/YearEndClose/...                    // YearEndCloseService + ClosingEntry
  Reports/AccountantExportPack.swift
mercantis hub/UI/Modes/                          // OwnerMode / AccountantMode / FieldVisibilityPolicy
```

**Core additions:** Account model fields (number/report_group/normal_balance/is_tax_control/allow_posting); a defaulting hook so the resolver runs as a stage; mode-aware label/visibility resolver in `GenericFormView`; `StatementImporter` protocol; `ReportBundle` for the export pack. Reuse `PostingCoordinator`, `UnitOfWork`, `AuditLog`, `ReportEngine`, `NamingSeriesStrategy`, `HubManifest`.

---

## 6. Minimum viable implementation plan

### Phase 1 — Accounting Autopilot Foundation (the P0 layer)
- **Change:** `HubOnboardingView` (country/tax-reg/basis steps), `HubOnboardingSeeder` (delegate to template seeders), `Company` (+jurisdiction fields + equity/RE/suspense defaults), `AccountingDocTypes` (Account fields), `HubBusinessProfileDefaultsPolicy` → `AccountResolver`, `HubManifest`.
- **Add:** `Jurisdiction`, `COATemplate(+Library+Seeder)`, `TaxTemplate(+Library+Seeder)`, `AccountResolver`, `PostingProfile`, `AccountingSetupService`.
- **Functional AC:** owner picks country+type+tax-status; app seeds a country-appropriate COA *with equity + expense detail* and a starter tax-code set; first invoice defaults the right tax + accounts with zero account-picking.
- **Technical AC:** every jurisdiction seeds a balanced (zero) opening TB; required-account set present; resolver is the only path to a posting account; submit still fail-closed.

### Phase 2 — Migration and Banking
Opening balance wizard; bank/cash/processor accounts; CSV bank import; reconciliation; payment matching.

### Phase 3 — Compliance and Accountant Collaboration
VAT/GST/sales-tax return preview (boxes); period/tax locks; year-end close; accountant export pack; audit/review status.

### Phase 4 — Business-Type Presets and UX polish
Service / Retail-POS / Distributor / Consultant accounting presets; owner-mode vs accountant-mode UI split.

---

## 7. P0 acceptance criteria (status at time of analysis)

| P0 criterion | Status |
|---|---|
| Create company by choosing **country** and business type | ❌ country not asked |
| App creates suitable **COA** automatically | ⚠️ 9 accounts, no equity/expense detail |
| App creates **tax codes** automatically | ❌ none seeded |
| App creates **fiscal year** automatically | ✅ |
| App creates **bank/cash/payment-method** defaults | ⚠️ Cash+Bank yes; no payment-method master |
| Issue **sales invoice** without selecting accounts | ✅ |
| Create **purchase invoice** without selecting accounts | ✅ |
| Record **customer payment** without selecting accounts | ✅ |
| Record **supplier payment** without selecting accounts | ✅ |
| **VAT/GST/sales-tax report** meaningful | ⚠️ VAT Summary; no boxes; useless until codes seeded |
| **Trial Balance** balances | ✅ |
| **Balance Sheet** balances | ⚠️ mechanically, but no real equity |
| **P&L** meaningful | ⚠️ thin (COGS only) |
| User can enter **opening balances** | ❌ |
| User can export an **accountant pack** | ❌ |
| No submitted transaction posts with **missing account mappings** | ✅ |

Transactional P0s essentially met; setup/opening-balance/tax-seed/equity/accountant-pack P0s are the blockers. Phase 1 closes most.

---

## 8. Triple-check (confidence)

**Strong:** minimal 9-account COA identical across presets/countries; no tax codes seeded; no jurisdiction templates; no opening-balance wizard; no bank reconciliation; no accountant pack; no year-end automation (lock only); no equity accounts. Refuted gaps (now confirmed present): required + fail-closed posting; TB/BS/P&L/VAT exist and balance.

**Partial:** a *company-level* resolver exists (`HubBusinessProfileDefaultsPolicy`) + POS overrides — per-entity profiles absent. Owner/accountant separation has an Advanced toggle + glossary (now surfaced via Help ▸ Glossary + in-form "?") but no role-enforced account hiding; accountant role not enforced (all run as System Manager).

**Requires runtime testing:** that each seeded path yields a balanced zero opening TB and VAT posts to the correct legs — provable only by running the app (no Swift toolchain in the analysis environment; verified by reading, not execution). Reverse-charge / state+local / GST-HST-PST do not exist yet (net-new).

---

## Closing principle

The app already *supports* accounting and *hides* account selection for routine posting. It does not yet **protect the non-accountant from accounting complexity at setup and year-end/handover.** The missing piece is the **Accounting Autopilot Layer** — *country + business type + tax registration + bank + opening balances → a correct, jurisdiction-aware setup* — after which the owner lives entirely in invoices, bills, payments, stock, POS, and reports. **Phase 1 (Jurisdiction Wizard + COA/Tax template libraries + AccountResolver) is the highest-leverage work and must ship before any real non-accountant business is onboarded** — above all, seed real tax codes and a chart that includes owner equity and retained earnings, because without those the "balanced" books are quietly unfileable.
