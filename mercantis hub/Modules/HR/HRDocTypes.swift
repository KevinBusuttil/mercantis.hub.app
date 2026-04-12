// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

// ADR-006: Sync policies — Payroll/ExpenseClaim use `versionChecked` (financial documents);
//          Employee/LeaveApplication/Attendance use `lastWriteWins` (master / administrative data).

import Foundation

// Uses Core's DocType, FieldDefinition, SyncPolicy — imported from MercantisCore when dependency is wired up.

/// DocType catalog for the **HR** module.
///
/// Covers employee master, leave management, expense claims, payroll processing,
/// and attendance tracking.
///
/// - ADR-006: Financial HR documents (`Payroll`, `ExpenseClaim`) require `versionChecked`
///            to prevent silent overwrites of payroll amounts.
public enum HR: Sendable {

    // MARK: - Employee

    /// Represents a company employee and their HR profile.
    ///
    /// Key fields:
    /// - `employeeName` (title field)
    /// - `department`, `designation`, `dateOfJoining`, `status`, `company`
    ///
    /// Child tables:
    /// - `educationDetails` → academic qualification rows
    /// - `previousExperience` → work history rows
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — master data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let employee = HubDocTypeDescriptor(
        name: "Employee",
        module: "HR",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - LeaveApplication

    /// A leave request submitted by an employee and approved by a manager.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `employee`, `leaveType`, `fromDate`, `toDate`, `status`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — administrative workflow document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let leaveApplication = HubDocTypeDescriptor(
        name: "LeaveApplication",
        module: "HR",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - Attendance

    /// A daily attendance record for an employee (present, absent, half-day, etc.).
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `employee`, `attendanceDate`, `status`
    ///
    /// Child tables: none
    ///
    /// Sync policy: `lastWriteWins` (ADR-006 — administrative data)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let attendance = HubDocTypeDescriptor(
        name: "Attendance",
        module: "HR",
        syncPolicy: "lastWriteWins"
    )

    // MARK: - ExpenseClaim

    /// An expense reimbursement claim submitted by an employee.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `employee`, `postingDate`, `totalClaimedAmount`, `totalSanctionedAmount`, `status`
    ///
    /// Child tables:
    /// - `expenses` → itemised expense rows
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let expenseClaim = HubDocTypeDescriptor(
        name: "ExpenseClaim",
        module: "HR",
        syncPolicy: "versionChecked"
    )

    // MARK: - Payroll

    /// A payroll processing run that calculates and disburses employee salaries.
    ///
    /// Key fields:
    /// - `name` (title field, auto-generated)
    /// - `payrollFrequency`, `startDate`, `endDate`, `status`, `company`
    ///
    /// Child tables:
    /// - `employees` → payroll employee rows with gross/deduction/net amounts
    ///
    /// Sync policy: `versionChecked` (ADR-006 — financial document)
    ///
    /// - TODO: Replace with `DocType` from MercantisCore.
    public static let payroll = HubDocTypeDescriptor(
        name: "Payroll",
        module: "HR",
        syncPolicy: "versionChecked"
    )

    // MARK: - All DocTypes

    /// All HR DocType descriptors — will be passed to `AppManifest` when Core is available.
    /// - TODO: Replace `HubDocTypeDescriptor` elements with `DocType` values from MercantisCore.
    public static let allDocTypes: [HubDocTypeDescriptor] = [
        employee, leaveApplication, attendance, expenseClaim, payroll,
    ]
}
