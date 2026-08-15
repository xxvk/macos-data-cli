import Foundation

/// A machine-readable registry of every CLI command. This is the single source
/// of truth from which agent tool schemas and human documentation are derived,
/// so it must stay in sync with the argument parser.
///
/// It is deliberately framework-free and lives in `Core` so it has no
/// dependency on the executable target or on any adapter.
public struct CommandManifest: Codable, Sendable {
    public let cli: CLIDescriptor
    public let commands: [CommandNode]
    /// Named JSON Schemas referenced by `CommandNode.inputSchema`/`outputSchema`.
    public let schemas: [String: JSONSchema]

    public init(cli: CLIDescriptor, commands: [CommandNode], schemas: [String: JSONSchema] = [:]) {
        self.cli = cli
        self.commands = commands
        self.schemas = schemas
    }
}

public struct CLIDescriptor: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// One command (a leaf) or a command group that contains subcommands.
public struct CommandNode: Codable, Sendable {
    public let name: String
    public let kind: CommandNodeKind
    public let description: String
    public let usage: String
    /// Whether this command can mutate user data. Read-only commands are false.
    public let mutates: Bool
    public let params: [CommandParam]
    public let exitCodes: [ExitCodeSpec]
    public let safety: CommandSafety
    /// Name of a schema in `CommandManifest.schemas` for the `--input`/`--stdin`
    /// JSON payload. `nil` when the command accepts no structured input.
    public let inputSchema: String?
    /// Name of a schema in `CommandManifest.schemas` for the success `data`.
    public let outputSchema: String?
    /// Present only for `.group` nodes.
    public let subcommands: [CommandNode]?

    public init(
        name: String,
        kind: CommandNodeKind,
        description: String,
        usage: String,
        mutates: Bool,
        params: [CommandParam],
        exitCodes: [ExitCodeSpec],
        safety: CommandSafety,
        inputSchema: String? = nil,
        outputSchema: String? = nil,
        subcommands: [CommandNode]? = nil
    ) {
        self.name = name
        self.kind = kind
        self.description = description
        self.usage = usage
        self.mutates = mutates
        self.params = params
        self.exitCodes = exitCodes
        self.safety = safety
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.subcommands = subcommands
    }
}

public enum CommandNodeKind: String, Codable, Sendable {
    case group
    case leaf
}

/// A single CLI flag or positional argument.
public struct CommandParam: Codable, Sendable {
    public let name: String
    public let type: ParamType
    public let required: Bool
    public let description: String
    public let defaultValue: String?

    public init(
        name: String,
        type: ParamType,
        required: Bool,
        description: String,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        self.defaultValue = defaultValue
    }
}

public enum ParamType: String, Codable, Sendable {
    case string
    case int
    case bool
    case file
    /// JSON payload supplied through `--input <file>` or `--stdin`.
    case json
}

/// A stable process exit code plus the JSON `error.code` it carries.
public struct ExitCodeSpec: Codable, Sendable {
    public let code: Int
    public let errorCode: String
    public let description: String

    public init(code: Int, errorCode: String, description: String) {
        self.code = code
        self.errorCode = errorCode
        self.description = description
    }
}

/// The write-safety surface of a command. Agents must not supply `confirmation`
/// automatically; that is the user's explicit approval.
public struct CommandSafety: Codable, Sendable {
    public let dryRun: Bool
    public let apply: Bool
    public let confirmation: String?

    public init(dryRun: Bool, apply: Bool, confirmation: String? = nil) {
        self.dryRun = dryRun
        self.apply = apply
        self.confirmation = confirmation
    }

    public static let readOnly = CommandSafety(dryRun: false, apply: false, confirmation: nil)
}
