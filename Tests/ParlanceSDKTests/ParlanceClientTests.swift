import Foundation
import Testing
@testable import ParlanceSDK

// ---------------------------------------------------------------------------
// MARK: - MockURLProtocol
//
// Uses a registry keyed by a session identifier injected via a custom HTTP
// header in URLSessionConfiguration.httpAdditionalHeaders. This avoids
// static state shared across parallel tests.
// ---------------------------------------------------------------------------

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private static let sessionHeaderKey = "X-Mock-Session-ID"
    private static let lock = NSLock()
    private static var registry: [String: Handler] = [:]

    static func makeSession(handler: @escaping Handler) -> (URLSession, String) {
        let id = UUID().uuidString
        lock.lock()
        registry[id] = handler
        lock.unlock()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.httpAdditionalHeaders = [sessionHeaderKey: id]
        return (URLSession(configuration: config), id)
    }

    static func remove(id: String) {
        lock.lock()
        registry.removeValue(forKey: id)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let sessionID = request.value(forHTTPHeaderField: Self.sessionHeaderKey) ?? ""
        Self.lock.lock()
        let handler = Self.registry[sessionID]
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// ---------------------------------------------------------------------------
// MARK: - Test helpers
// ---------------------------------------------------------------------------

private func makeClient(
    handler: @escaping MockURLProtocol.Handler
) -> (ParlanceClient, String) {
    let (session, id) = MockURLProtocol.makeSession(handler: handler)
    let client = ParlanceClient(
        apiKey: "test-key-123",
        baseURL: "https://api.parlancelabs.net",
        clientName: "swift-sdk-tests/1.0.0",
        session: session
    )
    return (client, id)
}

private func httpResponse(path: String, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.parlancelabs.net\(path)")!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    )!
}

private func j(_ string: String) -> Data {
    string.data(using: .utf8)!
}

/// Decode a URLRequest body as JSON.
/// URLSession moves httpBody into httpBodyStream before handing the request to a custom
/// URLProtocol, so we must read from either source.
private func decodeBody<T: Decodable>(_ req: URLRequest, as _: T.Type = T.self) throws -> T {
    let data: Data
    if let body = req.httpBody {
        data = body
    } else if let stream = req.httpBodyStream {
        stream.open()
        var buffer = [UInt8](repeating: 0, count: 4096)
        var result = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 { result.append(contentsOf: buffer[..<count]) }
        }
        stream.close()
        data = result
    } else {
        throw URLError(.badURL)
    }
    return try JSONDecoder().decode(T.self, from: data)
}

// ---------------------------------------------------------------------------
// MARK: - Request Infrastructure
// ---------------------------------------------------------------------------

@Suite("Request headers and common infrastructure")
struct RequestInfrastructureTests {

