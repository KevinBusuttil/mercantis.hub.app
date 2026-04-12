// mercantis hub
// Created by Kevin Busuttil on 12/04/2026.

import Foundation

// Uses Core's WorkflowDefinition, WorkflowState, WorkflowTransition — imported from MercantisCore when dependency is wired up.

/// Stub namespace for all Hub workflow definitions.
///
/// Hub workflows are declarative `WorkflowDefinition` values (ADR-004) that describe
/// state machines for transactional DocTypes. They are registered in the `AppManifest`
/// and evaluated entirely by Core's `WorkflowEngine` — Hub provides no custom runtime logic.
///
/// - ADR-004: Workflows are declarative manifest data.
/// - ADR-008: No dynamic code loading; all states and transitions are statically declared.
public enum HubWorkflows: Sendable {

    // MARK: - Sales Order Approval

    /// Workflow for the **Sales Order** document.
    ///
    /// Proposed states: Draft → Pending Approval → Approved → Cancelled
    ///
    /// - TODO: Implement using `WorkflowDefinition` from MercantisCore.
    public static var salesOrderApproval: Never {
        fatalError("salesOrderApproval is a stub — implement with Core's WorkflowDefinition.")
    }

    // MARK: - Purchase Order Approval

    /// Workflow for the **Purchase Order** document.
    ///
    /// Proposed states: Draft → Pending Approval → Approved → Cancelled
    ///
    /// - TODO: Implement using `WorkflowDefinition` from MercantisCore.
    public static var purchaseOrderApproval: Never {
        fatalError("purchaseOrderApproval is a stub — implement with Core's WorkflowDefinition.")
    }

    // MARK: - Leave Application

    /// Workflow for the **Leave Application** document.
    ///
    /// Proposed states: Open → Approved → Rejected
    ///
    /// - TODO: Implement using `WorkflowDefinition` from MercantisCore.
    public static var leaveApplicationApproval: Never {
        fatalError("leaveApplicationApproval is a stub — implement with Core's WorkflowDefinition.")
    }

    // MARK: - Expense Claim

    /// Workflow for the **Expense Claim** document.
    ///
    /// Proposed states: Draft → Submitted → Approved → Paid → Rejected
    ///
    /// - TODO: Implement using `WorkflowDefinition` from MercantisCore.
    public static var expenseClaimApproval: Never {
        fatalError("expenseClaimApproval is a stub — implement with Core's WorkflowDefinition.")
    }

    // MARK: - All Workflows

    /// All workflow definitions — will be wired into `HubManifest.build()`.
    /// - TODO: Replace with an array of `WorkflowDefinition` values from MercantisCore.
    public static let allWorkflows: [Any] = []
}
