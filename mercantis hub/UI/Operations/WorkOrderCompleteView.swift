import SwiftUI
import MercantisCore
import MercantisCoreUI

/// Shop-floor Work Order completion. Pick an in-progress Work Order, confirm
/// the produced quantity, and post its completion — which drives the
/// `Complete` workflow transition. `ManufacturingDerivationService` (wired at
/// app scope on the shared event bus) observes that `InProgress → Completed`
/// transition and posts the "Manufacturing" Stock Entry that consumes the
/// BOM-exploded raw materials and produces the finished good. We deliberately
/// reuse that real derivation rather than building a Stock Entry inline, so
/// completion behaves identically whether triggered here or from the record
/// workspace.
///
/// Ported from the Flutter `WorkOrderCompleteScreen`. The Flutter version built
/// the Stock Entry directly; the Swift Hub already owns that logic in
/// `ManufacturingDerivationService`, so this screen wires to it via the
/// workflow engine.
struct WorkOrderCompleteView: View {
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine

    @State private var workOrders: [Document] = []
    @State private var selectedId: String?
    @State private var producedQty: String = ""
    @State private var resultMessage: String?
    @State private var errorMessage: String?
    @State private var loaded = false

    private let evaluator = ExpressionEvaluator()

    private var selected: Document? {
        workOrders.first { $0.id == selectedId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MercantisPanelHeader("Complete Work Order", systemImage: "hammer")

                if workOrders.isEmpty {
                    emptyState
                } else {
                    picker
                    if let wo = selected {
                        details(for: wo)
                    }
                }

                if let resultMessage {
                    Label(resultMessage, systemImage: "checkmark.seal")
                        .font(.callout)
                        .foregroundStyle(MercantisTheme.success)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(MercantisTheme.danger)
                }
            }
            .padding(20)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MercantisTheme.appBackground)
        .onAppear(perform: reload)
    }

    private var emptyState: some View {
        Text(loaded
             ? "No work orders are in progress. Start a Work Order to complete it here."
             : "Loading…")
            .font(.callout)
            .foregroundStyle(MercantisTheme.textSecondary)
    }

    private var picker: some View {
        Picker("Work Order", selection: Binding(
            get: { selectedId ?? "" },
            set: { select($0.isEmpty ? nil : $0) }
        )) {
            Text("Select a work order…").tag("")
            ForEach(workOrders, id: \.id) { wo in
                Text("\(wo.id) · \(string(wo.fields["item"]) ?? "")").tag(wo.id)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func details(for wo: Document) -> some View {
        let required = wo.children["required_items"] ?? []
        VStack(alignment: .leading, spacing: 12) {
            Text("Producing: \(string(wo.fields["item"]) ?? "—")")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
            Text("From \(string(wo.fields["source_warehouse"]) ?? "—") → \(string(wo.fields["target_warehouse"]) ?? "—")")
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)

            if !required.isEmpty {
                Text("Raw materials to consume")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textSecondary)
                ForEach(Array(required.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(string(row.fields["item"]) ?? "—")
                            .foregroundStyle(MercantisTheme.textPrimary)
                        Spacer()
                        Text(formatQty(double(row.fields["required_qty"])))
                            .monospacedDigit()
                            .foregroundStyle(MercantisTheme.textSecondary)
                    }
                    .font(.callout)
                }
            }

            TextField("Produced quantity", text: $producedQty)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)

            Button(action: post) {
                Label("Post production", systemImage: "shippingbox.and.arrow.backward")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canComplete(wo))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MercantisTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MercantisTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func reload() {
        do {
            // Only Work Orders that can be completed: an "InProgress" status is
            // the precondition for the Complete transition. We still load all
            // and filter so the picker explains why a finished one is absent.
            let all = try engine.list(docType: "WorkOrder", applyRowAccess: false)
            workOrders = all.filter { $0.status == "InProgress" }
            loaded = true
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            loaded = true
        }
    }

    private func select(_ id: String?) {
        selectedId = id
        resultMessage = nil
        errorMessage = nil
        if let wo = workOrders.first(where: { $0.id == id }) {
            let qty = double(wo.fields["produced_qty"]) != 0
                ? double(wo.fields["produced_qty"])
                : double(wo.fields["qty_to_produce"])
            producedQty = formatQty(qty)
        } else {
            producedQty = ""
        }
    }

    private func canComplete(_ wo: Document) -> Bool {
        guard let qty = Double(producedQty.trimmingCharacters(in: .whitespaces)), qty > 0 else { return false }
        return wo.status == "InProgress"
    }

    private func post() {
        guard var wo = selected else { return }
        guard let qty = Double(producedQty.trimmingCharacters(in: .whitespaces)), qty > 0 else {
            errorMessage = "Enter a produced quantity."
            return
        }
        guard let workflow = HubWorkflows.workflow(forDocTypeId: "WorkOrder") else {
            errorMessage = "Work Order workflow is unavailable."
            return
        }
        do {
            // Record the actual produced qty before completing so the
            // derivation service's finished-good Stock Entry line uses it.
            wo.fields["produced_qty"] = .double(qty)
            wo = try engine.save(wo)

            // Drive the Complete transition. Entering "Completed" fires the
            // WorkflowTransitionEvent that ManufacturingDerivationService
            // listens for to post the Manufacturing Stock Entry.
            _ = try workflowEngine.transition(
                document: &wo,
                workflow: workflow,
                action: "Complete",
                userRoles: ["System Manager"],
                expressionEvaluator: evaluator,
                userId: HubIdentity.userId()
            )
            _ = try engine.save(wo)

            resultMessage = "Completed \(wo.id) — stock entry posted."
            errorMessage = nil
            reload()
            selectedId = nil
            producedQty = ""
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Coercion / formatting

    private func string(_ v: FieldValue?) -> String? {
        if case .string(let s) = v { return s.isEmpty ? nil : s }
        return nil
    }

    private func double(_ v: FieldValue?) -> Double {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return 0
        }
    }

    private func formatQty(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
