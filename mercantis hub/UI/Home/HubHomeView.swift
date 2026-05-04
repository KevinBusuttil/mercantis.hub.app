import SwiftUI
import MercantisCore

/// Default landing page for Mercantis Hub.
///
/// Shown when no sidebar item is selected. Per `Docs/HUB-UX-DIRECTION.md` §4.3,
/// this view must stay honest about the early-stage status of the app:
/// modules that are stubs say so, and there are no fabricated metrics or
/// populated dashboard tiles. The intent is to onboard, not to oversell.
struct HubHomeView: View {
    let engine: DocumentEngine
    let onSelect: (HubMenuItem) -> Void

    @State private var recentRecords: [RecentRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                welcomeHeader
                quickActions
                recentSection
                moduleStatusSection
                setupSection
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: loadRecentRecords)
    }

    // MARK: - Welcome

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(HubManifest.appName)
                    .font(.largeTitle.weight(.semibold))
                Text("v\(HubManifest.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("First-party ERP built on Mercantis Core. Many modules are still under construction — this home view shows what works today and what is coming.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 760, alignment: .leading)
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Quick Actions")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(quickActionDocTypes, id: \.id) { docType in
                    Button {
                        onSelect(.docType(docType))
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New \(docType.name)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(docType.module)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.separator, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickActionDocTypes: [DocType] {
        // Limit to a small set so the home view stays focused.
        Array(HubManifest.allDocTypes.prefix(6))
    }

    // MARK: - Recents

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Recent Records")
            if recentRecords.isEmpty {
                ContentUnavailableView(
                    "No records yet",
                    systemImage: "clock",
                    description: Text("Records you create will appear here, sorted by most recently modified.")
                )
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(recentRecords) { entry in
                        Button {
                            if let docType = HubManifest.docType(for: entry.docTypeID) {
                                onSelect(.docType(docType))
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(entry.docTypeName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(entry.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Module status

    private var moduleStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Module Status")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(moduleStatuses, id: \.module.id) { entry in
                    moduleStatusCard(entry)
                }
            }
        }
    }

    private struct ModuleStatus {
        let module: HubModule
        let docTypeCount: Int
        let reportCount: Int
        let dashboardCount: Int

        var headline: String {
            if docTypeCount == 0 && reportCount == 0 && dashboardCount == 0 {
                return "Planned — not yet wired"
            }
            var parts: [String] = []
            if docTypeCount > 0 { parts.append("\(docTypeCount) DocType\(docTypeCount == 1 ? "" : "s")") }
            if reportCount > 0 { parts.append("\(reportCount) report\(reportCount == 1 ? "" : "s")") }
            if dashboardCount > 0 { parts.append("\(dashboardCount) dashboard\(dashboardCount == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }

        var coming: String {
            if docTypeCount == 0 {
                return "DocTypes will land as Core walls clear (see Docs/HUB-STATUS.md)."
            }
            if reportCount == 0 && dashboardCount == 0 {
                return "Reports and dashboards arrive once Core ships GenericReportView / GenericDashboardView (Core Phase UX-4)."
            }
            return "Workspace polish lands with Hub Phase HUX-5."
        }
    }

    private var moduleStatuses: [ModuleStatus] {
        HubNavigation.allModules.map { module in
            var docCount = 0
            var reportCount = 0
            var dashboardCount = 0
            for group in module.groups {
                for item in group.items {
                    switch item {
                    case .docType: docCount += 1
                    case .report: reportCount += 1
                    case .dashboard: dashboardCount += 1
                    }
                }
            }
            return ModuleStatus(
                module: module,
                docTypeCount: docCount,
                reportCount: reportCount,
                dashboardCount: dashboardCount
            )
        }
    }

    private func moduleStatusCard(_ entry: ModuleStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: entry.module.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(entry.module.label)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Text(entry.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.coming)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        )
    }

    // MARK: - Setup

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Setup")
            ContentUnavailableView(
                "Onboarding checklist coming soon",
                systemImage: "checklist",
                description: Text("A guided checklist (Company, Fiscal Year, Currency) will appear here once those Setup DocTypes are declared. Tracked under Hub Phase HUX-3.")
            )
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator, lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers

    private func sectionHeading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private struct RecentRecord: Identifiable {
        let id: String
        let title: String
        let docTypeID: String
        let docTypeName: String
        let updatedAt: Date
    }

    private func loadRecentRecords() {
        var collected: [RecentRecord] = []
        for docType in HubManifest.allDocTypes {
            let documents = (try? engine.list(docType: docType.id)) ?? []
            for doc in documents {
                let title = displayTitle(for: doc, docType: docType)
                collected.append(
                    RecentRecord(
                        id: "\(docType.id):\(doc.id)",
                        title: title,
                        docTypeID: docType.id,
                        docTypeName: docType.name,
                        updatedAt: doc.updatedAt
                    )
                )
            }
        }
        recentRecords = Array(
            collected
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(8)
        )
    }

    private func displayTitle(for document: Document, docType: DocType) -> String {
        if case let .string(value)? = document.fields[docType.titleField], !value.isEmpty {
            return value
        }
        if !document.id.isEmpty {
            return document.id
        }
        return "Untitled \(docType.name)"
    }
}
