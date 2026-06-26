import XCTest
import MercantisCore
@testable import Mercantis_Hub

/// Tier 3 — end-to-end integration of the atomic posting path.
///
/// The derivation unit tests (`HubPostingDerivationTests`) prove the row
/// builders are correct in isolation. This suite proves the *whole machine*:
/// a real `MercantisDatabase` + installed `HubManifest` + `DocumentEngine` +
/// `PostingCoordinator`, driving a document through `submit` → in-transaction
/// `post` → commit, then reading the committed ledger and `PostingBatch` back
/// out of SQLite. It locks in the property that makes the atomic redesign
/// worth it: either the source document AND its ledger rows AND the posting
/// batch all commit together, or none of them do — there is no half-posted
/// state to recover.
///
/// JournalEntry is chosen as the vehicle because it needs the fewest fixtures
/// (no warehouse / stock cost basis / company-default accounts) while still
/// exercising the full submit-post-commit-cancel-reverse cycle.
final class HubPostingIntegrationTests: XCTestCase {

    private var databaseURL: URL!
    private var database: MercantisDatabase!
    private var engine: DocumentEngine!
    private var coordinator: PostingCoordinator!
    private var batches: PostingBatchStore!

    override func setUpWithError() throws {
        // A fresh on-disk SQLite database per test, in the temp dir.
        let dir = FileManager.default.temporaryDirectory
        databaseURL = dir.appendingPathComponent("hub-posting-\(UUID().uuidString).sqlite")

        database = try MercantisDatabase(databaseURL: databaseURL)
        let registry = MetadataRegistry(database: database)
        let validator = SchemaValidator()

        // Install the real Hub manifest so every DocType, workflow and
        // validation rule the posting path depends on is present.
        let installer = AppInstaller(
            database: database,
            schemaValidator: validator,
            registry: registry
        )
        try installer.install(HubManifest.build())

        // failClosedForSubmittable defaults to false here: with no operator
        // context the engine uses its legacy device identity and the
        // submittable lifecycle is open, so the test drives submit / cancel
        // without standing up an auth store. The posting behaviour under test
        // is independent of who is signed in.
        engine = DocumentEngine(
            database: database,
            registry: registry,
            deviceId: "test-device",
            userId: "tester"
        )
        coordinator = PostingCoordinator(engine: engine)
        batches = PostingBatchStore(database: database)
    }

    override func tearDownWithError() throws {
        engine = nil
        coordinator = nil
        batches = nil
        database = nil
        if let databaseURL { try? FileManager.default.removeItem(at: databaseURL) }
    }

    // MARK: - Helpers

    private func account(_ id: String, _ name: String, type: String) throws {
        let doc = Document(
            id: id, docType: "Account", company: "Default Company", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: [
                "account_name": .string(name),
                "account_type": .string(type),
                "is_group": .bool(false)
            ],
            children: [:]
        )
        try engine.save(doc)
    }

    private func dbl(_ v: FieldValue?) -> Double? {
        switch v {
        case .double(let d): return d
        case .int(let i):    return Double(i)
        default:             return nil
        }
    }

    private func glEntries() throws -> [Document] {
        // No operator context in the harness, so bypass row-access filtering
        // (which would otherwise drop every row for an unauthenticated read).
        try engine.list(docType: "GLEntry", applyRowAccess: false)
    }

    private func totalDebit(_ rows: [Document]) -> Double {
        rows.reduce(0) { $0 + (dbl($1.fields["debit"]) ?? 0) }
    }
    private func totalCredit(_ rows: [Document]) -> Double {
        rows.reduce(0) { $0 + (dbl($1.fields["credit"]) ?? 0) }
    }

    // MARK: - The full cycle

