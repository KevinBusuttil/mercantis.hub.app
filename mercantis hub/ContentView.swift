//
//  ContentView.swift
//  mercantis hub
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI
import MercantisCore

struct ContentView: View {
    let engine: DocumentEngine

    @State private var customerName: String = ""
    @State private var lastSavedID: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Mercantis Hub")
                .font(.title)
                .fontWeight(.semibold)

            TextField("Customer name", text: $customerName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Button("Save Customer") { save() }
                .disabled(customerName.trimmingCharacters(in: .whitespaces).isEmpty)

            if let id = lastSavedID {
                Text("Saved as \(id)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error = errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 240)
    }

    private func save() {
        let now = Date()
        let doc = Document(
            id: "",
            docType: "Customer",
            company: "Default Company",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: ["customer_name": .string(customerName)],
            children: [:]
        )

        do {
            let saved = try engine.save(doc)
            lastSavedID = saved.id
            errorMessage = nil
            customerName = ""
        } catch {
            errorMessage = String(describing: error)
            lastSavedID = nil
        }
    }
}
