import Foundation

// ---------------------------------------------------------------------------
// MARK: - Project
// ---------------------------------------------------------------------------

/// A Parlance project returned by GET /api/v1/projects.
public struct Project: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let platforms: [String]
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String,
        name: String,
        description: String? = nil,
        platforms: [String] = [],
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.platforms = platforms
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, platforms
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Contract types + Category / Status
// ---------------------------------------------------------------------------

/// The category of a contract component — an open-ended string matching known levels.
/// Canonical values are `atom`, `molecule`, `organism`, `template`, `page`, but the
/// platform stores category as free text, so unknown values decode without error.
public struct ContractCategory: Codable, Sendable, Equatable, RawRepresentable, Hashable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let atom      = ContractCategory(rawValue: "atom")
    public static let molecule  = ContractCategory(rawValue: "molecule")
    public static let organism  = ContractCategory(rawValue: "organism")
    public static let template  = ContractCategory(rawValue: "template")
    public static let page      = ContractCategory(rawValue: "page")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ContractStatus: String, Codable, Sendable {
    case draft, active, archived, deprecated
}

/// Platform-specific implementation detail embedded in a contract detail response.
public struct PlatformSpec: Codable, Sendable {
    public let platform: String
    public let framework: String
    public let componentName: String
    public let props: [String: AnyDecodable]
    public let a11y: [String: AnyDecodable]

    private enum CodingKeys: String, CodingKey {
        case platform, framework
        case componentName = "component_name"
        case props, a11y
    }
}

/// Standards (WCAG/accessibility) summary embedded in a contract detail response.
public struct ContractStandardsSummary: Codable, Sendable {
    public let wcagScore: Int
    public let criteriaPassed: Int
    public let criteriaTotal: Int
    public let issues: [AnyDecodable]

    private enum CodingKeys: String, CodingKey {
        case wcagScore = "wcag_score"
        case criteriaPassed = "criteria_passed"
        case criteriaTotal = "criteria_total"
        case issues
    }
}

/// Glossary term embedded in a contract detail response.
public struct EmbeddedGlossaryTerm: Codable, Sendable {
    public let name: String
    public let rawValue: String
    public let category: String
    public let description: String?
    public let translations: [String: String]

    private enum CodingKeys: String, CodingKey {
        case name
        case rawValue = "raw_value"
        case category, description, translations
    }
}

/**
 Lighter shape returned by GET /api/v1/projects/:id/contracts.
 Use ``ParlanceClient/getContractDetail(projectId:contractId:)`` for the full ``Contract`` shape.
 */
public struct ContractSummary: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let category: ContractCategory?
    public let status: ContractStatus
    public let createdAt: String
    public let updatedAt: String
    public let platformCount: Int
    public let latestScore: Double?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, category, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case platformCount = "platform_count"
        case latestScore = "latest_score"
    }
}

/// Full contract — returned by GET /api/v1/projects/:id/contracts/:contractId.
public struct Contract: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let category: ContractCategory?
    public let status: ContractStatus
    /// Free-form design intent dict (contents vary per contract).
    public let designIntent: [String: AnyDecodable]
    public let origin: ContractOrigin?
    public let platformSpecs: [PlatformSpec]
    public let standards: ContractStandardsSummary?
    public let glossaryTerms: [EmbeddedGlossaryTerm]
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, name, description, category, status
        case designIntent = "design_intent"
        case origin
        case platformSpecs = "platform_specs"
        case standards
        case glossaryTerms = "glossary_terms"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Input for createContract / updateContract.
public struct ContractInput: Encodable, Sendable {
    public let name: String
    public let description: String
    public let category: ContractCategory?
    public let status: ContractStatus?

    public init(
        name: String,
        description: String,
        category: ContractCategory? = nil,
        status: ContractStatus? = nil
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.status = status
    }
}

// ---------------------------------------------------------------------------
// MARK: - ContractOrigin
// ---------------------------------------------------------------------------

