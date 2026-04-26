// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — Project/Task/Timesheet all use `lastWriteWins`
//          as these are collaborative planning documents with low financial risk.

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **Projects** module.
///
/// Covers project management, task tracking, and timesheet logging.
///
/// - ADR-006: All Projects DocTypes use `lastWriteWins` — they are collaborative
///            planning/tracking records rather than financial ledger entries.
public enum Projects: Sendable {

    // MARK: - Project

    /// Represents a time-bound initiative with defined deliverables and a team.
    ///
    /// Key fields:
    /// - `projectName` (title field)
    /// - `status`, `expectedStartDate`, `expectedEndDate`, `customer`, `estimatedCost`
    ///
    /// Child tables:
    /// - `tasks` → project task rows
    ///
    /// Sync policy: `lastWriteWins` (ADR-006)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let project = HubDocTypeDescriptor(
        name: "Project",
        module: "Projects",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Task

    /// A single unit of work within a project, assignable to a team member.
    ///
    /// Key fields:
    /// - `subject` (title field)
    /// - `project`, `assignedTo`, `status`, `priority`, `expStartDate`, `expEndDate`
    ///
    /// Child tables:
    /// - `dependsOn` → task dependency rows
    ///
    /// Sync policy: `lastWriteWins` (ADR-006)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let task = HubDocTypeDescriptor(
        name: "Task",
        module: "Projects",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Timesheet

    /// Records the hours an employee spends on a project or task.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `employee`, `startDate`, `endDate`, `status`, `totalBillableHours`
    ///
    /// Child tables:
    /// - `timeLogs` → time-log detail rows (from/to time, project, task)
    ///
    /// Sync policy: `lastWriteWins` (ADR-006)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let timesheet = HubDocTypeDescriptor(
        name: "Timesheet",
        module: "Projects",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - All DocTypes

    /// All Projects DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        project, task, timesheet,
    ]
}
