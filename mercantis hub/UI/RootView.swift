import SwiftUI
import MercantisCore

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
                docTypeDetail(docType)
            case .report(_, let label):
                placeholder("\(label) — Reports not yet implemented")
            case .dashboard(_, let label):
                placeholder("\(label) — Dashboards not yet implemented")
            case .none:
                ContentUnavailableView(
                    "Select an item",
                    systemImage: "square.grid.2x2",
                    description: Text("Choose a record type, report or dashboard from the sidebar.")
                )
            }
        }
        .navigationTitle(selection?.label ?? "Mercantis Hub")
    }

    @ViewBuilder
    private func docTypeDetail(_ docType: DocType) -> some View {
        switch docType.id {
        case "Customer":
            CustomerFormView(engine: engine)
        default:
            placeholder("\(docType.name) — coming soon")
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
