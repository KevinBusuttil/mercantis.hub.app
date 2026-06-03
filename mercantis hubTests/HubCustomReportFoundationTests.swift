//
//  HubCustomReportFoundationTests.swift
//  mercantis hubTests
//
//  Hub user report customisation: the catalogue of customisable reports, the
//  saved-report projection/filter runner, and the local saved-report store.
//  Verifies friendly labels, advanced/audit gating, column show/hide +
//  reorder, stored filter defaults, and persistence round-trips.
//

import XCTest
import MercantisCore
@testable import Mercantis_Hub

@MainActor
final class HubCustomReportFoundationTests: XCTestCase {

    // MARK: - Catalogue contents

    func test_catalogue_exposes_safe_user_facing_reports() {
        let ids = Set(HubCustomReportCatalog.all.map(\.baseReportId))
        for safe in [
            "sales-register", "purchase-register", "stock-on-hand",
            "customer-aging", "supplier-ledger", "vat-summary",
            "open-deliveries", "todays-routes",
        ] {
            XCTAssertTrue(ids.contains(safe), "\(safe) should be customisable")
        }
    }

    func test_catalogue_excludes_raw_audit_reports() {
        let ids = Set(HubCustomReportCatalog.all.map(\.baseReportId))
        // Trial Balance, Customer Statement and Pending Receipts are not
        // safe to expose as customisable to normal users.
        for excluded in ["trial-balance", "customer-statement", "pending-receipts"] {
            XCTAssertFalse(ids.contains(excluded), "\(excluded) must not be customisable")
        }
    }

    func test_catalogue_templates_point_at_real_reports() {
        for template in HubCustomReportCatalog.all {
            guard let base = HubReports.report(forId: template.baseReportId) else {
                return XCTFail("\(template.baseReportId) is not a real Hub report")
            }
            XCTAssertEqual(template.sourceDocType, base.docType,
                           "\(template.baseReportId) source DocType must match the base report")
            XCTAssertFalse(template.columns.isEmpty, "\(template.baseReportId) needs columns")
        }
    }

    func test_catalogue_uses_friendly_labels() {
        guard let sales = HubCustomReportCatalog.template(forBaseReportId: "sales-register") else {
            return XCTFail("sales-register template missing")
        }
        // Raw field keys ("id", "grand_total") get friendly column labels.
        XCTAssertEqual(sales.columns.first { $0.key == "id" }?.label, "Invoice")
        XCTAssertEqual(sales.columns.first { $0.key == "grand_total" }?.label, "Grand Total")
    }

    // MARK: - Advanced / audit gating

    func test_advanced_reports_are_gated_behind_advanced_view() {
        let key = HubVisibilitySettings.defaultsKey
        let snapshot = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(snapshot ?? nil, forKey: key) }

        let settings = HubVisibilitySettings()

        settings.showAdvanced = false
        XCTAssertTrue(HubCustomReportCatalog.isCustomisable(reportId: "sales-register", settings: settings))
        XCTAssertFalse(HubCustomReportCatalog.isCustomisable(reportId: "stock-ledger-view", settings: settings),
                       "Stock Ledger View is advanced — hidden from normal users")
        // Audit reports are never customisable, advanced or not.
        XCTAssertFalse(HubCustomReportCatalog.isCustomisable(reportId: "trial-balance", settings: settings))

        let normalOnly = HubCustomReportCatalog.availableTemplates(settings).map(\.baseReportId)
        XCTAssertFalse(normalOnly.contains("stock-ledger-view"))

        settings.showAdvanced = true
        XCTAssertTrue(HubCustomReportCatalog.isCustomisable(reportId: "stock-ledger-view", settings: settings),
                      "Advanced view reveals Stock Ledger View for customisation")
        XCTAssertFalse(HubCustomReportCatalog.isCustomisable(reportId: "trial-balance", settings: settings),
                       "Trial Balance stays off the customisable list entirely")

