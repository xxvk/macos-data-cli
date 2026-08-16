import Foundation

public struct RESTCLIRequest: Sendable {
    public static let maximumParamsBytes = 32 * 1_024
    public static let maximumBodyBytes = 384 * 1_024

    public let route: RESTRouteDescriptor
    public let params: [String: JSONValue]
    public let body: String?
    public let dryRun: Bool
    public let apply: Bool
    public let confirmation: String?
    public let diagnosticSummary: String

    public var internalArguments: [String] {
        var result: [String]
        if route.path == "/contacts/avatar/edit" {
            result = ["contacts", "edit"]
        } else {
            result = route.path.split(separator: "/").map(String.init)
        }
        for param in route.params {
            guard let value = params[param.name] else { continue }
            switch value {
            case .bool(true): result.append("--\(param.name)")
            case .bool(false): continue
            case .string(let value): result += ["--\(param.name)", value]
            case .integer(let value): result += ["--\(param.name)", String(value)]
            case .number(let value): result += ["--\(param.name)", String(value)]
            case .array(let values):
                for case .string(let value) in values { result += ["--\(param.name)", value] }
            default: continue
            }
        }
        if let body { result += ["--inline-json", body] }
        if dryRun { result.append("--dry-run") }
        if apply { result.append("--apply") }
        if let confirmation { result += ["--confirm", confirmation] }
        return result
    }
}

public enum RESTCLIRequestParser {
    public static func parse(_ arguments: [String], manifest: CommandManifest) throws -> RESTCLIRequest {
        guard arguments.count >= 2, let method = RESTMethod(cliValue: arguments[0]) else {
            throw RESTCLIError.legacySyntaxRemoved(nextAction(arguments, routes: manifest.routes))
        }
        let path = arguments[1]
        guard valid(path: path) else { throw RESTCLIError.invalidPath }
        let pathRoutes = manifest.routes.filter { $0.path == path }
        guard !pathRoutes.isEmpty else { throw RESTCLIError.routeNotFound(path) }
        guard let route = pathRoutes.first(where: { $0.method == method }) else {
            throw RESTCLIError.methodNotAllowed(path: path, allowed: pathRoutes.map(\.method.rawValue).sorted())
        }

        let options = try parseOptions(Array(arguments.dropFirst(2)))
        let rawParams = try StrictJSON.object(options.params ?? "{}", maximumBytes: RESTCLIRequest.maximumParamsBytes)
        let params = try validateParams(rawParams, route: route)
        try validateSafety(options, route: route)
        try validateBody(options.body, route: route, schemas: manifest.schemas)
        let paramsText = options.params ?? "{}"
        return RESTCLIRequest(
            route: route, params: params, body: options.body,
            dryRun: options.dryRun, apply: options.apply, confirmation: options.confirmation,
            diagnosticSummary: RESTDiagnosticSummary.make(route: route, params: paramsText, body: options.body)
        )
    }

    private struct Options {
        var params: String?
        var body: String?
        var dryRun = false
        var apply = false
        var confirmation: String?
    }

