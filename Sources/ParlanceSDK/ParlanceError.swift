import Foundation

/// Errors thrown by ``ParlanceClient``.
public enum ParlanceError: Error, LocalizedError, Sendable {
    /// The API key was rejected (HTTP 401).
    case unauthorized
    /// The API returned a non-2xx status code, optionally with a message.
    case api(status: Int, message: String)
    /// A successful HTTP response contained no `data` field.
    case noData
    /// A transport-level error (network unreachable, DNS failure, etc.).
    case transport(Error)
    /// The response body could not be decoded.
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Invalid or revoked API key."
        case .api(let status, let message):
            return "API error (\(status)): \(message)"
        case .noData:
            return "The server returned no data."
        case .transport(let error):
            return "Transport error: \(error.localizedDescription)"
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
