import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A context-aware "create new record" action published by the active
/// workspace via the focused-scene value below, so the File ▸ New menu
/// command (⌘N) targets whatever the user is currently looking at (e.g.
/// "New Customer" in the Customers workspace) and is disabled where there's
/// nothing to create (Home, reports, dashboards).
struct NewRecordAction {
    let label: String
    let perform: () -> Void
}

private struct NewRecordActionKey: FocusedValueKey {
    typealias Value = NewRecordAction
}

extension FocusedValues {
    var newRecordAction: NewRecordAction? {
        get { self[NewRecordActionKey.self] }
        set { self[NewRecordActionKey.self] = newValue }
    }
}

/// Focused, native macOS menu commands for Mercantis Hub.
///
/// Deliberately minimal: these mirror on-screen affordances and add keyboard
/// access — they do not introduce menu-only features. Wired into the app via
/// `.commands { HubCommands() }`.
struct HubCommands: Commands {
    @FocusedValue(\.newRecordAction) private var newRecordAction

    var body: some Commands {
        // File ▸ New <record> — replaces the stock "New" item with a
        // context-aware create that drives the active workspace.
        CommandGroup(replacing: .newItem) {
            Button(newRecordAction.map { "New \($0.label)" } ?? "New") {
                newRecordAction?.perform()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newRecordAction == nil)
        }

        #if os(macOS)
        // View ▸ Show/Hide Sidebar — native split-view toggle so the sidebar
        // has a keyboard path, not just the toolbar button.
        CommandGroup(replacing: .sidebar) {
            Button("Show/Hide Sidebar") {
                NSApp.keyWindow?.firstResponder?.tryToPerform(
                    #selector(NSSplitViewController.toggleSidebar(_:)),
                    with: nil
                )
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }
        #endif
    }
}