    private static func parseOptions(_ arguments: [String]) throws -> Options {
        var result = Options()
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard ["--params", "--body", "--dry-run", "--apply", "--confirm"].contains(option),
                  seen.insert(option).inserted else { throw RESTCLIError.invalidRequest("Unknown or repeated option: \(option)") }
            if option == "--dry-run" { result.dryRun = true; index += 1; continue }
            if option == "--apply" { result.apply = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw RESTCLIError.invalidRequest("\(option) requires a value.") }
            switch option {
            case "--params": result.params = arguments[index + 1]
            case "--body": result.body = arguments[index + 1]
            case "--confirm": result.confirmation = arguments[index + 1]
            default: break
            }
            index += 2
        }
        return result
    }

    private static func validateParams(_ object: [String: Any], route: RESTRouteDescriptor) throws -> [String: JSONValue] {
        let definitions = Dictionary(uniqueKeysWithValues: route.params.map { ($0.name, $0) })
        for key in object.keys where definitions[key] == nil { throw RESTCLIError.unknownField(key) }
        for param in route.params where param.required && object[param.name] == nil { throw RESTCLIError.missingField(param.name) }
        return try object.mapValuesWithKeys { key, value in
            guard let param = definitions[key] else { throw RESTCLIError.unknownField(key) }
            return try jsonValue(value, type: param.type, field: key)
        }
    }

    private static func validateSafety(_ options: Options, route: RESTRouteDescriptor) throws {
        guard !(options.dryRun && options.apply) else { throw RESTCLIError.invalidRequest("Use exactly one of --dry-run or --apply.") }
        if options.dryRun && !route.safety.dryRun { throw RESTCLIError.invalidRequest("This route does not support --dry-run.") }
        if options.apply && !route.safety.apply { throw RESTCLIError.invalidRequest("This route does not support --apply.") }
        if route.mutates && route.safety.apply && !options.dryRun && !options.apply {
            throw RESTCLIError.invalidRequest("This route requires exactly one of --dry-run or --apply.")
        }
        if options.confirmation != nil && route.safety.confirmation == nil { throw RESTCLIError.invalidRequest("This route does not accept --confirm.") }
        if options.apply, let expected = route.safety.confirmation, options.confirmation != expected {
            throw RESTCLIError.invalidRequest("--apply requires the exact documented confirmation phrase.")
        }
        if !options.apply && options.confirmation != nil {
            throw RESTCLIError.invalidRequest("--confirm is valid only together with --apply.")
        }
    }

    private static func validateBody(_ body: String?, route: RESTRouteDescriptor, schemas: [String: JSONSchema]) throws {
        guard let schemaName = route.inputSchema else {
            if body != nil { throw RESTCLIError.invalidRequest("This route does not accept --body.") }
            return
        }
        guard let body else { throw RESTCLIError.missingField("body") }
        let object = try StrictJSON.object(body, maximumBytes: RESTCLIRequest.maximumBodyBytes)
        guard let schema = schemas[schemaName] else { throw RESTCLIError.invalidRequest("Route body schema is unavailable.") }
        try RESTJSONSchemaValidator.validate(object, schema: schema, schemas: schemas, field: "body")
    }

    private static func jsonValue(_ value: Any, type: ParamType, field: String) throws -> JSONValue {
        switch type {
        case .string, .file:
            guard let value = value as? String else { throw RESTCLIError.invalidFieldType(field) }
            return .string(value)
        case .stringArray:
            guard let values = value as? [String] else { throw RESTCLIError.invalidFieldType(field) }
            return .array(values.map(JSONValue.string))
        case .int:
            guard let number = value as? NSNumber, !(value is Bool), number.doubleValue.rounded() == number.doubleValue else {
                throw RESTCLIError.invalidFieldType(field)
            }
            return .integer(number.intValue)
        case .bool:
            guard let value = value as? Bool else { throw RESTCLIError.invalidFieldType(field) }
            return .bool(value)
        case .json:
            guard let value = value as? [String: Any] else { throw RESTCLIError.invalidFieldType(field) }
            return .object(value.mapValues { _ in .null })
        }
    }

    private static func valid(path: String) -> Bool {
        path.hasPrefix("/") && path.count > 1 && !path.hasPrefix("//") && !path.hasSuffix("/") &&
            !path.contains("?") && !path.contains("#") && !path.contains("//")
    }

    private static func nextAction(_ arguments: [String], routes: [RESTRouteDescriptor]) -> String {
        if arguments.first == "manifest" { return "Use mpia GET /agent/manifest." }
        if arguments.first == "resources" { return "Use mpia OPTIONS /resources." }
        guard !arguments.isEmpty else { return "Use mpia --help to discover METHOD and PATH." }
        let legacyPath = "/" + arguments.prefix { !$0.hasPrefix("-") }.joined(separator: "/")
        if let route = routes
            .filter({ legacyPath == $0.path || legacyPath.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count }) {
            return "Use mpia \(route.method.rawValue) \(route.path)."
        }
        return "Use mpia --help and mpia GET /agent/manifest."
    }
}

private extension Dictionary where Key == String, Value == Any {
    func mapValuesWithKeys<T>(_ transform: (String, Any) throws -> T) rethrows -> [String: T] {
        try Dictionary<String, T>(uniqueKeysWithValues: map { key, value in (key, try transform(key, value)) })
    }
}