/// The origin field on a contract — an open-ended string matching known tool names.
/// Canonical platform values: `figma`, `code`, `manual`. Additional values tolerated.
public struct ContractOrigin: Codable, Sendable, Equatable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static let figma     = ContractOrigin(rawValue: "figma")
    public static let code      = ContractOrigin(rawValue: "code")
    public static let manual    = ContractOrigin(rawValue: "manual")
    // Legacy / extended tool names — kept for backward compat with older records.
    public static let sketch    = ContractOrigin(rawValue: "sketch")
    public static let adobeXD  = ContractOrigin(rawValue: "adobe-xd")
    public static let penpot    = ContractOrigin(rawValue: "penpot")
    public static let zeplin    = ContractOrigin(rawValue: "zeplin")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// ---------------------------------------------------------------------------
// MARK: - GlossaryTerm
// ---------------------------------------------------------------------------

/// A glossary term returned by GET /api/v1/projects/:id/glossary.
public struct GlossaryTerm: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    /// Display name of the term.
    public let name: String
    /// Raw / source value in design tokens or source files.
    public let rawValue: String
    public let category: String
    /// Optional human-readable description (maps to `glossary_values.description` on the platform).
    public let description: String?
    public let translations: [String: String]
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String,
        name: String,
        rawValue: String = "",
        category: String = "",
        description: String? = nil,
        translations: [String: String] = [:],
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.name = name
        self.rawValue = rawValue
        self.category = category
        self.description = description
        self.translations = translations
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case rawValue = "raw_value"
        case category, description, translations
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Input for createGlossaryTerm / updateGlossaryTerm.
public struct GlossaryTermInput: Encodable, Sendable {
    public let name: String
    public let rawValue: String
    public let category: String?
    public let description: String?

    public init(name: String, rawValue: String, category: String? = nil, description: String? = nil) {
        self.name = name
        self.rawValue = rawValue
        self.category = category
        self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case rawValue = "raw_value"
        case category, description
    }
}

// ---------------------------------------------------------------------------
// MARK: - Audit Results
// ---------------------------------------------------------------------------

public enum AuditSeverity: String, Codable, Sendable {
    case critical, error, warning, info
}

/// A single audit finding to be sent to the API.
public struct AuditResultItem: Encodable, Sendable {
    public let ruleId: String
    public let severity: AuditSeverity
    public let message: String
    public let filePath: String?
    public let elementSelector: String?
    /// Concrete remediation for this finding, persisted server-side.
    public let suggestedFix: String?

    public init(
        ruleId: String,
        severity: AuditSeverity,
        message: String,
        filePath: String? = nil,
        elementSelector: String? = nil,
        suggestedFix: String? = nil
    ) {
        self.ruleId = ruleId
        self.severity = severity
        self.message = message
        self.filePath = filePath
        self.elementSelector = elementSelector
        self.suggestedFix = suggestedFix
    }

    private enum CodingKeys: String, CodingKey {
        case ruleId = "rule_id"
        case severity, message
        case filePath = "file_path"
        case elementSelector = "element_selector"
        case suggestedFix = "suggested_fix"
    }
}

/// The input payload for ``ParlanceClient/pushAuditResults(projectId:input:)``.
public struct AuditResultInput: Encodable, Sendable {
    public let results: [AuditResultItem]
    /// The audited page URL — recorded as the audit's target server-side.
    public let pageUrl: String?
    /// Overall audit score 0–100 — recorded as the audit's overall score.
    public let score: Int?

    public init(results: [AuditResultItem], pageUrl: String? = nil, score: Int? = nil) {
        self.results = results
        self.pageUrl = pageUrl
        self.score = score
    }

    private enum CodingKeys: String, CodingKey {
        case results
        case pageUrl = "page_url"
        case score
    }
}

/// Response from pushAuditResults — POST /api/v1/projects/:id/audit-results returns { inserted: N }.
public struct AuditResult: Decodable, Sendable {
    public let inserted: Int
}

