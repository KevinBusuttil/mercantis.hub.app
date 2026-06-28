import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 1 (Accounting Autopilot) — guards for the jurisdiction-aware setup:
/// the COA + tax template libraries, the Business-Profile wiring, idempotent
/// seeding, and that a non-accountant can issue an invoice that defaults the
/// right accounts AND the right tax with zero manual accounting.
final class AccountingSetupTemplateTests: XCTestCase {

    // MARK: - COA template library (pure)

    func test_coa_vat_template_includes_equity_expenses_and_tax_controls() {
        let chart = HubCOATemplateLibrary.accounts(taxStyle: .vat)
        let ids = Set(chart.map(\.id))
        // Equity — the layer the old 9-account stub was missing entirely.
        XCTAssertTrue(ids.isSuperset(of: ["OwnerCapital", "OwnerDrawings", "RetainedEarnings", "OpeningBalanceEquity"]))
        // Operating expenses.
        XCTAssertTrue(ids.isSuperset(of: ["Rent", "Utilities", "BankCharges", "MerchantFees", "Wages", "Suspense"]))
        // Clearing + tax control.
        XCTAssertTrue(ids.isSuperset(of: ["CardClearing", "ProcessorClearing", "VAT", "InputVAT"]))
    }

    func test_coa_no_tax_template_omits_tax_control_accounts() {
        let ids = Set(HubCOATemplateLibrary.accounts(taxStyle: .none).map(\.id))
        XCTAssertFalse(ids.contains("VAT"))
        XCTAssertFalse(ids.contains("InputVAT"))
        // Core posting anchors still present.
        XCTAssertTrue(ids.isSuperset(of: ["Cash", "Debtors", "Creditors", "Sales", "COGS", "Stock", "GRNI"]))
    }

    func test_coa_slots_cover_every_company_default_with_canonical_ids() {
        let chart = HubCOATemplateLibrary.accounts(taxStyle: .vat)
        let bySlot = Dictionary(uniqueKeysWithValues: chart.compactMap { acc in acc.slot.map { ($0, acc.id) } })
        XCTAssertEqual(bySlot[.receivable], "Debtors")
        XCTAssertEqual(bySlot[.payable], "Creditors")
        XCTAssertEqual(bySlot[.income], "Sales")
        XCTAssertEqual(bySlot[.expense], "COGS")
        XCTAssertEqual(bySlot[.cashBank], "Cash")
        XCTAssertEqual(bySlot[.stock], "Stock")
        XCTAssertEqual(bySlot[.grni], "GRNI")
        XCTAssertEqual(bySlot[.vatControl], "VAT")
        // Every slot mapped exactly once.
        XCTAssertEqual(bySlot.count, HubAccountSlot.allCases.count)
    }

    func test_account_defaults_map_matches_legacy_wiring() {
        let chart = HubCOATemplateLibrary.accounts(taxStyle: .vat)
        let map = HubOnboardingSeeder.accountDefaults(from: chart)
        for (key, value) in HubOnboardingSeeder.companyDefaults {
            XCTAssertEqual(map[key], value, "slot wiring for \(key) must match the canonical default")
        }
    }

    // MARK: - Tax template library (pure)

    func test_malta_registered_seeds_full_vat_band_with_standard_default() {
        let mt = HubJurisdictionLibrary.jurisdiction(id: "MT")
        let codes = HubTaxTemplateLibrary.codes(for: mt, registered: true)
        let byId = Dictionary(uniqueKeysWithValues: codes.map { ($0.id, $0) })
        XCTAssertEqual(byId["VAT-STD"]?.rate, 18)
        XCTAssertTrue(byId["VAT-STD"]?.isDefault ?? false)
        XCTAssertNotNil(byId["VAT-ZERO"])
        XCTAssertNotNil(byId["VAT-EXEMPT"])
        XCTAssertEqual(codes.filter(\.isDefault).count, 1, "exactly one default code")
        XCTAssertEqual(HubTaxTemplateLibrary.defaultCodeId(for: mt, registered: true), "VAT-STD")
    }

    func test_not_registered_seeds_single_no_tax_default() {
        let mt = HubJurisdictionLibrary.jurisdiction(id: "MT")
        let codes = HubTaxTemplateLibrary.codes(for: mt, registered: false)
        XCTAssertEqual(codes.count, 1)
        XCTAssertEqual(codes.first?.id, "NO-TAX")
        XCTAssertEqual(codes.first?.rate, 0)
        XCTAssertTrue(codes.first?.isDefault ?? false)
    }

    func test_us_and_canada_use_sales_tax_codes() {
        let us = HubTaxTemplateLibrary.codes(for: HubJurisdictionLibrary.jurisdiction(id: "US"), registered: true)
        XCTAssertEqual(us.first(where: \.isDefault)?.id, "SALES-TAX")
        XCTAssertTrue(us.allSatisfy { $0.type == "SalesTax" })

        let ca = HubTaxTemplateLibrary.codes(for: HubJurisdictionLibrary.jurisdiction(id: "CA"), registered: true)
        XCTAssertEqual(ca.first(where: \.isDefault)?.id, "GST")
    }

    func test_jurisdiction_library_and_currency_mapping() {
        XCTAssertEqual(HubJurisdictionLibrary.jurisdiction(id: "GB").currencyCode, "GBP")
        XCTAssertEqual(HubJurisdictionLibrary.jurisdiction(id: "US").taxStyle, .salesTax)
        XCTAssertEqual(HubJurisdictionLibrary.jurisdiction(id: "NONE").taxStyle, HubTaxStyle.none)
        XCTAssertEqual(HubJurisdictionLibrary.forCurrency("GBP").id, "GB")
        XCTAssertEqual(HubJurisdictionLibrary.forCurrency("CAD").id, "CA")
    }

