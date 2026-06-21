import SwiftUI
import MercantisCore
import MercantisCoreUI

/// A row in the captures review queue, projected from a Captured Document.
struct CaptureRow: Identifiable, Hashable {
    let id: String
    let merchant: String
    let date: String
    let amount: String
    let confidence: Int
    let status: String

    var isOpen: Bool { Capture.openStatuses.contains(status) }
}

/// The Document Capture review queue (ADR-049): captures visible to this
/// operator (role-filtered), open ones first. Select to review; toolbar to
/// scan and to open AI settings. Port of the Flutter `CapturesScreen`.
struct CapturesView: View {
    let engine: DocumentEngine
    let userRoles: Set<String>
    /// Navigation hooks supplied by the host (RootView).
    let onScan: () -> Void
    let onOpenAISettings: () -> Void
    let onReview: (String) -> Void

    @State private var rows: [CaptureRow] = []
    @State private var loaded = false

    private var openRows: [CaptureRow] { rows.filter(\.isOpen) }
    private var doneRows: [CaptureRow] { rows.filter { !$0.isOpen } }

    var body: some View {
        Group {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                emptyState
            } else {
                List {
                    if !openRows.isEmpty {
                        Section("Needs your attention") {
                            ForEach(openRows) { row(for: $0) }
                        }
                    }
                    if !doneRows.isEmpty {
                        Section("Processed") {
                            ForEach(doneRows) { row(for: $0) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(MercantisTheme.appBackground)
        .navigationTitle("Captures")
        .toolbar {
            ToolbarItemGroup {
                Button { onOpenAISettings() } label: {
                    Label("Smart capture (AI)", systemImage: "sparkles")
                }
                Button { onScan() } label: {
                    Label("Scan", systemImage: "doc.text.viewfinder")
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func row(for r: CaptureRow) -> some View {
        Button { onReview(r.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: "receipt")
                    .foregroundStyle(MercantisTheme.brandPrimary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.merchant.isEmpty ? "(no merchant)" : r.merchant)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MercantisTheme.textPrimary)
                    let subtitle = [r.date.isEmpty ? nil : r.date,
                                    r.confidence > 0 ? "\(r.confidence)% read" : nil]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 11))
                            .foregroundStyle(MercantisTheme.textTertiary)
                    }
                }
                Spacer()
                if !r.amount.isEmpty {
                    Text(r.amount).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(MercantisTheme.textPrimary)
                }
                statusChip(r.status)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ status: String) -> some View {
        let color: Color
        switch status {
        case Capture.statusReady:        color = .green
        case Capture.statusNeedsReview:  color = .orange
        case Capture.statusDraftCreated: color = MercantisTheme.brandPrimary
        default:                         color = MercantisTheme.textTertiary
        }
        return Text(status)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var emptyState: some View {
        MercantisEmptyState(
            systemImage: "doc.text.magnifyingglass",
            title: "No receipts captured yet",
            message: "Scan a receipt or bill and it lands here."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        let docs = (try? engine.list(docType: "Captured Document",
                                     sortBy: [ListSort(fieldKey: "updatedAt", direction: .descending)],
                                     userRoles: userRoles)) ?? []
        rows = docs.compactMap { doc in
            let intendedRole = CaptureService.nonEmpty(doc.fields["intended_role"])
            guard Capture.visibleToRole(intendedRole, userRoles: userRoles) else { return nil }
            let status = CaptureService.nonEmpty(doc.fields["status"]) ?? Capture.statusReceived
            let amount: String
            if let g = CaptureService.doubleValue(doc.fields["grand_total"]) {
                amount = String(format: "%.2f", g)
            } else {
                amount = ""
            }
            let conf = CaptureService.intValue(doc.fields["extraction_confidence"]) ?? 0
            return CaptureRow(
                id: doc.id,
                merchant: CaptureService.nonEmpty(doc.fields["merchant_name"]) ?? "",
                date: CaptureService.nonEmpty(doc.fields["document_date"]) ?? "",
                amount: amount,
                confidence: conf,
                status: status
            )
        }
        loaded = true
    }
}
