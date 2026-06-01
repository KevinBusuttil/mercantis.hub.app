import MercantisCore

private let systemManagerPermission = PermissionRule(
    role: "System Manager",
    canRead: true,
    canWrite: true,
    canCreate: true,
    canDelete: true,
    canSubmit: false,
    canAmend: false
)

enum CRM {

    // MARK: - Child DocTypes

    /// One row inside an Address.links or Contact.links table. Declares a
    /// dynamic relation: `link_doctype` chooses the target DocType and
    /// `link_name` carries that document's id. Wall 5 unlocks this in
    /// place of the single static link Contact carried before.
    static let dynamicLink = DocType(
        id: "DynamicLink",
        name: "Dynamic Link",
        module: "CRM",
        appId: HubManifest.appID,
        isChildTable: true,
        fields: [
            FieldDefinition(key: "link_doctype", label: "Link DocType",
                            type: .select, required: true,
                            options: ["Customer", "Supplier", "Lead", "Contact"]),
            FieldDefinition(key: "link_name", label: "Link Name",
                            type: .text, required: true),
            FieldDefinition(key: "is_primary", label: "Primary",
                            type: .boolean, required: false, defaultValue: .bool(false))
        ],
        permissions: [systemManagerPermission],
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: [],
        titleField: "link_name"
    )

    // MARK: - Parent DocTypes

