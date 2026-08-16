import Foundation

public enum RESTCLIError: Error, Equatable, Sendable {
    case legacySyntaxRemoved(String)
    case invalidRequest(String)
    case invalidPath
    case routeNotFound(String)
    case methodNotAllowed(path: String, allowed: [String])
    case invalidJSON
    case jsonObjectRequired
    case duplicateJSONKey(String)
    case payloadTooLarge(Int)
    case unknownField(String)
    case missingField(String)
    case invalidFieldType(String)

    public var machineCode: String {
        switch self {
        case .legacySyntaxRemoved: "LEGACY_SYNTAX_REMOVED"
        case .routeNotFound: "ROUTE_NOT_FOUND"
        case .methodNotAllowed: "METHOD_NOT_ALLOWED"
        default: "INVALID_REQUEST"
        }
    }

    public var message: String {
        switch self {
        case .legacySyntaxRemoved(let action): "Legacy command syntax was removed in 0.9.3. \(action)"
        case .invalidRequest(let reason): reason
        case .invalidPath: "Route path must start with one slash and must not contain a query, fragment, or trailing slash."
        case .routeNotFound(let path): "Unknown route: \(path)"
        case .methodNotAllowed(let path, let methods): "Method is not allowed for \(path). Allowed: \(methods.joined(separator: ", "))."
        case .invalidJSON: "--params and --body require strict JSON."
        case .jsonObjectRequired: "--params and --body must contain a JSON object."
        case .duplicateJSONKey(let key): "Duplicate JSON field is not allowed: \(key)"
        case .payloadTooLarge(let bytes): "Inline JSON exceeds the \(bytes)-byte limit."
        case .unknownField(let field): "Unknown request field: \(field)"
        case .missingField(let field): "Required request field is missing: \(field)"
        case .invalidFieldType(let field): "Request field has the wrong JSON type: \(field)"
        }
    }
}
