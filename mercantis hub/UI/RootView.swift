import SwiftUI
import MercantisCore

struct RootView: View {
    let engine: DocumentEngine

    @State private var selection: HubMenuItem?

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
                    ForEach(module.groups.indices, id: \.self) { idx in
                        groupView(module.groups[idx])
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

    @ViewBuilder
    private func groupView(_ group: HubMenuGroup) -> some View {
        if let label = group.label {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        ForEach(group.items) { item in
            Label(item.label, systemImage: item.systemImage)
                .tag(item as HubMenuItem?)
        }
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
