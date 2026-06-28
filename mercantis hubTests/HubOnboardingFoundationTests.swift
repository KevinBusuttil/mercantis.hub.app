import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 8 — Presets & Onboarding wiring guards.
@MainActor
final class HubOnboardingFoundationTests: XCTestCase {

    // MARK: - Preset capability mapping

    func test_preset_capability_mapping() {
        XCTAssertFalse(HubPreset.services.enablesPOS)
        XCTAssertFalse(HubPreset.services.enablesDeliveries)
        XCTAssertFalse(HubPreset.services.enablesManufacturing)

        XCTAssertTrue(HubPreset.tradeDistribution.enablesDeliveries)
        XCTAssertFalse(HubPreset.tradeDistribution.enablesPOS)

        XCTAssertTrue(HubPreset.retailPOS.enablesPOS)
        XCTAssertTrue(HubPreset.lightManufacturing.enablesManufacturing)

        // Consultant is a service-type preset: no optional modules.
        XCTAssertFalse(HubPreset.consultant.enablesPOS)
        XCTAssertFalse(HubPreset.consultant.enablesDeliveries)
        XCTAssertFalse(HubPreset.consultant.enablesManufacturing)

        XCTAssertEqual(HubPreset.allCases.count, 5)
    }

    // MARK: - Apply + module gating

    private func module(_ id: String) -> HubModule {
        HubNavigation.allModules.first { $0.id == id }!
    }

    func test_services_preset_hides_optional_modules() {
        let settings = HubVisibilitySettings()
        settings.apply(.services)
        XCTAssertFalse(settings.isModuleVisible(module("pos")))
        XCTAssertFalse(settings.isModuleVisible(module("deliveries")))
        XCTAssertFalse(settings.isModuleVisible(module("manufacturing")))
        // Core modules always show.
        XCTAssertTrue(settings.isModuleVisible(module("selling")))
    }

    func test_retail_preset_reveals_pos_only() {
        let settings = HubVisibilitySettings()
        settings.apply(.retailPOS)
        XCTAssertTrue(settings.isModuleVisible(module("pos")))
        XCTAssertFalse(settings.isModuleVisible(module("deliveries")))
        XCTAssertFalse(settings.isModuleVisible(module("manufacturing")))
    }

    func test_trade_preset_reveals_deliveries_only() {
        let settings = HubVisibilitySettings()
        settings.apply(.tradeDistribution)
        XCTAssertTrue(settings.isModuleVisible(module("deliveries")))
        XCTAssertFalse(settings.isModuleVisible(module("pos")))
    }

    func test_manufacturing_hidden_until_light_manufacturing_preset() {
        let settings = HubVisibilitySettings()
        settings.apply(.services)
        XCTAssertFalse(settings.isModuleVisible(module("manufacturing")))
        settings.apply(.lightManufacturing)
        XCTAssertTrue(settings.isModuleVisible(module("manufacturing")))
    }

    func test_capability_can_be_toggled_manually_after_preset() {
        let settings = HubVisibilitySettings()
        settings.apply(.services)
        XCTAssertFalse(settings.isModuleVisible(module("deliveries")))
        settings.deliveriesEnabled = true   // manual override
        XCTAssertTrue(settings.isModuleVisible(module("deliveries")))
    }

    func test_optional_modules_declare_their_capability_gate() {
        XCTAssertTrue(module("pos").requiresPOS)
        XCTAssertTrue(module("deliveries").requiresDeliveries)
        XCTAssertTrue(module("manufacturing").requiresManufacturing)
    }

    // MARK: - Seeder

    func test_seeder_default_chart_covers_posting_accounts() {
        let ids = Set(HubOnboardingSeeder.defaultAccounts.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["Cash", "Debtors", "Creditors", "Sales", "COGS", "VAT", "Stock"]))
    }

    func test_seeder_company_defaults_wire_every_posting_account() {
        let defaults = HubOnboardingSeeder.companyDefaults
        XCTAssertEqual(defaults["default_receivable_account"], "Debtors")
        XCTAssertEqual(defaults["default_payable_account"], "Creditors")
        XCTAssertEqual(defaults["default_income_account"], "Sales")
        XCTAssertEqual(defaults["default_vat_account"], "VAT")
        XCTAssertEqual(defaults["default_cash_bank_account"], "Cash")
        // Every wired account id exists in the seeded chart.
        let accountIds = Set(HubOnboardingSeeder.defaultAccounts.map(\.id))
        for (key, accountId) in defaults where key != "default_warehouse" {
            XCTAssertTrue(accountIds.contains(accountId), "\(accountId) must exist in the chart")
        }
    }

    func test_fiscal_year_bounds_span_the_calendar_year() {
        let bounds = HubOnboardingSeeder.fiscalYearBounds(year: 2026)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.month, from: bounds.start), 1)
        XCTAssertEqual(cal.component(.day, from: bounds.start), 1)
        XCTAssertEqual(cal.component(.month, from: bounds.end), 12)
        XCTAssertEqual(cal.component(.day, from: bounds.end), 31)
    }
}