// ---------------------------------------------------------------------------
// MARK: - Validation
// ---------------------------------------------------------------------------

/// Colour in RGBA 0-255 format.
public struct DesignColour: Codable, Sendable, Equatable {
    public let r: Int
    public let g: Int
    public let b: Int
    public let a: Int

    public init(r: Int, g: Int, b: Int, a: Int = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// Design data properties passed in a validate request.
public struct DesignProperties: Encodable, Sendable {
    public let width: Double?
    public let height: Double?
    public let paddingTop: Double?
    public let paddingBottom: Double?
    public let paddingLeft: Double?
    public let paddingRight: Double?
    public let fontSize: Double?
    public let fontWeight: Double?
    public let lineHeight: Double?
    public let cornerRadius: Double?
    public let fillColors: [DesignColour]?
    public let textColors: [DesignColour]?
    public let hasFocusRing: Bool?
    public let minTouchTarget: Double?

    public init(
        width: Double? = nil,
        height: Double? = nil,
        paddingTop: Double? = nil,
        paddingBottom: Double? = nil,
        paddingLeft: Double? = nil,
        paddingRight: Double? = nil,
        fontSize: Double? = nil,
        fontWeight: Double? = nil,
        lineHeight: Double? = nil,
        cornerRadius: Double? = nil,
        fillColors: [DesignColour]? = nil,
        textColors: [DesignColour]? = nil,
        hasFocusRing: Bool? = nil,
        minTouchTarget: Double? = nil
    ) {
        self.width = width
        self.height = height
        self.paddingTop = paddingTop
        self.paddingBottom = paddingBottom
        self.paddingLeft = paddingLeft
        self.paddingRight = paddingRight
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.cornerRadius = cornerRadius
        self.fillColors = fillColors
        self.textColors = textColors
        self.hasFocusRing = hasFocusRing
        self.minTouchTarget = minTouchTarget
    }

    private enum CodingKeys: String, CodingKey {
        case width, height
        case paddingTop = "padding_top"
        case paddingBottom = "padding_bottom"
        case paddingLeft = "padding_left"
        case paddingRight = "padding_right"
        case fontSize = "font_size"
        case fontWeight = "font_weight"
        case lineHeight = "line_height"
        case cornerRadius = "corner_radius"
        case fillColors = "fill_colors"
        case textColors = "text_colors"
        case hasFocusRing = "has_focus_ring"
        case minTouchTarget = "min_touch_target"
    }
}

/// Input for ``ParlanceClient/validate(_:)``.
public struct ValidateInput: Encodable, Sendable {
    public let contractId: String
    public let designData: DesignData

    public init(contractId: String, designData: DesignData) {
        self.contractId = contractId
        self.designData = designData
    }

    public struct DesignData: Encodable, Sendable {
        public let componentName: String
        public let properties: DesignProperties
        public let statesPresent: [String]
        public let platform: String

        public init(
            componentName: String,
            properties: DesignProperties,
            statesPresent: [String],
            platform: String
        ) {
            self.componentName = componentName
            self.properties = properties
            self.statesPresent = statesPresent
            self.platform = platform
        }

        private enum CodingKeys: String, CodingKey {
            case componentName = "component_name"
            case properties
            case statesPresent = "states_present"
            case platform
        }
    }

    private enum CodingKeys: String, CodingKey {
        case contractId = "contract_id"
        case designData = "design_data"
    }
}

/// A single check result inside a ``ValidationResult``.
public struct ValidationCheck: Codable, Sendable {
    public let property: String
    public let pass: Bool
    public let note: String?

    private enum CodingKeys: String, CodingKey {
        case property, pass, note
    }
}

/// Response from POST /api/v1/validate.
public struct ValidationResult: Codable, Sendable {
    public let contractName: String
    public let overallPass: Bool
    public let score: Double
    public let checks: [ValidationCheck]

    private enum CodingKeys: String, CodingKey {
        case contractName = "contract_name"
        case overallPass = "overall_pass"
        case score, checks
    }
}

// ---------------------------------------------------------------------------
// MARK: - Standards
// ---------------------------------------------------------------------------

public typealias WcagLevel = String   // "A" | "AA" | "AAA"

public struct StandardsLevelSummary: Codable, Sendable {
    public let pass: Int
    public let total: Int
}

public struct WorstPerformingContract: Codable, Sendable {
    public let contractId: String
    public let contractName: String
    public let score: Double
    /// WCAG conformance level ("A" | "AA" | "AAA"). The platform returns `null`
    /// when a contract has not yet been scored against a target level.
    public let wcagLevel: String?

    private enum CodingKeys: String, CodingKey {
        case contractId = "contract_id"
        case contractName = "contract_name"
        case score
        case wcagLevel = "wcag_level"
    }
}

/// Response from GET /api/v1/projects/:id/standards.
public struct Standard: Codable, Sendable {
    public let projectId: String
    public let averageScore: Double?
    public let totalContracts: Int
    public let byWcagLevel: [String: StandardsLevelSummary]
    public let worstPerforming: [WorstPerformingContract]

    private enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case averageScore = "average_score"
        case totalContracts = "total_contracts"
        case byWcagLevel = "by_wcag_level"
        case worstPerforming = "worst_performing"
    }
}

// ---------------------------------------------------------------------------
// MARK: - Origin (source-of-truth complex enum from xcode)
//
// The TS SDK treats origin as a flat string; the xcode Models/Origin.swift
// models it as a discriminated union for richer type safety.
// The SDK carries the full discriminated-union version so consumers can
// introspect origin data from contract detail responses.
// ---------------------------------------------------------------------------

public struct SnapshotRef: Codable, Sendable, Equatable {
    public let url: String
    public let capturedAt: String
    public let sha256: String?

