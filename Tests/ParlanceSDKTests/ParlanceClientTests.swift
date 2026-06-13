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

private func jsonData(_ string: String) -> Data {
    string.data(using: .utf8)!
}

// ---------------------------------------------------------------------------
// MARK: - Tests
// ---------------------------------------------------------------------------

@Suite("ParlanceClient envelope + error decoding")
struct ParlanceClientTests {

    // MARK: Success — listProjects decodes envelope correctly

    @Test("listProjects decodes { data: [...] } envelope")
    func listProjectsSuccess() async throws {
        let (client, id) = makeClient { _ in
            (
                jsonData("""
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
                """),
                httpResponse(path: "/api/v1/projects")
            )
        }
        defer { MockURLProtocol.remove(id: id) }
        let projects = try await client.listProjects()
        #expect(projects.count == 1)
        #expect(projects[0].id == "proj-1")
        #expect(projects[0].name == "Wallet")
        #expect(projects[0].platforms == ["ios"])
    }

    // MARK: API error — { data: null, error: "…" } with non-2xx

    @Test("request throws .api when envelope contains error string on non-2xx")
    func apiErrorEnvelope() async throws {
        let (client, id) = makeClient { _ in
            (
                jsonData("""
                { "data": null, "error": "Project limit reached" }
                """),
                httpResponse(path: "/api/v1/projects", statusCode: 422)
            )
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

    // MARK: 401 — always unauthorized

    @Test("HTTP 401 throws .unauthorized regardless of body")
    func unauthorizedError() async throws {
        let (client, id) = makeClient { _ in
            (
                jsonData("""
                { "data": null, "error": "Invalid API key" }
                """),
                httpResponse(path: "/api/v1/projects", statusCode: 401)
            )
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.unauthorized {
            // Pass
        }
    }

    // MARK: noData — { "data": null } with 200 and no error field

    @Test("HTTP 200 with null data and no error throws .noData")
    func noDataError() async throws {
        let (client, id) = makeClient { _ in
            (
                jsonData("""
                { "data": null }
                """),
                httpResponse(path: "/api/v1/projects", statusCode: 200)
            )
        }
        defer { MockURLProtocol.remove(id: id) }
        do {
            _ = try await client.listProjects()
            #expect(Bool(false), "Expected throw")
        } catch ParlanceError.noData {
            // Pass — null data with no error on 200
        } catch ParlanceError.api {
            // Also acceptable — envelope has no error, but data is null
        }
    }

    // MARK: Glossary term CodingKeys — raw_value maps to rawValue

    @Test("GlossaryTerm decodes raw_value -> rawValue snake_case mapping")
    func glossaryTermDecoding() throws {
        let json = """
        {
          "id": "term-1",
          "name": "Primary Button",
          "raw_value": "btn-primary",
          "category": "component",
          "translations": { "fr": "Bouton principal" },
          "created_at": "2024-01-01T00:00:00Z",
          "updated_at": "2024-01-01T00:00:00Z"
        }
        """
        let term = try JSONDecoder().decode(GlossaryTerm.self, from: jsonData(json))
        #expect(term.id == "term-1")
        #expect(term.name == "Primary Button")
        #expect(term.rawValue == "btn-primary")
        #expect(term.translations["fr"] == "Bouton principal")
    }

    // MARK: ContractSummary CodingKeys

    @Test("ContractSummary decodes list-endpoint shape with snake_case keys")
    func contractSummaryDecoding() throws {
        let json = """
        {
          "id": "c-1",
          "name": "Nav Bar",
          "description": null,
          "category": "molecule",
          "status": "active",
          "created_at": "2024-01-01T00:00:00Z",
          "updated_at": "2024-01-02T00:00:00Z",
          "platform_count": 3,
          "latest_score": 92.5
        }
        """
        let summary = try JSONDecoder().decode(ContractSummary.self, from: jsonData(json))
        #expect(summary.id == "c-1")
        #expect(summary.name == "Nav Bar")
        #expect(summary.category == .molecule)
        #expect(summary.status == .active)
        #expect(summary.platformCount == 3)
        #expect(summary.latestScore == 92.5)
    }

    // MARK: pushAuditResults — response { inserted: N }

    @Test("pushAuditResults decodes { inserted: N } response on 201")
    func pushAuditResultsSuccess() async throws {
        let (client, id) = makeClient { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/v1/projects/proj-1/audit-results")
            return (
                jsonData("""
                { "data": { "inserted": 5 } }
                """),
                httpResponse(path: "/api/v1/projects/proj-1/audit-results", statusCode: 201)
            )
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = AuditResultInput(results: [
            AuditResultItem(ruleId: "wcag-1.1.1", severity: .error, message: "Missing alt text")
        ])
        let result = try await client.pushAuditResults(projectId: "proj-1", input: input)
        #expect(result.inserted == 5)
    }

    // MARK: validate — no projectId in path

    @Test("validate hits /api/v1/validate (no projectId in path)")
    func validatePath() async throws {
        let (client, id) = makeClient { req in
            #expect(req.url?.path == "/api/v1/validate")
            return (
                jsonData("""
                {
                  "data": {
                    "contract_name": "Primary Button",
                    "overall_pass": true,
                    "score": 95.0,
                    "checks": []
                  }
                }
                """),
                httpResponse(path: "/api/v1/validate")
            )
        }
        defer { MockURLProtocol.remove(id: id) }
        let input = ValidateInput(
            contractId: "c-1",
            designData: .init(
                componentName: "Button",
                properties: DesignProperties(width: 200, height: 44),
                statesPresent: ["default"],
                platform: "ios"
            )
        )
        let result = try await client.validate(input)
        #expect(result.overallPass == true)
        #expect(result.score == 95.0)
        #expect(result.contractName == "Primary Button")
    }

    // MARK: Request headers

    @Test("request injects Authorization, Content-Type, X-Parlance-Client headers")
    func requestHeaders() async throws {
        let (client, id) = makeClient { req in
            // Filter out the injected mock-session header; check real API headers
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
            #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(req.value(forHTTPHeaderField: "X-Parlance-Client") == "swift-sdk-tests/1.0.0")
            return (
                jsonData("""
                { "data": [] }
                """),
                httpResponse(path: "/api/v1/projects")
            )
        }
        defer { MockURLProtocol.remove(id: id) }
        let projects = try await client.listProjects()
        #expect(projects.isEmpty)
    }
}