    func test_normal_balance_sides() {
        XCTAssertEqual(HubCOATemplateLibrary.normalBalance(for: "Asset"), "Debit")
        XCTAssertEqual(HubCOATemplateLibrary.normalBalance(for: "Expense"), "Debit")
        XCTAssertEqual(HubCOATemplateLibrary.normalBalance(for: "Liability"), "Credit")
        XCTAssertEqual(HubCOATemplateLibrary.normalBalance(for: "Income"), "Credit")
        XCTAssertEqual(HubCOATemplateLibrary.normalBalance(for: "Equity"), "Credit")
    }

    // MARK: - End-to-end seeding (real engine)

    private func makeEngine() throws -> (MercantisDatabase, DocumentEngine, URL) {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("hub-setup-\(UUID().uuidString).sqlite")
        let database = try MercantisDatabase(databaseURL: url)
        let registry = MetadataRegistry(database: database)
        let installer = AppInstaller(database: database, schemaValidator: SchemaValidator(), registry: registry)
        try installer.install(HubManifest.build())
        let engine = DocumentEngine(database: database, registry: registry, deviceId: "test-device", userId: "tester")
        return (database, engine, url)
    }

    func test_seeding_malta_creates_chart_tax_codes_and_wired_company() throws {
        let (_, engine, url) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: url) }

        let mt = HubJurisdictionLibrary.jurisdiction(id: "MT")
        HubOnboardingSeeder.seed(engine: engine, businessName: "Busuttil Ltd",
                                 jurisdiction: mt, registered: true, taxId: "MT12345678", basis: .accrual)

        // Equity + posting anchors exist as real Account records.
        for id in ["RetainedEarnings", "OwnerCapital", "Cash", "Debtors", "Creditors", "Sales", "COGS", "VAT", "InputVAT"] {
            XCTAssertNotNil(try? engine.fetch(docType: "Account", id: id), "Account \(id) must be seeded")
        }
        // Standard VAT code at 18%.
        let std = try? engine.fetch(docType: "TaxCode", id: "VAT-STD")
        XCTAssertNotNil(std)
        XCTAssertEqual(std.flatMap { doubleField($0.fields["rate"]) }, 18)

        // Company wired to defaults + jurisdiction.
        let company = try XCTUnwrap((try? engine.list(docType: "Company"))?.first)
        XCTAssertEqual(stringField(company.fields["default_receivable_account"]), "Debtors")
        XCTAssertEqual(stringField(company.fields["default_income_account"]), "Sales")
        XCTAssertEqual(stringField(company.fields["default_vat_account"]), "VAT")
        XCTAssertEqual(stringField(company.fields["default_tax_code"]), "VAT-STD")
        XCTAssertEqual(stringField(company.fields["country"]), "Malta")
        XCTAssertEqual(boolField(company.fields["tax_registered"]), true)
        XCTAssertEqual(stringField(company.fields["vat_tax_number"]), "MT12345678")
    }

    func test_seeding_is_idempotent() throws {
        let (_, engine, url) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: url) }

        let mt = HubJurisdictionLibrary.jurisdiction(id: "MT")
        HubOnboardingSeeder.seed(engine: engine, businessName: "Busuttil Ltd",
                                 jurisdiction: mt, registered: true, taxId: "", basis: .accrual)
        let firstCount = (try? engine.list(docType: "Account"))?.count ?? 0
        HubOnboardingSeeder.seed(engine: engine, businessName: "Busuttil Ltd",
                                 jurisdiction: mt, registered: true, taxId: "", basis: .accrual)
        let secondCount = (try? engine.list(docType: "Account"))?.count ?? 0
        XCTAssertEqual(firstCount, secondCount, "re-seeding must not duplicate accounts")
        XCTAssertGreaterThan(firstCount, 30, "the jurisdiction chart is a full business-ready COA")
    }

    func test_new_sales_invoice_defaults_accounts_and_tax_without_user_input() throws {
        let (_, engine, url) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: url) }

        let mt = HubJurisdictionLibrary.jurisdiction(id: "MT")
        HubOnboardingSeeder.seed(engine: engine, businessName: "Busuttil Ltd",
                                 jurisdiction: mt, registered: true, taxId: "", basis: .accrual)
        let company = try XCTUnwrap((try? engine.list(docType: "Company"))?.first)
        let salesInvoice = try XCTUnwrap(HubManifest.docType(for: "SalesInvoice"))

        // A blank draft, as the owner would start it.
        let draft = Document(id: "", docType: "SalesInvoice", company: "", status: "",
                             createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
                             fields: [:], children: [:])
        let prepared = HubBusinessProfileDefaultsPolicy.prepareForFirstSave(
            draft, docType: salesInvoice, businessProfile: company
        )

        XCTAssertEqual(stringField(prepared.fields["debit_to"]), "Debtors",
                       "receivable account auto-filled — owner never picks it")
        XCTAssertEqual(stringField(prepared.fields["income_account"]), "Sales")
        XCTAssertEqual(stringField(prepared.fields["tax_code"]), "VAT-STD",
                       "the registered country's standard VAT applies automatically")
    }

    // MARK: - Field coercion helpers

    private func stringField(_ value: FieldValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }
    private func boolField(_ value: FieldValue?) -> Bool? {
        if case .bool(let b)? = value { return b }
        return nil
    }
    private func doubleField(_ value: FieldValue?) -> Double? {
        switch value {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }
}
