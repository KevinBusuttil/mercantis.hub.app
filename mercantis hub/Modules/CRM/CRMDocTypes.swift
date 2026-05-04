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
                fieldKeys: ["customer_name", "customer_type", "customer_group", "territory"]
            ),
            FormLayoutSection(
                key: "contact",
                title: "Contact",
                helpText: "How sales and support reach this customer.",
                fieldKeys: ["email", "phone", "mobile", "website"]
            ),
            FormLayoutSection(
                key: "financial",
                title: "Financial",
                helpText: "Tax registration and accounts-receivable terms.",
                fieldKeys: ["tax_id", "credit_limit", "payment_terms"]
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
            FieldDefinition(key: "company_name", label: "Company", type: .link,
                            required: false, linkedDocType: "Customer"),
            FieldDefinition(key: "designation", label: "Designation", type: .text,
                            required: false),
            FieldDefinition(key: "department", label: "Department", type: .text,
                            required: false),
            FieldDefinition(key: "address", label: "Address", type: .link,
                            required: false, linkedDocType: "Address")
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
                fieldKeys: ["first_name", "last_name"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                fieldKeys: ["email_id", "mobile_no", "phone"]
            ),
            FormLayoutSection(
                key: "company",
                title: "Company",
                fieldKeys: ["company_name", "designation", "department", "address"]
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
            FieldDefinition(key: "fax", label: "Fax", type: .text, required: false)
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
                fieldKeys: ["address_title", "address_type"]
            ),
            FormLayoutSection(
                key: "street",
                title: "Street",
                fieldKeys: ["address_line1", "address_line2", "city", "state", "country", "pincode"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                fieldKeys: ["phone", "fax"]
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
                fieldKeys: ["lead_name", "company_name"]
            ),
            FormLayoutSection(
                key: "pipeline",
                title: "Pipeline",
                helpText: "Where this lead sits in the sales process.",
                fieldKeys: ["status", "source", "territory"]
            ),
            FormLayoutSection(
                key: "reach",
                title: "Reach",
                fieldKeys: ["email_id", "mobile_no", "phone"]
            ),
            FormLayoutSection(
                key: "notes",
                title: "Notes",
                fieldKeys: ["notes"]
            )
        ])
    )

    static let allDocTypes: [DocType] = [customer, contact, address, lead]
}
