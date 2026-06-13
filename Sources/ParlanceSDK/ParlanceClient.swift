import Foundation

// ---------------------------------------------------------------------------
// MARK: - Internal envelope
// ---------------------------------------------------------------------------

private struct APIEnvelope<T: Decodable>: Decodable {
    let data: T?
    let error: String?
}

// ---------------------------------------------------------------------------
// MARK: - ParlanceClient
// ---------------------------------------------------------------------------

/// The Swift counterpart to the TypeScript `@parlance/sdk` `ParlanceClient`.
///
/// Usage:
/// ```swift
/// let client = ParlanceClient(apiKey: "pk_live_…", clientName: "xcode-extension/1.0.0")
/// let projects = try await client.listProjects()
/// ```
public final class ParlanceClient: @unchecked Sendable {

    private let apiKey: String
    private let baseURL: String
    private let clientName: String
    private let session: URLSession

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// - Parameters:
    ///   - apiKey: Parlance API key — sent as `Authorization: Bearer …`.
    ///   - baseURL: Override the API base URL. Defaults to `https://api.parlancelabs.net`.
    ///   - clientName: Identifies the caller, e.g. `xcode-extension/1.0.0`. Sent as `X-Parlance-Client`.
    ///   - session: Injectable `URLSession` (useful in tests).
    public init(
        apiKey: String,
        baseURL: String = "https://api.parlancelabs.net",
        clientName: String,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.clientName = clientName
        self.session = session
    }

    // -------------------------------------------------------------------------
    // MARK: - Core request helper
    // -------------------------------------------------------------------------