    func test_journalEntry_submitPostsBalancedLedgerAndBatch_cancelReverses() throws {
        try account("ACC-CASH", "Cash", type: "Cash")
        try account("ACC-SALES", "Sales", type: "Income")

        // A balanced manual journal: Dr Cash 100 / Cr Sales 100.
        let jeId = "JE-TEST-1"
        let draft = Document(
            id: jeId, docType: "JournalEntry", company: "Default Company", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: [
                "voucher_type": .string("Journal Entry"),
                "posting_date": .date(Date()),
                "total_debit": .double(100),
                "total_credit": .double(100)
            ],
            children: ["accounts": [
                ChildRow(id: "r0", rowIndex: 0, fields: [
                    "account": .string("ACC-CASH"), "debit": .double(100), "credit": .double(0)
                ]),
                ChildRow(id: "r1", rowIndex: 1, fields: [
                    "account": .string("ACC-SALES"), "debit": .double(0), "credit": .double(100)
                ])
            ]]
        )

        // Save as a draft, then submit — the posting closure runs INSIDE the
        // submit write transaction and commits the ledger atomically with the
        // docStatus transition.
        var je = try engine.save(draft)
        XCTAssertEqual(je.docStatus, 0)

        // Nothing posted before submit.
        XCTAssertTrue(try glEntries().isEmpty)
        XCTAssertNil(try batches.batch(id: PostingBatch.makeID(sourceId: jeId, version: 1)))

        try engine.submit(&je, inTransaction: coordinator.submitClosure(for: je))
        XCTAssertEqual(je.docStatus, 1)

        // Ledger committed: two balanced GL legs.
        let posted = try glEntries()
        XCTAssertEqual(posted.count, 2)
        XCTAssertEqual(totalDebit(posted), 100, accuracy: 0.001)
        XCTAssertEqual(totalCredit(posted), 100, accuracy: 0.001)
        let cashLeg = posted.first { ($0.fields["account"]) == .string("ACC-CASH") }
        XCTAssertEqual(dbl(cashLeg?.fields["debit"]), 100)

        // The posting batch committed in the same transaction, marked posted.
        let v1 = try batches.batch(id: PostingBatch.makeID(sourceId: jeId, version: 1))
        XCTAssertEqual(v1?.status, .posted)
        XCTAssertEqual(v1?.sourceType, "JournalEntry")
        XCTAssertEqual(v1?.sourceId, jeId)

        // Cancel reverses: a v2 batch and a mirrored pair of reversal legs that
        // net the ledger back to zero.
        try engine.cancel(&je, inTransaction: coordinator.cancelClosure(for: je))
        XCTAssertEqual(je.docStatus, 2)

        let afterCancel = try glEntries()
        XCTAssertEqual(afterCancel.count, 4)   // 2 original + 2 reversal
        // Whole ledger now sums to zero on each side's net.
        XCTAssertEqual(totalDebit(afterCancel), totalCredit(afterCancel), accuracy: 0.001)
        let netDebit = totalDebit(afterCancel) - totalCredit(afterCancel)
        XCTAssertEqual(netDebit, 0, accuracy: 0.001)

        let v2 = try batches.batch(id: PostingBatch.makeID(sourceId: jeId, version: 2))
        XCTAssertEqual(v2?.status, .reversed)
        XCTAssertEqual(v2?.reversalOfBatch, PostingBatch.makeID(sourceId: jeId, version: 1))
    }

    /// Re-firing the same posting closure is a no-op: the deterministic batch id
    /// makes the post idempotent, so a duplicate submit can't double-post.
    func test_posting_isIdempotentOnBatchId() throws {
        try account("ACC-CASH", "Cash", type: "Cash")
        try account("ACC-SALES", "Sales", type: "Income")

        let jeId = "JE-TEST-2"
        let draft = Document(
            id: jeId, docType: "JournalEntry", company: "Default Company", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: [
                "voucher_type": .string("Journal Entry"),
                "posting_date": .date(Date()),
                "total_debit": .double(50),
                "total_credit": .double(50)
            ],
            children: ["accounts": [
                ChildRow(id: "r0", rowIndex: 0, fields: [
                    "account": .string("ACC-CASH"), "debit": .double(50), "credit": .double(0)
                ]),
                ChildRow(id: "r1", rowIndex: 1, fields: [
                    "account": .string("ACC-SALES"), "debit": .double(0), "credit": .double(50)
                ])
            ]]
        )
        var je = try engine.save(draft)
        try engine.submit(&je, inTransaction: coordinator.submitClosure(for: je))
        XCTAssertEqual(try glEntries().count, 2)

        // Replay the post closure inside an unrelated write transaction (here,
        // saving another Account) via the public `inTransaction` seam. The
        // deterministic batch id already exists, so post() returns early and
        // writes nothing — a re-fire can't double-post.
        let replay = Document(
            id: "ACC-REPLAY", docType: "Account", company: "Default Company", status: "",
            createdAt: Date(), updatedAt: Date(), syncVersion: 0, syncState: .local,
            fields: ["account_name": .string("Replay"), "is_group": .bool(false)],
            children: [:]
        )
        try engine.save(replay, inTransaction: coordinator.submitClosure(for: je))
        XCTAssertEqual(try glEntries().count, 2)   // still 2 — no double-post
    }
}
