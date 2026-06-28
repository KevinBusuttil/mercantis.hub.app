import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Phase 4 (Accounting Autopilot) — guards for business-type accounting presets
/// and the Owner / Accountant mode façade.
@MainActor
final class BusinessPresetTests: XCTestCase {

    // MARK: - Preset accounting tailoring

    func test_default_income_account_is_service_for_service_businesses() {
        XCTAssertEqual(HubPreset.services.defaultIncomeAccountId, "ServiceIncome")
        XCTAssertEqual(HubPreset.consultant.defaultIncomeAccountId, "ServiceIncome")
        XCTAssertEqual(HubPreset.retailPOS.defaultIncomeAccountId, "Sales")
        XCTAssertEqual(HubPreset.tradeDistribution.defaultIncomeAccountId, "Sales")
        XCTAssertEqual(HubPreset.lightManufacturing.defaultIncomeAccountId, "Sales")
    }

    func test_tracks_inventory_only_for_goods_businesses() {
        XCTAssertFalse(HubPreset.services.tracksInventory)
        XCTAssertFalse(HubPreset.consultant.tracksInventory)
        XCTAssertTrue(HubPreset.retailPOS.tracksInventory)
        XCTAssertTrue(HubPreset.tradeDistribution.tracksInventory)
        XCTAssertTrue(HubPreset.lightManufacturing.tracksInventory)
    }

    func test_every_preset_default_income_account_exists_in_the_chart() {
        let chartIds = Set(HubCOATemplateLibrary.accounts(taxStyle: .vat).map(\.id))
        for preset in HubPreset.allCases {
            XCTAssertTrue(chartIds.contains(preset.defaultIncomeAccountId),
                          "\(preset.rawValue) default income account \(preset.defaultIncomeAccountId) must exist in the seeded chart")
        }
    }

    func test_company_records_business_type() {
        let company = HubManifest.docType(for: "Company")
        XCTAssertTrue(Set(company?.fields.map(\.key) ?? []).contains("business_type"),
                      "Company must store the chosen business type")
    }

    // MARK: - Owner / Accountant mode façade

    func test_user_mode_is_a_facade_over_showAdvanced() {
        let settings = HubVisibilitySettings()

        settings.showAdvanced = false
        XCTAssertEqual(settings.userMode, .owner)
        XCTAssertFalse(settings.isVisible(.advanced))
        XCTAssertTrue(settings.isVisible(.normal))   // everyday surface always shows

        settings.userMode = .accountant
        XCTAssertTrue(settings.showAdvanced)
        XCTAssertTrue(settings.isVisible(.advanced))

        settings.userMode = .owner
        XCTAssertFalse(settings.showAdvanced)
        XCTAssertFalse(settings.isVisible(.advanced))
    }

    func test_user_mode_has_two_cases() {
        XCTAssertEqual(HubUserMode.allCases.count, 2)
        XCTAssertEqual(HubUserMode.owner.title, "Owner")
        XCTAssertEqual(HubUserMode.accountant.title, "Accountant")
    }
}
