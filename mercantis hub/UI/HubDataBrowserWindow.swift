import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Developer ▸ Data Browser window. Gated to the System Manager role and wired
/// to the engine's guarded, read-only query runner — so it can inspect any
/// table but never mutate data.
struct HubDataBrowserWindowView: View {
    let engine: DocumentEngine

    @Environment(\.operatorRoles) private var operatorRoles
    private var authorized: Bool { operatorRoles.contains("System Manager") }

    var body: some View {
        Group {
            if authorized {
                DataBrowserView(runQuery: { try await engine.runReadOnlyQueryAsync($0) })
            } else {
                ContentUnavailableView(
                    "Restricted",
                    systemImage: "lock",
                    description: Text("The Data Browser is available to System Managers only.")
                )
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}
