import SwiftUI
import MercantisCore
import MercantisCoreUI

/// A dedicated editor view for single-record / settings-style DocTypes.
///
/// Instead of showing a list or browse layout, this view renders a scrollable
/// form editor directly for the one settings record. It handles both the
/// initial creation flow (unsaved draft) and subsequent edits of the existing
/// record, including save feedback.
struct SingleRecordSettingsEditor: View {
    let docType: DocType
    let engine: DocumentEngine
    let workflowEngine: WorkflowEngine
    let customFieldStore: CustomFieldStore
    let initialDocument: Document
    let copy: HubWorkspaceCopy
    let onReload: () -> Void

    @State private var document: Document
    @State private var customFields: [CustomField] = []
    @State private var errorMessage: String?
    @State private var showSavedConfirmation = false

    init(docType: DocType, engine: DocumentEngine, workflowEngine: WorkflowEngine,
         customFieldStore: CustomFieldStore, initialDocument: Document,
         copy: HubWorkspaceCopy, onReload: @escaping () -> Void) {
        self.docType = docType
        self.engine = engine
        self.workflowEngine = workflowEngine
        self.customFieldStore = customFieldStore
        self.initialDocument = initialDocument
        self.copy = copy
        self.onReload = onReload
        self._document = State(initialValue: initialDocument)
    }

    private var isNewRecord: Bool {
        document.id.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsHeader
                GenericFormView(
                    docType: docType,
                    document: $document,
                    linkSearchProvider: { targetDocType, _ in
                        (try? engine.list(docType: targetDocType)) ?? []
                    },
                    linkResolveProvider: { targetDocType, id in
                        try? engine.fetch(docType: targetDocType, id: id)
                    },
                    childDocTypeProvider: { HubManifest.docType(for: $0) }
                )

                saveButton

                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(MercantisTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MercantisTheme.appBackground)
        .onAppear {
            loadCustomFields()
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: settingsSymbol)
                    .font(.title2)
                    .foregroundStyle(MercantisTheme.brandPrimary)
                Text(copy.title)
                    .font(.title2.bold())
                    .foregroundStyle(MercantisTheme.textPrimary)
                if showSavedConfirmation {
                    Text("Saved")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(MercantisTheme.success)
                        .transition(.opacity)
                }
            }
            Text(copy.subtitle)
                .font(.callout)
                .foregroundStyle(MercantisTheme.textSecondary)
        }
        .padding(.bottom, 4)
    }

    private var saveButton: some View {
        HStack {
            Button(isNewRecord ? copy.primaryActionTitle : "Save Changes") {
                saveRecord()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.top, 4)
    }

    private func saveRecord() {
        do {
            let saved = try engine.save(document)
            // Refetch so optimistic concurrency stays valid on next save.
            if let refetched = try? engine.fetch(docType: docType.id, id: saved.id) {
                document = refetched
            } else {
                document = saved
            }
            errorMessage = nil
            showSavedConfirmation = true
            onReload()
            // Dismiss the "Saved" label after a short delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showSavedConfirmation = false
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func loadCustomFields() {
        do {
            customFields = try customFieldStore.list(forDocType: docType.id)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private var settingsSymbol: String {
        switch docType.id {
        case "Company":         return "building.2"
        case "NumberingSeries":  return "number"
        default:                return "gearshape"
        }
    }
}
