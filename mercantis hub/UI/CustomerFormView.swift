import SwiftUI
import MercantisCore
import MercantisCoreUI

struct CustomerFormView: View {
    let engine: DocumentEngine

    @State private var document: Document = CustomerFormView.makeBlankCustomer()
    @State private var lastSavedID: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            GenericFormView(docType: CRM.customer, document: $document)

            Button("Save Customer") { save() }

            if let id = lastSavedID {
                Text("Saved as \(id)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = errorMessage {
                Text(error).font(.callout).foregroundStyle(MercantisTheme.danger)
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
            document = CustomerFormView.makeBlankCustomer()
        } catch {
            errorMessage = String(describing: error)
            lastSavedID = nil
        }
    }

    private static func makeBlankCustomer() -> Document {
        let now = Date()
        return Document(
            id: "",
            docType: "Customer",
            company: "Default Company",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [:],
            children: [:]
        )
    }
}