    @Test("listProjects injects Authorization, Content-Type, X-Parlance-Client headers")
    func requestHeaders() async throws {
        let (client, id) = makeClient { req in
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
            #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(req.value(forHTTPHeaderField: "X-Parlance-Client") == "swift-sdk-tests/1.0.0")
            return (j(#"{"data":[]}"#), httpResponse(path: "/api/v1/projects"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let projects = try await client.listProjects()
        #expect(projects.isEmpty)
    }

    @Test("HTTP 401 throws .unauthorized regardless of body content")
    func unauthorizedError() async throws {
        let (client, id) = makeClient { _ in
            (j(#"{"data":null,"error":"Invalid API key"}"#),
             httpResponse(path: "/api/v1/projects", statusCode: 401))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.unauthorized { /* Pass */ }
    }

    @Test("Non-2xx with JSON error envelope throws .api with status and message")
    func apiErrorEnvelopeNon2xx() async throws {
        let (client, id) = makeClient { _ in
            (j(#"{"data":null,"error":"Project limit reached"}"#),
             httpResponse(path: "/api/v1/projects", statusCode: 422))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.api(let status, let message) {
            #expect(status == 422)
            #expect(message == "Project limit reached")
        }
    }

    @Test("Non-2xx with non-JSON body throws .api with HTTP status code")
    func nonJsonBodyNon2xx() async throws {
        let (client, id) = makeClient { _ in
            ("Internal Server Error".data(using: .utf8)!,
             httpResponse(path: "/api/v1/projects", statusCode: 500))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.api(let status, _) {
            #expect(status == 500)
        }
    }

    @Test("2xx with non-JSON body throws .decoding")
    func nonJsonBody2xx() async throws {
        let (client, id) = makeClient { _ in
            ("not json".data(using: .utf8)!,
             httpResponse(path: "/api/v1/projects", statusCode: 200))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.decoding { /* Pass */ }
    }

    @Test("HTTP 200 with null data and no error field throws .noData")
    func noDataError() async throws {
        let (client, id) = makeClient { _ in
            (j(#"{"data":null}"#),
             httpResponse(path: "/api/v1/projects", statusCode: 200))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.noData { /* Pass */
        } catch ParlanceError.api { /* Also acceptable */ }
    }

    @Test("Error envelope on 200 status throws .api with message")
    func apiErrorOn200() async throws {
        let (client, id) = makeClient { _ in
            (j(#"{"data":null,"error":"downstream failure"}"#),
             httpResponse(path: "/api/v1/projects", statusCode: 200))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.api(let status, let message) {
            #expect(status == 200)
            #expect(message == "downstream failure")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Projects
// ---------------------------------------------------------------------------

@Suite("Projects endpoint")
struct ProjectsTests {

    @Test("listProjects: GET /api/v1/projects, decodes data array envelope")
    func listProjectsSuccess() async throws {
        let body = """
            {
              "data": [
                {
                  "id": "proj-1",
                  "name": "Wallet",
                  "description": "Mobile wallet",
                  "platforms": ["ios"],
                  "created_at": "2024-01-01T00:00:00Z",
                  "updated_at": "2024-01-02T00:00:00Z"
                }
              ]
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path == "/api/v1/projects")
            return (j(body), httpResponse(path: "/api/v1/projects"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let projects = try await client.listProjects()
        #expect(projects.count == 1)
        #expect(projects[0].id == "proj-1")
        #expect(projects[0].name == "Wallet")
        #expect(projects[0].platforms == ["ios"])
    }

    @Test("listProjects: null description decodes to nil")
    func listProjectsNullDescription() async throws {
        let body = """
            {"data":[{"id":"proj-2","name":"Console","description":null,
            "platforms":[],"created_at":"","updated_at":""}]}
            """
        let (client, id) = makeClient { _ in
            (j(body), httpResponse(path: "/api/v1/projects"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let projects = try await client.listProjects()
        #expect(projects[0].description == nil)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Contracts
// ---------------------------------------------------------------------------

@Suite("Contracts endpoints")
struct ContractsTests {

    @Test("getContracts: GET /api/v1/projects/:id/contracts, decodes ContractSummary list")
    func getContractsSuccess() async throws {
        let body = """
            {
              "data": [{
                "id": "c-1", "name": "Primary Button", "description": null,
                "category": "atom", "status": "active",
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-02T00:00:00Z",
                "platform_count": 2, "latest_score": 88.0
              }]
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path == "/api/v1/projects/proj-1/contracts")
            return (j(body), httpResponse(path: "/api/v1/projects/proj-1/contracts"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let contracts = try await client.getContracts(projectId: "proj-1")
        #expect(contracts.count == 1)
        #expect(contracts[0].id == "c-1")
        #expect(contracts[0].category == .atom)
        #expect(contracts[0].status == .active)
        #expect(contracts[0].platformCount == 2)
        #expect(contracts[0].latestScore == 88.0)
    }

    @Test("getContractDetail: GET /api/v1/projects/:id/contracts/:contractId, decodes full Contract")
    func getContractDetailSuccess() async throws {
        let body = """
            {
              "data": {
                "id": "c-1", "name": "Primary Button",
                "description": "Main CTA button",
                "category": "atom", "status": "active",
                "design_intent": {"purpose": "primary action"},
                "origin": null, "platform_specs": [],
                "standards": null, "glossary_terms": [],
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-02T00:00:00Z"
              }
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path == "/api/v1/projects/proj-1/contracts/c-1")
            return (j(body), httpResponse(path: "/api/v1/projects/proj-1/contracts/c-1"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let contract = try await client.getContractDetail(projectId: "proj-1", contractId: "c-1")
        #expect(contract.id == "c-1")
        #expect(contract.name == "Primary Button")
        #expect(contract.status == .active)
        #expect(contract.category == .atom)
    }

    @Test("createContract: POST /api/v1/projects/:id/contracts, encodes body and decodes response")
    func createContractSuccess() async throws {
        struct BodyShape: Decodable { let name: String; let description: String }
        var capturedBody: BodyShape?
        let response = """
            {
              "data": {
                "id": "c-new", "name": "Nav Bar",
                "description": "Top navigation",
                "category": "molecule", "status": "draft",
                "design_intent": {}, "origin": null,
                "platform_specs": [], "standards": null,
                "glossary_terms": [],
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z"
              }
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/v1/projects/proj-1/contracts")
            capturedBody = try decodeBody(req, as: BodyShape.self)
            return (j(response), httpResponse(path: "/api/v1/projects/proj-1/contracts", statusCode: 201))
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = ContractInput(name: "Nav Bar", description: "Top navigation", category: .molecule)
        let contract = try await client.createContract(projectId: "proj-1", input: input)
        #expect(contract.id == "c-new")
        #expect(capturedBody?.name == "Nav Bar")
        #expect(capturedBody?.description == "Top navigation")
    }

    @Test("updateContract: PUT /api/v1/projects/:id/contracts/:contractId, encodes body")
    func updateContractSuccess() async throws {
        struct BodyShape: Decodable { let name: String }
        var capturedBody: BodyShape?
        let response = """
            {
              "data": {
                "id": "c-1", "name": "Nav Bar v2",
                "description": null, "category": "molecule",
                "status": "active", "design_intent": {},
                "origin": null, "platform_specs": [],
                "standards": null, "glossary_terms": [],
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-02T00:00:00Z"
              }
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "PUT")
            #expect(req.url?.path == "/api/v1/projects/proj-1/contracts/c-1")
            capturedBody = try decodeBody(req, as: BodyShape.self)
            return (j(response), httpResponse(path: "/api/v1/projects/proj-1/contracts/c-1"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = ContractInput(name: "Nav Bar v2", description: "")
        let contract = try await client.updateContract(
            projectId: "proj-1", contractId: "c-1", input: input)
        #expect(contract.id == "c-1")
        #expect(capturedBody?.name == "Nav Bar v2")
    }

    @Test("deleteContract: DELETE /api/v1/projects/:id/contracts/:contractId succeeds")
    func deleteContractSuccess() async throws {
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "DELETE")
            #expect(req.url?.path == "/api/v1/projects/proj-1/contracts/c-1")
            return (j(#"{"data":{"deleted":true,"id":"c-1"}}"#),
                    httpResponse(path: "/api/v1/projects/proj-1/contracts/c-1"))
        }
        defer { MockURLProtocol.remove(id: id) }
        try await client.deleteContract(projectId: "proj-1", contractId: "c-1")
    }

    @Test("deleteContract: 404 propagates as .api")
    func deleteContractNotFound() async throws {
        let (client, id) = makeClient { _ in
            (j(#"{"data":null,"error":"Contract not found"}"#),
             httpResponse(path: "/api/v1/projects/proj-1/contracts/c-nope", statusCode: 404))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            try await client.deleteContract(projectId: "proj-1", contractId: "c-nope")
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.api(let status, let message) {
            #expect(status == 404)
            #expect(message == "Contract not found")
        }
    }

    @Test("ContractSummary decodes snake_case keys")
    func contractSummaryDecoding() throws {
        let json = """
            {
              "id": "c-1", "name": "Nav Bar",
              "description": null, "category": "molecule",
              "status": "active",
              "created_at": "2024-01-01T00:00:00Z",
              "updated_at": "2024-01-02T00:00:00Z",
              "platform_count": 3, "latest_score": 92.5
            }
            """
        let summary = try JSONDecoder().decode(ContractSummary.self, from: j(json))
        #expect(summary.id == "c-1")
        #expect(summary.category == .molecule)
        #expect(summary.status == .active)
        #expect(summary.platformCount == 3)
        #expect(summary.latestScore == 92.5)
    }

    @Test("ContractCategory tolerates unknown values (open struct)")
    func contractCategoryUnknown() throws {
        let json = """
            {
              "id": "c-2", "name": "Exotic",
              "description": null, "category": "some-new-category",
              "status": "draft", "created_at": "", "updated_at": "",
              "platform_count": 0, "latest_score": null
            }
            """
        let summary = try JSONDecoder().decode(ContractSummary.self, from: j(json))
        #expect(summary.category?.rawValue == "some-new-category")
    }

    @Test("ContractStatus all enum values decode")
    func contractStatusValues() throws {
        let cases: [(String, ContractStatus)] = [
            ("draft", .draft), ("active", .active),
            ("archived", .archived), ("deprecated", .deprecated),
        ]
        for (raw, expected) in cases {
            let decoded = try JSONDecoder().decode(
                ContractStatus.self, from: "\"\(raw)\"".data(using: .utf8)!)
            #expect(decoded == expected)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Glossary
// ---------------------------------------------------------------------------

@Suite("Glossary endpoints")
struct GlossaryTests {

    @Test("getGlossary: GET /api/v1/projects/:id/glossary, decodes GlossaryTerm list")
    func getGlossarySuccess() async throws {
        let body = """
            {
              "data": [{
                "id": "term-1", "name": "Primary Button",
                "raw_value": "btn-primary", "category": "component",
                "description": "Main CTA",
                "translations": {"fr": "Bouton principal"},
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z"
              }]
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path == "/api/v1/projects/proj-1/glossary")
            return (j(body), httpResponse(path: "/api/v1/projects/proj-1/glossary"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let terms = try await client.getGlossary(projectId: "proj-1")
        #expect(terms.count == 1)
        #expect(terms[0].id == "term-1")
        #expect(terms[0].rawValue == "btn-primary")
        #expect(terms[0].translations["fr"] == "Bouton principal")
    }

    @Test("createGlossaryTerm: POST /api/v1/projects/:id/glossary, encodes body and decodes term")
    func createGlossaryTermSuccess() async throws {
        struct BodyShape: Decodable { let name: String; let raw_value: String }
        var capturedBody: BodyShape?
        let response = """
            {
              "data": {
                "id": "term-new", "name": "Icon Button",
                "raw_value": "btn-icon", "category": "component",
                "description": null, "translations": {},
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-01T00:00:00Z"
              }
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/v1/projects/proj-1/glossary")
            capturedBody = try decodeBody(req, as: BodyShape.self)
            return (j(response), httpResponse(path: "/api/v1/projects/proj-1/glossary", statusCode: 201))
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = GlossaryTermInput(name: "Icon Button", rawValue: "btn-icon", category: "component")
        let term = try await client.createGlossaryTerm(projectId: "proj-1", input: input)
        #expect(term.id == "term-new")
        #expect(capturedBody?.name == "Icon Button")
        #expect(capturedBody?.raw_value == "btn-icon")
    }

    @Test("updateGlossaryTerm: PUT /api/v1/projects/:id/glossary/:termId, encodes body")
    func updateGlossaryTermSuccess() async throws {
        struct BodyShape: Decodable { let name: String }
        var capturedBody: BodyShape?
        let response = """
            {
              "data": {
                "id": "term-1", "name": "Updated Button",
                "raw_value": "btn-primary", "category": "component",
                "description": null, "translations": {},
                "created_at": "2024-01-01T00:00:00Z",
                "updated_at": "2024-01-02T00:00:00Z"
              }
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "PUT")
            #expect(req.url?.path == "/api/v1/projects/proj-1/glossary/term-1")
            capturedBody = try decodeBody(req, as: BodyShape.self)
            return (j(response), httpResponse(path: "/api/v1/projects/proj-1/glossary/term-1"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = GlossaryTermInput(name: "Updated Button", rawValue: "btn-primary")
        let term = try await client.updateGlossaryTerm(
            projectId: "proj-1", termId: "term-1", input: input)
        #expect(term.id == "term-1")
        #expect(capturedBody?.name == "Updated Button")
    }

    @Test("deleteGlossaryTerm: DELETE /api/v1/projects/:id/glossary/:termId succeeds")
    func deleteGlossaryTermSuccess() async throws {
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "DELETE")
            #expect(req.url?.path == "/api/v1/projects/proj-1/glossary/term-1")
            return (j(#"{"data":{"deleted":true,"id":"term-1"}}"#),
                    httpResponse(path: "/api/v1/projects/proj-1/glossary/term-1"))
        }
        defer { MockURLProtocol.remove(id: id) }
        try await client.deleteGlossaryTerm(projectId: "proj-1", termId: "term-1")
    }

    @Test("GlossaryTerm decodes raw_value -> rawValue snake_case mapping")
    func glossaryTermSnakeCaseDecoding() throws {
        let json = """
            {
              "id": "term-1", "name": "Primary Button",
              "raw_value": "btn-primary", "category": "component",
              "translations": {"fr": "Bouton principal"},
              "created_at": "2024-01-01T00:00:00Z",
              "updated_at": "2024-01-01T00:00:00Z"
            }
            """
        let term = try JSONDecoder().decode(GlossaryTerm.self, from: j(json))
        #expect(term.rawValue == "btn-primary")
        #expect(term.translations["fr"] == "Bouton principal")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Audit Results
// ---------------------------------------------------------------------------

@Suite("Audit results endpoint")
struct AuditResultsTests {

    @Test("pushAuditResults: POST /api/v1/projects/:id/audit-results, decodes { inserted: N }")
    func pushAuditResultsSuccess() async throws {
        struct BodyShape: Decodable {
            struct Item: Decodable { let rule_id: String; let severity: String }
            let results: [Item]
        }
        var capturedBody: BodyShape?
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/v1/projects/proj-1/audit-results")
            capturedBody = try decodeBody(req, as: BodyShape.self)
            return (j(#"{"data":{"inserted":3}}"#),
                    httpResponse(path: "/api/v1/projects/proj-1/audit-results", statusCode: 201))
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = AuditResultInput(results: [
            AuditResultItem(ruleId: "wcag-1.1.1", severity: .error, message: "Missing alt text"),
            AuditResultItem(ruleId: "wcag-2.5.8", severity: .warning, message: "Touch target"),
            AuditResultItem(ruleId: "wcag-1.4.3", severity: .info, message: "Low contrast"),
        ])
        let result = try await client.pushAuditResults(projectId: "proj-1", input: input)
        #expect(result.inserted == 3)
        #expect(capturedBody?.results.count == 3)
        #expect(capturedBody?.results[0].rule_id == "wcag-1.1.1")
        #expect(capturedBody?.results[0].severity == "error")
    }

    @Test("pushAuditResults: 401 propagates as .unauthorized")
    func pushAuditResultsUnauthorized() async throws {
        let (client, id) = makeClient { _ in
            (j(#"{"data":null,"error":"Unauthorized"}"#),
             httpResponse(path: "/api/v1/projects/proj-1/audit-results", statusCode: 401))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.pushAuditResults(
                projectId: "proj-1", input: AuditResultInput(results: []))
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.unauthorized { /* Pass */ }
    }

    @Test("AuditResultItem encodes rule_id / file_path / element_selector as snake_case")
    func auditResultItemSnakeCaseEncoding() throws {
        let item = AuditResultItem(
            ruleId: "wcag-1.1.1",
            severity: .error,
            message: "Alt text missing",
            filePath: "Views/Button.swift",
            elementSelector: ".btn"
        )
        struct Probe: Decodable {
            let rule_id: String
            let severity: String
            let file_path: String?
            let element_selector: String?
        }
        let probe = try JSONDecoder().decode(Probe.self, from: JSONEncoder().encode(item))
        #expect(probe.rule_id == "wcag-1.1.1")
        #expect(probe.severity == "error")
        #expect(probe.file_path == "Views/Button.swift")
        #expect(probe.element_selector == ".btn")
    }
}

// ---------------------------------------------------------------------------
// MARK: - Validate
// ---------------------------------------------------------------------------

@Suite("Validate endpoint")
struct ValidateTests {

    @Test("validate: POST /api/v1/validate (no projectId in path), decodes ValidationResult")
    func validateSuccess() async throws {
        struct BodyShape: Decodable {
            let contract_id: String
            let design_data: DD
            struct DD: Decodable {
                let component_name: String
                let states_present: [String]
                let platform: String
            }
        }
        var capturedBody: BodyShape?
        let response = """
            {
              "data": {
                "contract_name": "Primary Button",
                "overall_pass": true, "score": 95.0,
                "checks": [{"property": "touch_target", "pass": true, "note": null}]
              }
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/v1/validate")
            capturedBody = try decodeBody(req, as: BodyShape.self)
            return (j(response), httpResponse(path: "/api/v1/validate"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = ValidateInput(
            contractId: "c-1",
            designData: .init(
                componentName: "Button",
                properties: DesignProperties(width: 200, height: 44),
                statesPresent: ["default", "disabled"],
                platform: "ios"
            )
        )
        let result = try await client.validate(input)
        #expect(result.overallPass == true)
        #expect(result.score == 95.0)
        #expect(result.contractName == "Primary Button")
        #expect(result.checks.count == 1)
        #expect(result.checks[0].property == "touch_target")
        #expect(capturedBody?.contract_id == "c-1")
        #expect(capturedBody?.design_data.component_name == "Button")
        #expect(capturedBody?.design_data.states_present == ["default", "disabled"])
        #expect(capturedBody?.design_data.platform == "ios")
    }

    @Test("validate: 404 API error propagates as .api")
    func validateApiError() async throws {
        let (client, id) = makeClient { _ in
            (j(#"{"data":null,"error":"Contract not found"}"#),
             httpResponse(path: "/api/v1/validate", statusCode: 404))
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = ValidateInput(
            contractId: "c-missing",
            designData: .init(
                componentName: "Button",
                properties: DesignProperties(),
                statesPresent: [],
                platform: "ios"
            )
        )
        do {
            _ = try await client.validate(input)
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.api(let status, let message) {
            #expect(status == 404)
            #expect(message == "Contract not found")
        }
    }

    @Test("ValidationResult decodes snake_case keys")
    func validationResultSnakeCaseDecoding() throws {
        let json = """
            {
              "contract_name": "Nav Bar", "overall_pass": false,
              "score": 60.0,
              "checks": [
                {"property": "font_size", "pass": false, "note": "Too small"},
                {"property": "color_contrast", "pass": true, "note": null}
              ]
            }
            """
        let result = try JSONDecoder().decode(ValidationResult.self, from: j(json))
        #expect(result.contractName == "Nav Bar")
        #expect(result.overallPass == false)
        #expect(result.checks.count == 2)
        #expect(result.checks[0].note == "Too small")
        #expect(result.checks[1].note == nil)
    }

    @Test("ValidateInput encodes contract_id and design_data snake_case keys")
    func validateInputSnakeCaseEncoding() throws {
        let input = ValidateInput(
            contractId: "c-42",
            designData: .init(
                componentName: "Toggle",
                properties: DesignProperties(),
                statesPresent: ["on", "off"],
                platform: "figma"
            )
        )
        struct Probe: Decodable {
            let contract_id: String
            let design_data: DD
            struct DD: Decodable {
                let component_name: String
                let states_present: [String]
                let platform: String
            }
        }
        let probe = try JSONDecoder().decode(Probe.self, from: JSONEncoder().encode(input))
        #expect(probe.contract_id == "c-42")
        #expect(probe.design_data.component_name == "Toggle")
        #expect(probe.design_data.states_present == ["on", "off"])
        #expect(probe.design_data.platform == "figma")
    }

    @Test("DesignProperties encodes snake_case keys for all non-nil fields")
    func designPropertiesSnakeCaseEncoding() throws {
        let props = DesignProperties(
            width: 320, height: 44, fontSize: 16, hasFocusRing: true)
        struct Probe: Decodable {
            let width: Double?
            let height: Double?
            let font_size: Double?
            let has_focus_ring: Bool?
        }
        let probe = try JSONDecoder().decode(Probe.self, from: JSONEncoder().encode(props))
        #expect(probe.width == 320)
        #expect(probe.height == 44)
        #expect(probe.font_size == 16)
        #expect(probe.has_focus_ring == true)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Standards
// ---------------------------------------------------------------------------

@Suite("Standards endpoint")
struct StandardsTests {

    @Test("getStandards: GET /api/v1/projects/:id/standards, decodes Standard")
    func getStandardsSuccess() async throws {
        let body = """
            {
              "data": {
                "project_id": "proj-1",
                "average_score": 87.5, "total_contracts": 12,
                "by_wcag_level": {
                  "A": {"pass": 10, "total": 12},
                  "AA": {"pass": 8, "total": 12}
                },
                "worst_performing": [{
                  "contract_id": "c-bad",
                  "contract_name": "Legacy Form",
                  "score": 42.0, "wcag_level": "AA"
                }]
              }
            }
            """
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "GET")
            #expect(req.url?.path == "/api/v1/projects/proj-1/standards")
            return (j(body), httpResponse(path: "/api/v1/projects/proj-1/standards"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let standards = try await client.getStandards(projectId: "proj-1")
        #expect(standards.projectId == "proj-1")
        #expect(standards.averageScore == 87.5)
        #expect(standards.totalContracts == 12)
        #expect(standards.byWcagLevel["A"]?.pass == 10)
        #expect(standards.byWcagLevel["AA"]?.total == 12)
        #expect(standards.worstPerforming.count == 1)
        #expect(standards.worstPerforming[0].contractId == "c-bad")
        #expect(standards.worstPerforming[0].score == 42.0)
    }

    @Test("getStandards: null averageScore decodes to nil")
    func getStandardsNullAverage() async throws {
        let body = """
            {"data":{"project_id":"proj-empty","average_score":null,
            "total_contracts":0,"by_wcag_level":{},"worst_performing":[]}}
            """
        let (client, id) = makeClient { _ in
            (j(body), httpResponse(path: "/api/v1/projects/proj-empty/standards"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let standards = try await client.getStandards(projectId: "proj-empty")
        #expect(standards.averageScore == nil)
        #expect(standards.worstPerforming.isEmpty)
    }

    @Test("Standard decodes snake_case keys correctly")
    func standardSnakeCaseDecoding() throws {
        let json = """
            {
              "project_id": "proj-1", "average_score": 75.0,
              "total_contracts": 5,
              "by_wcag_level": {"A": {"pass": 4, "total": 5}},
              "worst_performing": [{
                "contract_id": "c-1", "contract_name": "Old Modal",
                "score": 50.0, "wcag_level": "A"
              }]
            }
            """
        let standard = try JSONDecoder().decode(Standard.self, from: j(json))
        #expect(standard.projectId == "proj-1")
        #expect(standard.byWcagLevel["A"]?.pass == 4)
        #expect(standard.worstPerforming[0].contractName == "Old Modal")
        #expect(standard.worstPerforming[0].wcagLevel == "A")
    }

    @Test("getStandards: null worst_performing wcag_level decodes to nil")
    func getStandardsNullWcagLevel() async throws {
        // The live API returns wcag_level: null for not-yet-scored contracts.
        let body = """
            {
              "data": {
                "project_id": "proj-1", "average_score": 85.0,
                "total_contracts": 9, "by_wcag_level": {},
                "worst_performing": [{
                  "contract_id": "c-x", "contract_name": "Navbar",
                  "score": 79.0, "wcag_level": null
                }]
              }
            }
            """
        let (client, id) = makeClient { _ in
            (j(body), httpResponse(path: "/api/v1/projects/proj-1/standards"))
        }
        defer { MockURLProtocol.remove(id: id) }
        let standards = try await client.getStandards(projectId: "proj-1")
        #expect(standards.worstPerforming.count == 1)
        #expect(standards.worstPerforming[0].contractName == "Navbar")
        #expect(standards.worstPerforming[0].wcagLevel == nil)
    }
}

// ---------------------------------------------------------------------------
// MARK: - testConnection
// ---------------------------------------------------------------------------

@Suite("testConnection")
struct TestConnectionTests {

    @Test("testConnection: health 200 + projects auth returns true")
    func testConnectionSuccess() async throws {
        var requestCount = 0
        let (client, id) = makeClient { req in
            requestCount += 1
            if req.url?.path == "/api/v1/health" {
                return (j(#"{"status":"ok"}"#),
                        HTTPURLResponse(
                            url: req.url!, statusCode: 200,
                            httpVersion: "HTTP/1.1", headerFields: nil)!)
            } else {
                #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
                return (j(#"{"data":[]}"#), httpResponse(path: "/api/v1/projects"))
            }
        }
        defer { MockURLProtocol.remove(id: id) }
        let ok = try await client.testConnection()
        #expect(ok == true)
        #expect(requestCount == 2)
    }

    @Test("testConnection: health 500 throws .api")
    func testConnectionHealthFails() async throws {
        let (client, id) = makeClient { req in
            if req.url?.path == "/api/v1/health" {
                return (Data(),
                        HTTPURLResponse(
                            url: req.url!, statusCode: 500,
                            httpVersion: "HTTP/1.1", headerFields: nil)!)
            }
            return (Data(), httpResponse(path: req.url!.path))
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.testConnection()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.api(let status, _) {
            #expect(status == 0)  // testConnection uses status 0 for "cannot reach" path
        }
    }

    @Test("testConnection: projects 401 throws .unauthorized")
    func testConnectionProjectsUnauthorized() async throws {
        let (client, id) = makeClient { req in
            if req.url?.path == "/api/v1/health" {
                return (j(#"{"status":"ok"}"#),
                        HTTPURLResponse(
                            url: req.url!, statusCode: 200,
                            httpVersion: "HTTP/1.1", headerFields: nil)!)
            } else {
                return (j(#"{"data":null,"error":"Unauthorized"}"#),
                        httpResponse(path: "/api/v1/projects", statusCode: 401))
            }
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.testConnection()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.unauthorized { /* Pass */ }
    }
}
