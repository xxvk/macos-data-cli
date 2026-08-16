import Foundation

public enum RESTMethod: String, Codable, CaseIterable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
    case options = "OPTIONS"

    public init?(cliValue: String) {
        self.init(rawValue: cliValue.uppercased())
    }
}

public struct RESTRouteDescriptor: Codable, Sendable {
    public let method: RESTMethod
    public let path: String
    public let description: String
    public let mutates: Bool
    public let params: [CommandParam]
    public let exitCodes: [ExitCodeSpec]
    public let safety: CommandSafety
    public let inputSchema: String?
    public let outputSchema: String?

    public init(method: RESTMethod, path: String, command: CommandNode) {
        self.method = method
        self.path = path
        description = command.description
        mutates = command.mutates
        var routeParams = Self.publicParams(command.params, hasBody: command.inputSchema != nil)
        if path.hasPrefix("/contacts/") && !["/contacts/containers", "/contacts/permission"].contains(path) {
            routeParams.append(CommandParam(name: "container", type: .string, required: false, description: "iCloud or exact container identifier"))
        }
        if path.hasPrefix("/calendar/") && !["/calendar/sources", "/calendar/permission"].contains(path) {
            routeParams.append(CommandParam(name: "source", type: .string, required: false, description: "iCloud or exact EventKit source identifier"))
        }
        if path.hasPrefix("/reminders/") && !["/reminders/sources", "/reminders/permission"].contains(path) {
            routeParams.append(CommandParam(name: "source", type: .string, required: false, description: "iCloud or exact EventKit source identifier"))
        }
        params = routeParams
        exitCodes = command.exitCodes
        safety = command.safety
        inputSchema = command.inputSchema
        outputSchema = command.outputSchema
    }

    private static func publicParams(_ params: [CommandParam], hasBody: Bool) -> [CommandParam] {
        let reserved = Set(["apply", "dry-run", "confirm", "format", "stdin"])
        return params.filter { param in
            !reserved.contains(param.name) && !(hasBody && param.name == "input")
        }
    }
}

extension CommandRegistry {
    static func restRoutes(from commands: [CommandNode]) -> [RESTRouteDescriptor] {
        commands.flatMap { command in
            if command.kind == .leaf {
                return [RESTRouteDescriptor(method: restMethod(for: command), path: "/\(command.name)", command: command)]
            }
            return (command.subcommands ?? []).map { leaf in
                let suffix = leaf.name.split(separator: " ").joined(separator: "/")
                return RESTRouteDescriptor(
                    method: restMethod(for: leaf),
                    path: "/\(command.name)/\(suffix)",
                    command: leaf
                )
            }
        }.sorted { ($0.path, $0.method.rawValue) < ($1.path, $1.method.rawValue) }
    }

    static func restMethod(for command: CommandNode) -> RESTMethod {
        let name = command.name.lowercased()
        if name.contains("permission") || name.contains("doctor") || name.contains("verify") ||
            ["resources", "containers", "sources"].contains(name) { return .options }
        if ["count", "container", "version"].contains(name) { return .head }
        if name.contains("export") || name.contains("run") || name.contains("reveal") ||
            name.contains("build") || name.contains("validate") { return .post }
        if !command.mutates { return .get }
        if name.contains("delete") || name.contains("forget") { return .delete }
        if name.contains("edit-body") || name.contains("replace") || name == "update" { return .put }
        if name.contains("edit") || name.contains("rename") || name.contains("move") { return .patch }
        return .post
    }
}
