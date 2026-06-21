import MercantisCore
import MercantisCoreUI

/// Navigation surface for Document Capture (ADR-049). Defines the `Capture`
/// module's menu and the stable flow ids the host (RootView) routes to bespoke
/// SwiftUI screens — `CapturesView`, `ScanReceiptView`, `CaptureReviewView`,
/// `CaptureAISettingsView`.
///
/// This file only *declares* the module; the integrator adds `Capture.module`
/// to `HubNavigation.allModules` and routes the flow ids in `RootView`. See
/// `HUB_CAPTURE_WIRING.md`.
extension Capture {

    /// Stable nav ids used by `HubMenuItem.flow` and matched in `RootView`.
    enum Flow {
        static let captures   = "capture-list"
        static let scan       = "capture-scan"
        static let aiSettings = "capture-ai-settings"
        // `capture-review` is reached programmatically (with a capture id), not
        // from a menu item — the host pushes it after a scan or list selection.
        static let review     = "capture-review"
    }

    static let module = HubModule(
        id: "capture",
        label: "Capture",
        systemImage: "doc.text.viewfinder",
        tone: .buying,
        groups: [
            HubMenuGroup(label: "Document Capture", items: [
                .flow(id: Flow.captures, label: "Captures",
                      systemImage: "tray.full"),
                .flow(id: Flow.scan, label: "Scan Receipt",
                      systemImage: "doc.text.viewfinder")
            ]),
            HubMenuGroup(label: "Settings", items: [
                .flow(id: Flow.aiSettings, label: "Smart Capture (AI)",
                      systemImage: "sparkles")
            ], visibility: .advanced)
        ]
    )
}