    private func makeRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw ParlanceError.transport(URLError(.badURL))
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientName, forHTTPHeaderField: "X-Parlance-Client")
        if let body { req.httpBody = body }
        return req
    }

    /// Executes the request, checks HTTP status, decodes the `{ data, error }` envelope
    /// and returns `data`, or throws a typed ``ParlanceError``.
    private func request<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let http: HTTPURLResponse

        do {
            let (d, response) = try await session.data(for: req)
            guard let h = response as? HTTPURLResponse else {
                throw ParlanceError.transport(URLError(.badServerResponse))
            }
            data = d
            http = h
        } catch let err as ParlanceError {
            throw err
        } catch {
            throw ParlanceError.transport(error)
        }

        // 401 — always unauthorised, regardless of body content
        if http.statusCode == 401 {
            throw ParlanceError.unauthorized
        }

        // Try to decode envelope for both success and error paths
        let envelope: APIEnvelope<T>
        do {
            envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
        } catch {
            // Non-2xx without a JSON envelope
            if !(200..<300).contains(http.statusCode) {
                throw ParlanceError.api(
                    status: http.statusCode,
                    message: "HTTP \(http.statusCode)"
                )
            }
            throw ParlanceError.decoding(error)
        }

        // API-layer error (can come with any status code)
        if let apiError = envelope.error, !apiError.isEmpty {
            throw ParlanceError.api(status: http.statusCode, message: apiError)
        }

        guard let value = envelope.data else {
            throw ParlanceError.noData
        }
        return value
    }

    /// A variant that encodes an `Encodable` body to JSON before sending.
    private func request<Body: Encodable, Response: Decodable>(
        _ req: URLRequest,
        body: Body
    ) async throws -> Response {
        var mutable = req
        do {
            mutable.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ParlanceError.transport(error)
        }
        return try await request(mutable)
    }

    // -------------------------------------------------------------------------
    // MARK: - Connection / auth
    // -------------------------------------------------------------------------

    /// Validates connectivity and the API key.
    /// Hits `GET /api/v1/health` (no auth), then `GET /api/v1/projects` (requires auth).
    /// Returns `true` on success; throws ``ParlanceError`` on failure.
    @discardableResult
    public func testConnection() async throws -> Bool {
        guard let healthURL = URL(string: baseURL + "/api/v1/health") else {
            throw ParlanceError.transport(URLError(.badURL))
        }
        let (_, healthResponse) = try await {
            do { return try await session.data(from: healthURL) }
            catch { throw ParlanceError.transport(error) }
        }()
        guard let http = healthResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ParlanceError.api(status: 0, message: "Cannot reach Parlance API")
        }
        let _: [Project] = try await request(try makeRequest(path: "/api/v1/projects"))
        return true
    }

    // -------------------------------------------------------------------------
    // MARK: - Projects
    // -------------------------------------------------------------------------

    /// GET /api/v1/projects
    public func listProjects() async throws -> [Project] {
        try await request(try makeRequest(path: "/api/v1/projects"))
    }

    // -------------------------------------------------------------------------
    // MARK: - Contracts
    // -------------------------------------------------------------------------

    /// GET /api/v1/projects/:projectId/contracts — returns the lighter ``ContractSummary`` list.
    public func getContracts(projectId: String) async throws -> [ContractSummary] {
        try await request(try makeRequest(path: "/api/v1/projects/\(projectId)/contracts"))
    }

    /// GET /api/v1/projects/:projectId/contracts/:contractId — returns the full ``Contract``.
    public func getContractDetail(projectId: String, contractId: String) async throws -> Contract {
        try await request(try makeRequest(
            path: "/api/v1/projects/\(projectId)/contracts/\(contractId)"
        ))
    }

    /// POST /api/v1/projects/:projectId/contracts
    public func createContract(projectId: String, input: ContractInput) async throws -> Contract {
        let req = try makeRequest(path: "/api/v1/projects/\(projectId)/contracts", method: "POST")
        return try await request(req, body: input)
    }

    /// PUT /api/v1/projects/:projectId/contracts/:contractId
    public func updateContract(
        projectId: String,
        contractId: String,
        input: ContractInput
    ) async throws -> Contract {
        let req = try makeRequest(
            path: "/api/v1/projects/\(projectId)/contracts/\(contractId)",
            method: "PUT"
        )
        return try await request(req, body: input)
    }

    /// DELETE /api/v1/projects/:projectId/contracts/:contractId
    public func deleteContract(projectId: String, contractId: String) async throws {
        struct DeleteResponse: Decodable { let deleted: Bool; let id: String }
        let _: DeleteResponse = try await request(try makeRequest(
            path: "/api/v1/projects/\(projectId)/contracts/\(contractId)",
            method: "DELETE"
        ))
    }

    // -------------------------------------------------------------------------
    // MARK: - Glossary
    // -------------------------------------------------------------------------

    /// GET /api/v1/projects/:projectId/glossary
    public func getGlossary(projectId: String) async throws -> [GlossaryTerm] {
        try await request(try makeRequest(path: "/api/v1/projects/\(projectId)/glossary"))
    }

    /// POST /api/v1/projects/:projectId/glossary
    public func createGlossaryTerm(
        projectId: String,
        input: GlossaryTermInput
    ) async throws -> GlossaryTerm {
        let req = try makeRequest(path: "/api/v1/projects/\(projectId)/glossary", method: "POST")
        return try await request(req, body: input)
    }

    /// PUT /api/v1/projects/:projectId/glossary/:termId
    public func updateGlossaryTerm(
        projectId: String,
        termId: String,
        input: GlossaryTermInput
    ) async throws -> GlossaryTerm {
        let req = try makeRequest(
            path: "/api/v1/projects/\(projectId)/glossary/\(termId)",
            method: "PUT"
        )
        return try await request(req, body: input)
    }

    /// DELETE /api/v1/projects/:projectId/glossary/:termId
    public func deleteGlossaryTerm(projectId: String, termId: String) async throws {
        struct DeleteResponse: Decodable { let deleted: Bool; let id: String }
        let _: DeleteResponse = try await request(try makeRequest(
            path: "/api/v1/projects/\(projectId)/glossary/\(termId)",
            method: "DELETE"
        ))
    }

    // -------------------------------------------------------------------------
    // MARK: - Audit Results
    // -------------------------------------------------------------------------

    /// POST /api/v1/projects/:projectId/audit-results
    public func pushAuditResults(
        projectId: String,
        input: AuditResultInput
    ) async throws -> AuditResult {
        let req = try makeRequest(
            path: "/api/v1/projects/\(projectId)/audit-results",
            method: "POST"
        )
        return try await request(req, body: input)
    }

    // -------------------------------------------------------------------------
    // MARK: - Validate
    // -------------------------------------------------------------------------

    /// POST /api/v1/validate
    /// Note: no projectId in the path — the contractId is in the request body.
    public func validate(_ input: ValidateInput) async throws -> ValidationResult {
        let req = try makeRequest(path: "/api/v1/validate", method: "POST")
        return try await request(req, body: input)
    }

    // -------------------------------------------------------------------------
    // MARK: - Standards
    // -------------------------------------------------------------------------

    /// GET /api/v1/projects/:projectId/standards
    public func getStandards(projectId: String) async throws -> Standard {
        try await request(try makeRequest(path: "/api/v1/projects/\(projectId)/standards"))
    }
}