    static let customer = DocType(
        id: "Customer",
        name: "Customer",
        module: "CRM",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "customer_name", label: "Customer Name", type: .text,
                            required: true, isSearchable: true),
            FieldDefinition(key: "customer_type", label: "Customer Type", type: .select,
                            required: true, options: ["Individual", "Company"]),
            FieldDefinition(key: "customer_group", label: "Customer Group", type: .link,
                            required: false, linkedDocType: "CustomerGroup"),
            FieldDefinition(key: "territory", label: "Territory", type: .link,
                            required: false, linkedDocType: "Territory"),
            FieldDefinition(key: "email", label: "Email", type: .email,
                            required: false, isSearchable: true),
            FieldDefinition(key: "phone", label: "Phone", type: .phone, required: false),
            FieldDefinition(key: "mobile", label: "Mobile", type: .phone, required: false),
            FieldDefinition(key: "website", label: "Website", type: .text, required: false),
            FieldDefinition(key: "tax_id", label: "Tax ID", type: .text, required: false),
            FieldDefinition(key: "tax_code", label: "Default Tax Code",
                            type: .link, required: false, linkedDocType: "TaxCode"),
            FieldDefinition(key: "default_currency", label: "Default Currency",
                            type: .link, required: false, linkedDocType: "Currency"),
            FieldDefinition(key: "default_price_list", label: "Default Price List",
                            type: .link, required: false, linkedDocType: "PriceList"),
            FieldDefinition(key: "default_cost_center", label: "Default Cost Center",
                            type: .link, required: false, linkedDocType: "CostCenter"),
            FieldDefinition(key: "default_warehouse", label: "Default Warehouse",
                            type: .link, required: false, linkedDocType: "Warehouse"),
            FieldDefinition(key: "credit_limit", label: "Credit Limit", type: .currency,
                            required: false),
            FieldDefinition(key: "payment_terms", label: "Payment Terms", type: .text,
                            required: false),
            FieldDefinition(key: "notes", label: "Notes", type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:CUST-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["customer_name", "email"],
        titleField: "customer_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity",
                title: "Customer",
                columns: 2,
                fieldKeys: ["customer_name", "customer_type", "customer_group", "territory"]
            ),
            FormLayoutSection(
                key: "contact",
                title: "Contact",
                helpText: "How sales and support reach this customer.",
                columns: 2,
                fieldKeys: ["email", "phone", "mobile", "website"]
            ),
            FormLayoutSection(
                key: "defaults",
                title: "Defaults",
                helpText: "Used when raising new transactions for this customer.",
                columns: 2,
                fieldKeys: ["default_currency", "default_price_list",
                            "default_cost_center", "default_warehouse"]
            ),
            FormLayoutSection(
                key: "financial",
                title: "Financial",
                helpText: "Tax registration and accounts-receivable terms.",
                columns: 2,
                fieldKeys: ["tax_id", "tax_code", "credit_limit", "payment_terms"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    static let contact = DocType(
        id: "Contact",
        name: "Contact",
        module: "CRM",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "first_name", label: "First Name", type: .text,
                            required: true, isSearchable: true),
            FieldDefinition(key: "last_name", label: "Last Name", type: .text,
                            required: false, isSearchable: true),
            FieldDefinition(key: "email_id", label: "Email", type: .email,
                            required: false, isSearchable: true),
            FieldDefinition(key: "mobile_no", label: "Mobile", type: .phone, required: false),
            FieldDefinition(key: "phone", label: "Phone", type: .phone, required: false),
            FieldDefinition(key: "designation", label: "Designation", type: .text,
                            required: false),
            FieldDefinition(key: "department", label: "Department", type: .text,
                            required: false),
            FieldDefinition(key: "links", label: "Linked To",
                            type: .table, required: false, childDocType: "DynamicLink")
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:CONT-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["first_name", "last_name", "email_id"],
        titleField: "first_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "name",
                title: "Name",
                columns: 2,
                fieldKeys: ["first_name", "last_name"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                columns: 2,
                fieldKeys: ["email_id", "mobile_no", "phone"]
            ),
            FormLayoutSection(
                key: "role",
                title: "Role",
                columns: 2,
                fieldKeys: ["designation", "department"]
            ),
            FormLayoutSection(
                key: "links",
                title: "Linked To",
                helpText: "Customers, Suppliers, or Leads this contact is associated with.",
                fieldKeys: ["links"]
            )
        ])
    )

    static let address = DocType(
        id: "Address",
        name: "Address",
        module: "CRM",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "address_title", label: "Title", type: .text,
                            required: true, isSearchable: true),
            FieldDefinition(key: "address_type", label: "Address Type", type: .select,
                            required: false, options: ["Billing", "Shipping", "Other"]),
            FieldDefinition(key: "address_line1", label: "Address Line 1", type: .text,
                            required: true),
            FieldDefinition(key: "address_line2", label: "Address Line 2", type: .text,
                            required: false),
            FieldDefinition(key: "city", label: "City", type: .text, required: true),
            FieldDefinition(key: "state", label: "State / Province", type: .text,
                            required: false),
            FieldDefinition(key: "country", label: "Country", type: .text, required: true),
            FieldDefinition(key: "pincode", label: "Postcode", type: .text, required: false),
            FieldDefinition(key: "phone", label: "Phone", type: .phone, required: false),
            FieldDefinition(key: "fax", label: "Fax", type: .text, required: false),
            FieldDefinition(key: "links", label: "Linked To",
                            type: .table, required: false, childDocType: "DynamicLink")
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:ADDR-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["address_title", "city", "country"],
        titleField: "address_title",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "label",
                title: "Address",
                columns: 2,
                fieldKeys: ["address_title", "address_type"]
            ),
            FormLayoutSection(
                key: "street",
                title: "Street",
                columns: 2,
                fieldKeys: ["address_line1", "address_line2", "city", "state", "country", "pincode"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                columns: 2,
                fieldKeys: ["phone", "fax"]
            ),
            FormLayoutSection(
                key: "links",
                title: "Linked To",
                helpText: "Customers, Suppliers, or Leads this address belongs to.",
                fieldKeys: ["links"]
            )
        ])
    )

    static let lead = DocType(
        id: "Lead",
        name: "Lead",
        module: "CRM",
        appId: HubManifest.appID,
        isChildTable: false,
        fields: [
            FieldDefinition(key: "lead_name", label: "Name", type: .text,
                            required: true, isSearchable: true),
            FieldDefinition(key: "company_name", label: "Company", type: .text,
                            required: false, isSearchable: true),
            FieldDefinition(key: "status", label: "Status", type: .select,
                            required: true,
                            options: ["Lead", "Open", "Replied", "Opportunity",
                                      "Interested", "Converted", "Do Not Contact"]),
            FieldDefinition(key: "source", label: "Lead Source", type: .select,
                            required: false,
                            options: ["Cold Calling", "Advertisement", "Email",
                                      "Campaign", "Word of Mouth", "Other"]),
            FieldDefinition(key: "email_id", label: "Email", type: .email,
                            required: false, isSearchable: true),
            FieldDefinition(key: "mobile_no", label: "Mobile", type: .phone, required: false),
            FieldDefinition(key: "phone", label: "Phone", type: .phone, required: false),
            FieldDefinition(key: "territory", label: "Territory", type: .link,
                            required: false, linkedDocType: "Territory"),
            FieldDefinition(key: "converted_customer", label: "Converted Customer",
                            type: .link, required: false, linkedDocType: "Customer"),
            FieldDefinition(key: "notes", label: "Notes", type: .longText, required: false)
        ],
        permissions: [systemManagerPermission],
        autoname: "naming_series:CRM-LEAD-.YYYY.-.####",
        syncPolicy: SyncPolicy(conflictResolution: .lastWriteWins, immutableAfterSubmit: false),
        indexes: [],
        searchFields: ["lead_name", "company_name", "email_id"],
        titleField: "lead_name",
        formLayout: FormLayout(sections: [
            FormLayoutSection(
                key: "identity",
                title: "Lead",
                columns: 2,
                fieldKeys: ["lead_name", "company_name"]
            ),
            FormLayoutSection(
                key: "pipeline",
                title: "Pipeline",
                helpText: "Where this lead sits in the sales process.",
                columns: 2,
                fieldKeys: ["status", "source", "territory"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                columns: 2,
                fieldKeys: ["email_id", "mobile_no", "phone"]
            ),
            FormLayoutSection(
                key: "conversion",
                title: "Conversion",
                helpText: "Once this lead becomes a paying customer, link the resulting Customer record here.",
                fieldKeys: ["converted_customer"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [
        // Child DocTypes first so install ordering matches reference order.
        dynamicLink,
        // Parents
        customer, contact, address, lead
    ]
}
