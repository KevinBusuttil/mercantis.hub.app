import MercantisCore

/// Declares which DocTypes behave as settings-style single-record workspaces.
///
/// When a DocType is marked as single-record:
/// - If no record exists, the workspace shows a setup empty state with a
///   single "Set Up…" action.
/// - If one record already exists, the workspace shows the editor for that
///   record directly, bypassing the list/browse view entirely.
/// - The "New" menu action is suppressed once a record exists to prevent
///   accidental creation of duplicate settings.
enum HubSingleRecordPolicy {

    /// DocType IDs that should follow single-record / settings UX.
    private static let singleRecordDocTypes: Set<String> = [
        "Company",
        "NumberingSeries"
    ]

    /// Returns `true` if the given DocType should be treated as a
    /// settings-style single-record workspace.
    static func isSingleRecord(_ docTypeId: String) -> Bool {
        singleRecordDocTypes.contains(docTypeId)
    }
}