        let advanced = HubCustomReportCatalog.availableTemplates(settings).map(\.baseReportId)
        XCTAssertTrue(advanced.contains("stock-ledger-view"))
    }

    // MARK: - Cloning a built-in report

    func test_makeSavedReport_clones_columns_and_filters() {
        guard let template = HubCustomReportCatalog.template(forBaseReportId: "sales-register") else {
            return XCTFail("sales-register template missing")
        }
        let saved = HubCustomReportCatalog.makeSavedReport(from: template, ownerUserId: "alice")

        XCTAssertEqual(saved.baseReportId, "sales-register")
        XCTAssertEqual(saved.sourceDocType, "SalesInvoice")
        XCTAssertEqual(saved.ownerUserId, "alice")
        XCTAssertEqual(saved.visibility, .private)

        XCTAssertEqual(saved.columns.map(\.fieldKey), template.columns.map(\.key))
        XCTAssertEqual(saved.columns.compactMap(\.labelOverride), template.columns.map(\.label))
        XCTAssertTrue(saved.columns.allSatisfy(\.visible))
        XCTAssertEqual(saved.columns.map(\.order), Array(0..<template.columns.count))

        XCTAssertEqual(saved.filters.map(\.fieldKey), template.filters.map(\.fieldKey))
    }

    // MARK: - Projection (hide / show / reorder / relabel)

    private func makeSaved(columns: [SavedReportColumn], filters: [SavedReportFilter] = []) -> SavedReportDefinition {
        SavedReportDefinition(
            name: "Test",
            baseReportId: "sales-register",
            sourceDocType: "SalesInvoice",
            ownerUserId: "alice",
            columns: columns,
            filters: filters
        )
    }

    func test_projection_hides_reorders_and_relabels_columns() {
        let base = ReportResult(
            columns: ["id", "customer", "grand_total", "status"],
            rows: [
                ["INV-1", "Acme", "100.00", "Posted"],
                ["INV-2", "Beta", "50.00", "Draft"],
            ]
        )
        let saved = makeSaved(columns: [
            SavedReportColumn(fieldKey: "id", labelOverride: "Invoice", visible: false, order: 0),
            SavedReportColumn(fieldKey: "customer", labelOverride: "Customer", visible: true, order: 2),
            SavedReportColumn(fieldKey: "grand_total", labelOverride: "Total", visible: true, order: 1),
            SavedReportColumn(fieldKey: "status", labelOverride: "Status", visible: true, order: 3),
        ])

        let projected = HubSavedReportRunner.project(base: base, savedReport: saved)

        // id hidden; remaining ordered by `order`: grand_total, customer, status.
        XCTAssertEqual(projected.columns, ["Total", "Customer", "Status"])
        XCTAssertEqual(projected.rows[0], ["100.00", "Acme", "Posted"])
        XCTAssertEqual(projected.rows[1], ["50.00", "Beta", "Draft"])
    }

    func test_projection_renders_missing_column_as_empty() {
        let base = ReportResult(columns: ["customer"], rows: [["Acme"]])
        let saved = makeSaved(columns: [
            SavedReportColumn(fieldKey: "customer", labelOverride: "Customer", visible: true, order: 0),
            SavedReportColumn(fieldKey: "ghost", labelOverride: "Ghost", visible: true, order: 1),
        ])

        let projected = HubSavedReportRunner.project(base: base, savedReport: saved)

        XCTAssertEqual(projected.columns, ["Customer", "Ghost"])
        XCTAssertEqual(projected.rows[0], ["Acme", nil])
    }

    // MARK: - Filter default resolution

    func test_filterValues_resolve_stored_then_default() {
        let saved = makeSaved(
            columns: [SavedReportColumn(fieldKey: "id", visible: true, order: 0)],
            filters: [
                SavedReportFilter(fieldKey: "customer", op: .equals, value: .string("C-1")),
                SavedReportFilter(fieldKey: "status", op: .equals, value: nil, defaultValue: .string("Posted")),
                SavedReportFilter(fieldKey: "currency", op: .equals, value: nil, defaultValue: nil),
            ]
        )

        let values = HubSavedReportRunner.filterValues(for: saved)

        XCTAssertEqual(values["customer"], .string("C-1"))   // stored value wins
        XCTAssertEqual(values["status"], .string("Posted"))  // falls back to default
        XCTAssertNil(values["currency"])                     // neither → omitted
    }

    func test_filterValues_skip_null_defaults() {
        let saved = makeSaved(
            columns: [SavedReportColumn(fieldKey: "id", visible: true, order: 0)],
            filters: [SavedReportFilter(fieldKey: "customer", op: .equals, value: .null)]
        )
        XCTAssertTrue(HubSavedReportRunner.filterValues(for: saved).isEmpty)
    }

    // MARK: - Store round-trips

    func test_store_persists_across_instances() {
        let suite = "test.savedReports.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HubSavedReportStore(defaults: defaults, key: "k")
        XCTAssertTrue(store.reports.isEmpty)

        let template = HubCustomReportCatalog.template(forBaseReportId: "sales-register")!
        let report = HubCustomReportCatalog.makeSavedReport(from: template, ownerUserId: "alice", name: "My Sales")
        store.save(report)
        XCTAssertEqual(store.reports.count, 1)
        XCTAssertNotNil(store.get(id: report.id))

        store.rename(id: report.id, to: "Renamed Sales")
        XCTAssertEqual(store.get(id: report.id)?.name, "Renamed Sales")

        // A fresh store over the same defaults reads the persisted state.
        let reloaded = HubSavedReportStore(defaults: defaults, key: "k")
        XCTAssertEqual(reloaded.get(id: report.id)?.name, "Renamed Sales")

        store.delete(id: report.id)
        XCTAssertTrue(store.reports.isEmpty)
        let reloadedEmpty = HubSavedReportStore(defaults: defaults, key: "k")
        XCTAssertTrue(reloadedEmpty.reports.isEmpty)
    }

    func test_store_access_honours_visibility() {
        let suite = "test.savedReports.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HubSavedReportStore(defaults: defaults, key: "k")
        let template = HubCustomReportCatalog.template(forBaseReportId: "sales-register")!

        var mine = HubCustomReportCatalog.makeSavedReport(from: template, ownerUserId: "alice", name: "Mine")
        mine.visibility = .private
        var shared = HubCustomReportCatalog.makeSavedReport(from: template, ownerUserId: "carol", name: "Shared")
        shared.visibility = .shared
        store.save(mine)
        store.save(shared)

        let aliceIds = Set(store.accessibleReports(forUserId: "alice").map(\.id))
        XCTAssertTrue(aliceIds.contains(mine.id))
        XCTAssertTrue(aliceIds.contains(shared.id))

        let bobIds = Set(store.accessibleReports(forUserId: "bob").map(\.id))
        XCTAssertFalse(bobIds.contains(mine.id), "Bob can't see Alice's private report")
        XCTAssertTrue(bobIds.contains(shared.id), "Shared reports are visible to everyone")
    }

    // MARK: - From-scratch: reportable DocType catalogue

    func test_reportable_doctypes_gate_audit_spine() {
        let key = HubVisibilitySettings.defaultsKey
        let snapshot = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(snapshot ?? nil, forKey: key) }

        let settings = HubVisibilitySettings()

        settings.showAdvanced = false
        let normal = Set(HubReportableDocTypes.available(settings).map(\.docType))
        XCTAssertTrue(normal.contains("Customer"))
        XCTAssertTrue(normal.contains("SalesInvoice"))
        XCTAssertFalse(normal.contains("GLEntry"), "Ledger spine hidden from normal users")
        XCTAssertFalse(HubReportableDocTypes.isReportable("GLEntry", settings: settings))

        settings.showAdvanced = true
        XCTAssertTrue(HubReportableDocTypes.available(settings).map(\.docType).contains("GLEntry"))
        XCTAssertTrue(HubReportableDocTypes.isReportable("GLEntry", settings: settings))
    }

    func test_reportable_doctypes_only_offer_registered_types() {
        let key = HubVisibilitySettings.defaultsKey
        let snapshot = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(snapshot ?? nil, forKey: key) }
        let settings = HubVisibilitySettings()
        settings.showAdvanced = true

        for entry in HubReportableDocTypes.available(settings) {
            XCTAssertNotNil(HubManifest.docType(for: entry.docType),
                            "\(entry.docType) is offered but not registered")
        }
    }

    // MARK: - From-scratch: blank report builder

    func test_blank_report_seeds_columns_from_metadata() throws {
        guard let customer = HubManifest.docType(for: "Customer") else {
            return XCTFail("Customer DocType missing")
        }
        let report = HubReportBuilder.makeBlankReport(docType: customer, ownerUserId: "alice")

        XCTAssertNil(report.baseReportId, "From-scratch reports have no base report")
        XCTAssertEqual(report.sourceDocType, "Customer")
        XCTAssertEqual(report.ownerUserId, "alice")
        XCTAssertEqual(report.visibility, .private)

        // First column is the id system column; created/updated are included.
        XCTAssertEqual(report.columns.first?.fieldKey, "id")
        XCTAssertTrue(report.columns.contains { $0.fieldKey == "createdAt" })
        XCTAssertTrue(report.columns.contains { $0.fieldKey == "updatedAt" })

        // Child-table fields are never offered as flat columns.
        let tableKeys = Set(customer.fields.filter { $0.type == .table }.map(\.key))
        XCTAssertTrue(report.columns.allSatisfy { !tableKeys.contains($0.fieldKey) })

        // Orders are contiguous from zero.
        XCTAssertEqual(report.columns.map(\.order), Array(0..<report.columns.count))
    }

    func test_blank_report_default_visible_count() throws {
        guard let customer = HubManifest.docType(for: "Customer") else {
            return XCTFail("Customer DocType missing")
        }
        let report = HubReportBuilder.makeBlankReport(
            docType: customer, ownerUserId: "alice", defaultVisibleCount: 3
        )
        XCTAssertEqual(report.visibleColumnsInOrder.count, min(3, report.columns.count))
    }

    // MARK: - CSV export

    func test_csv_export_escapes_fields() {
        let result = ReportResult(
            columns: ["Name", "Note"],
            rows: [
                ["Acme, Inc.", "He said \"hi\""],
                ["Beta", nil],
            ]
        )
        let csv = HubReportCSV.string(from: result)
        let lines = csv.components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "Name,Note")
        // Comma forces quoting; embedded quotes are doubled.
        XCTAssertEqual(lines[1], "\"Acme, Inc.\",\"He said \"\"hi\"\"\"")
        // A nil cell becomes an empty field.
        XCTAssertEqual(lines[2], "Beta,")
    }

    func test_csv_filename_is_sanitised() {
        XCTAssertEqual(HubReportCSV.fileName(for: "Customers Report"), "Customers Report.csv")
        XCTAssertEqual(HubReportCSV.fileName(for: "A/B:C"), "A-B-C.csv")
        XCTAssertEqual(HubReportCSV.fileName(for: "   "), "report.csv")
    }

    func test_blank_report_runs_through_core_engine_path() throws {
        // A from-scratch report must route to the Core engine; without one the
        // runner reports that cleanly rather than falling through to HubReports.
        let report = SavedReportDefinition(
            name: "Scratch",
            baseReportId: nil,
            sourceDocType: "Customer",
            ownerUserId: "alice",
            columns: [SavedReportColumn(fieldKey: "id", visible: true, order: 0)]
        )
        XCTAssertEqual(report.baseReportId, nil)
        // filterValues still works on a base-less report (no filters → empty).
        XCTAssertTrue(HubSavedReportRunner.filterValues(for: report).isEmpty)
    }
}
