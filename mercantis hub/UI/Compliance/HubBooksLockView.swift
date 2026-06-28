import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Phase 3 — the books-lock control. Once a period is filed or finalised the
/// owner locks the books through a date so nothing dated on or before it can be
/// posted or changed by accident. Plain framing: "Lock everything up to…".
/// Enforced fail-closed in `PostingCoordinator`; this is just where the owner
/// sets or lifts the date.
struct HubBooksLockView: View {

    let engine: DocumentEngine

    @State private var lockEnabled = false
    @State private var lockDate = Date()
    @State private var savedLockDate: Date?
    @State private var message: String?
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusCard
                editCard
                if let message { banner(message, "checkmark.seal.fill", MercantisTheme.success) }
                if let error { banner(error, "exclamationmark.triangle.fill", MercantisTheme.danger) }
            }
            .padding(24)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .navigationTitle("Lock Books")
        .onAppear(perform: load)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lock your books").font(.title2).bold()
            Text("After you've filed a tax return or finished with a period, lock it. Nothing dated on or before the lock date can be posted or edited — so your filed figures stay put.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        MercantisInspectorCard("Current status", systemImage: savedLockDate == nil ? "lock.open" : "lock.fill") {
            if let savedLockDate {
                Text("Books are locked through \(savedLockDate.formatted(date: .long, time: .omitted)).")
                    .font(.callout)
            } else {
                Text("Books are open — nothing is locked.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var editCard: some View {
        MercantisInspectorCard("Set the lock", systemImage: "calendar.badge.clock") {
            Toggle("Lock the books up to a date", isOn: $lockEnabled)
                .toggleStyle(.switch)
            if lockEnabled {
                DatePicker("Lock everything up to", selection: $lockDate, displayedComponents: .date)
            }
            HStack {
                Spacer()
                if savedLockDate != nil {
                    Button("Clear lock") { clear() }
                        .buttonStyle(.bordered)
                }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Data

    private func load() {
        guard !loaded else { return }
        loaded = true
        let company = (try? engine.list(docType: "Company"))?.first
        if let date = dateField(company?.fields["books_lock_date"]) {
            savedLockDate = date
            lockDate = date
            lockEnabled = true
        }
    }

    private func save() {
        message = nil; error = nil
        guard var company = (try? engine.list(docType: "Company"))?.first else {
            error = "Set up your Business Profile first."
            return
        }
        if lockEnabled {
            company.fields["books_lock_date"] = .date(lockDate)
        } else {
            company.fields["books_lock_date"] = .null
        }
        guard (try? engine.save(company)) != nil else {
            error = "Couldn't save the lock date."
            return
        }
        savedLockDate = lockEnabled ? lockDate : nil
        message = lockEnabled
            ? "Books locked through \(lockDate.formatted(date: .abbreviated, time: .omitted))."
            : "Lock removed — your books are open again."
    }

    private func clear() {
        lockEnabled = false
        save()
    }

    // MARK: - Helpers

    private func banner(_ text: String, _ system: String, _ tone: Color) -> some View {
        Label(text, systemImage: system)
            .font(.callout).foregroundStyle(tone)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func dateField(_ value: FieldValue?) -> Date? {
        switch value { case .date(let d), .dateTime(let d): return d; default: return nil }
    }
}
