//
//  CustomerFormView.swift
//  mercantis hub
//
//  Prepared swap target for ContentView's hand-rolled save UI.
//
//  This file is gated behind `#if canImport(MercantisCoreUI)` so it stays
//  inert until Core ships the `MercantisCoreUI` library product (tracked
//  as P2.7 in mercantis.core.app — promote `UIShell/` out of the
//  `exclude:` list and expose `GenericFormView` / `GenericListView`).
//
//  Flip procedure once Core ships MercantisCoreUI:
//    1. Add `MercantisCoreUI` as a product dependency on the Hub app
//       target in Xcode (File → Add Package Dependencies… is already
//       resolved; just tick the new product).
//    2. In mercantis_hubApp.swift, swap
//         ContentView(engine: documentEngine)
//       for
//         CustomerFormView(engine: documentEngine)
//    3. Verify the GenericFormView init signature below against the
//       published API and adjust if needed — the shape here is the
//       expected pattern, not a contract.
//    4. Update Docs/HUB-ON-CORE-PROGRESS.md (Wall 1 → resolved).
//

import SwiftUI
import MercantisCore

#if canImport(MercantisCoreUI)
import MercantisCoreUI

struct CustomerFormView: View {
    let engine: DocumentEngine

    var body: some View {
        GenericFormView(docType: "Customer", engine: engine)
    }
}
#endif
