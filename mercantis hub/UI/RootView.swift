import SwiftUI
import MercantisCore
import MercantisCoreUI

struct RootView: View {
    let engine: DocumentEngine

    @State private var selection: HubMenuItem?
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(HubNavigation.allModules) { module in
                Section {
                    ForEach(module.groups.indices, id: \.self) { gIdx in
                        let group = module.groups[gIdx]
                        let key = "\(module.id)::\(gIdx)"
                        if let label = group.label {
                            groupHeader(label: label, key: key)
                        }
                        if group.label == nil || !collapsedGroups.contains(key) {
                            ForEach(group.items, id: \.self) { item in
                                Label(item.label, systemImage: item.systemImage)
                            }
                        }
                    }
                } header: {
                    Label(module.label, systemImage: module.systemImage)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mercantis Hub")
        .frame(minWidth: 220)
    }

    private func groupHeader(label: String, key: String) -> some View {
        let isCollapsed = collapsedGroups.contains(key)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if isCollapsed {
                    collapsedGroups.remove(key)
                } else {
                    collapsedGroups.insert(key)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch selection {
            case .docType(let docType):
                HubDocTypeView(docType: docType, engine: engine)
            case .report(_, let label):
                reportPlaceholder(label: label)
            case .dashboard(_, let label):
                dashboardPlaceholder(label: label)
            case .none:
                HubHomeView(engine: engine) { item in
                    selection = item
                }
            }
        }
        .navigationTitle(selection?.label ?? "Mercantis Hub")
    }

    private func reportPlaceholder(label: String) -> some View {
        ContentUnavailableView(
            label,
            systemImage: "chart.bar.doc.horizontal",
            description: Text("Report rendering arrives when Core ships GenericReportView (Core Phase UX-4). Until then this view stays a placeholder rather than a stubbed table.")
        )
    }

    private func dashboardPlaceholder(label: String) -> some View {
        ContentUnavailableView(
            label,
            systemImage: "rectangle.grid.2x2",
            description: Text("Dashboards arrive when Core ships GenericDashboardView (Core Phase UX-4). The widget definitions for this dashboard are tracked in HubDashboards.swift.")
        )
    }
}

private struct HubDocTypeView: View {
    let docType: DocType
    let engine: DocumentEngine

    @State private var document: Document
    @State private var lastSavedID: String?
    @State private var errorMessage: String?

    init(docType: DocType, engine: DocumentEngine) {
        self.docType = docType
        self.engine = engine
        let now = Date()
        self._document = State(initialValue: Document(
            id: "",
            docType: docType.id,
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [:],
            children: [:]
        ))
    }

    var body: some View {
        VStack(spacing: 16) {
            GenericFormView(
                docType: docType,
                document: $document,
                linkSearchProvider: { targetDocType, _ in
                    (try? engine.list(docType: targetDocType)) ?? []
                },
                childDocTypeProvider: { HubManifest.docType(for: $0) }
            )
            Button("Save \(docType.name)") { save() }
            if let id = lastSavedID {
                Text("Saved as \(id)").font(.callout).foregroundStyle(.secondary)
            }
            if let error = errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 320)
    }

    private func save() {
        do {
            let saved = try engine.save(document)
            lastSavedID = saved.id
            errorMessage = nil
            let now = Date()
            document = Document(
                id: "",
                docType: docType.id,
                company: "",
                status: "",
                createdAt: now,
                updatedAt: now,
                syncVersion: 0,
                syncState: .local,
                fields: [:],
                children: [:]
            )
        } catch {
            errorMessage = String(describing: error)
            lastSavedID = nil
        }
    }
}