    public init(url: String, capturedAt: String, sha256: String? = nil) {
        self.url = url
        self.capturedAt = capturedAt
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case url
        case capturedAt = "captured_at"
        case sha256
    }
}

public struct TokenRef: Codable, Sendable, Equatable {
    public let name: String
    public let value: String?

    public init(name: String, value: String? = nil) {
        self.name = name
        self.value = value
    }
}

public struct ComponentRef: Codable, Sendable, Equatable {
    public let key: String
    public let name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

public enum Origin: Codable, Sendable, Equatable {
    case figmaFrame(FigmaFrame)
    case liveURL(LiveURL)
    case imageUpload(ImageUpload)
    case codeComponent(CodeComponent)
    case generated(Generated)
    case legacy(Legacy)
    case unspecified(Unspecified)

    public struct FigmaFrame: Codable, Sendable, Equatable {
        public let fileKey: String
        public let nodeId: String
        public let version: String?
        public let snapshot: SnapshotRef
        public let resolvedTokens: [TokenRef]?
        public let resolvedComponents: [ComponentRef]?

        private enum CodingKeys: String, CodingKey {
            case fileKey = "file_key"
            case nodeId = "node_id"
            case version, snapshot
            case resolvedTokens = "resolved_tokens"
            case resolvedComponents = "resolved_components"
        }
    }

    public struct LiveURL: Codable, Sendable, Equatable {
        public struct Viewport: Codable, Sendable, Equatable {
            public let w: Int
            public let h: Int
        }
        public let url: String
        public let viewport: Viewport
        public let capturedAt: String
        public let snapshot: SnapshotRef
        public let domDump: String?

        private enum CodingKeys: String, CodingKey {
            case url, viewport, snapshot
            case capturedAt = "captured_at"
            case domDump = "dom_dump"
        }
    }

    public struct ImageUpload: Codable, Sendable, Equatable {
        public let snapshot: SnapshotRef
        public let originalFilename: String
        public let uploadedBy: String

        private enum CodingKeys: String, CodingKey {
            case snapshot
            case originalFilename = "original_filename"
            case uploadedBy = "uploaded_by"
        }
    }

    public struct CodeComponent: Codable, Sendable, Equatable {
        public let repoUrl: String
        public let path: String
        public let ref: String
        public let storyName: String?
        public let snapshot: SnapshotRef

        private enum CodingKeys: String, CodingKey {
            case repoUrl = "repo_url"
            case path, ref
            case storyName = "story_name"
            case snapshot
        }
    }

    public struct Generated: Codable, Sendable, Equatable {
        public let prompt: String
        public let model: String
        public let snapshot: SnapshotRef
    }

    public struct Legacy: Codable, Sendable, Equatable {
        public let migratedAt: String
        private enum CodingKeys: String, CodingKey {
            case migratedAt = "migrated_at"
        }
    }

    public struct Unspecified: Codable, Sendable, Equatable {
        public let stampedAt: String
        private enum CodingKeys: String, CodingKey {
            case stampedAt = "stamped_at"
        }
    }

    private enum DiscriminatorKey: String, CodingKey { case type }

    private enum DiscriminatorValue: String {
        case figmaFrame = "figma_frame"
        case liveURL = "live_url"
        case imageUpload = "image_upload"
        case codeComponent = "code_component"
        case generated
        case legacy
        case unspecified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKey.self)
        let raw = try container.decode(String.self, forKey: .type)
        guard let kind = DiscriminatorValue(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown origin type '\(raw)'"
            )
        }
        switch kind {
        case .figmaFrame:    self = .figmaFrame(try FigmaFrame(from: decoder))
        case .liveURL:       self = .liveURL(try LiveURL(from: decoder))
        case .imageUpload:   self = .imageUpload(try ImageUpload(from: decoder))
        case .codeComponent: self = .codeComponent(try CodeComponent(from: decoder))
        case .generated:     self = .generated(try Generated(from: decoder))
        case .legacy:        self = .legacy(try Legacy(from: decoder))
        case .unspecified:   self = .unspecified(try Unspecified(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .figmaFrame(let v):    try v.encode(to: encoder); try writeType(.figmaFrame, encoder: encoder)
        case .liveURL(let v):       try v.encode(to: encoder); try writeType(.liveURL, encoder: encoder)
        case .imageUpload(let v):   try v.encode(to: encoder); try writeType(.imageUpload, encoder: encoder)
        case .codeComponent(let v): try v.encode(to: encoder); try writeType(.codeComponent, encoder: encoder)
        case .generated(let v):     try v.encode(to: encoder); try writeType(.generated, encoder: encoder)
        case .legacy(let v):        try v.encode(to: encoder); try writeType(.legacy, encoder: encoder)
        case .unspecified(let v):   try v.encode(to: encoder); try writeType(.unspecified, encoder: encoder)
        }
    }

    private func writeType(_ value: DiscriminatorValue, encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DiscriminatorKey.self)
        try container.encode(value.rawValue, forKey: .type)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AnyDecodable
// ---------------------------------------------------------------------------

/// A type-erased `Decodable` wrapper for free-form JSON dictionaries.
/// Used for `design_intent`, `props`, `a11y`, and `issues` fields whose
/// exact structure is not fixed by the API contract.
public struct AnyDecodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode(Int.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([AnyDecodable].self) { value = v.map(\.value) }
        else if let v = try? container.decode([String: AnyDecodable].self) {
            value = v.mapValues(\.value)
        } else if container.decodeNil() { value = NSNull() }
        else { throw DecodingError.typeMismatch(Any.self, .init(codingPath: decoder.codingPath, debugDescription: "Cannot decode value")) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:               try container.encode(v)
        case let v as Int:                try container.encode(v)
        case let v as Double:             try container.encode(v)
        case let v as String:             try container.encode(v)
        case let v as [Any]:              try container.encode(v.map { AnyDecodable($0) })
        case let v as [String: Any]:      try container.encode(v.mapValues { AnyDecodable($0) })
        default:                          try container.encodeNil()
        }
    }
}
