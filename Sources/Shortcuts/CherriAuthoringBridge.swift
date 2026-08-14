import Core
import Darwin
import Foundation

public enum ShortcutSigningMode: String, Codable, Equatable, Sendable {
    case anyone
    case peopleWhoKnowMe = "people-who-know-me"
}

public struct ShortcutAuthorValidationResult: Codable, Equatable, Sendable {
    public let sourceSHA256: String
    public let sourceBytes: Int
    public let includeCount: Int
    public let actionCount: Int
    public let compiler: String
    public let compilerVersion: String
    public let clientVersion: String?
    public let experimental: Bool
}

public struct ShortcutAuthorBuildResult: Codable, Equatable, Sendable {
    public let sourceSHA256: String
    public let sourceBytes: Int
    public let compiledSHA256: String
    public let compiledBytes: Int
    public let actionCount: Int
    public let compiler: String
    public let compilerVersion: String
    public let clientVersion: String?
    public let signingMode: ShortcutSigningMode
    public let experimental: Bool
}

public struct ShortcutArtifactMetadata: Equatable, Sendable {
    public let actionCount: Int
    public let clientVersion: String?
}

public protocol ShortcutsAuthoringBuilding: Sendable {
    func validate(sourceURL: URL) throws -> ShortcutAuthorValidationResult
    func build(sourceURL: URL, outputURL: URL, signingMode: ShortcutSigningMode) throws -> ShortcutAuthorBuildResult
}

struct AuthorCommandResult: Sendable {
    let exitCode: Int32
    let timedOut: Bool
    let stdout: Data
}

protocol AuthorCommandRunning: Sendable {
    func run(executable: URL, arguments: [String], currentDirectory: URL, timeoutSeconds: TimeInterval) throws -> AuthorCommandResult
}

struct SystemAuthorCommandRunner: AuthorCommandRunning {
    func run(executable: URL, arguments: [String], currentDirectory: URL, timeoutSeconds: TimeInterval) throws -> AuthorCommandResult {
        let fileManager = FileManager.default
        let captureDirectory = fileManager.temporaryDirectory.appendingPathComponent("macos-data-author-capture-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: captureDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: captureDirectory) }
        let stdoutURL = captureDirectory.appendingPathComponent("stdout")
        let stderrURL = captureDirectory.appendingPathComponent("stderr")
        fileManager.createFile(atPath: stdoutURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        fileManager.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdout.close(); try? stderr.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        process.environment = environment
        try process.run()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return AuthorCommandResult(exitCode: process.terminationStatus, timedOut: true, stdout: Data())
        }
        process.waitUntilExit()
        let data = (try? Data(contentsOf: stdoutURL, options: [.mappedIfSafe])) ?? Data()
        return AuthorCommandResult(exitCode: process.terminationStatus, timedOut: false, stdout: Data(data.prefix(16 * 1024)))
    }
}

public struct CherriAuthoringBridge: ShortcutsAuthoringBuilding, @unchecked Sendable {
    public static let maximumActionCount = 2_000
    public static let maximumArtifactBytes = 10 * 1024 * 1024
    private static let timeoutSeconds: TimeInterval = 30

    private let validator: CherriSourceValidator
    private let runner: any AuthorCommandRunning
    private let fileManager: FileManager
    private let cherriURL: URL?

    public init() {
        self.init(validator: CherriSourceValidator(), runner: SystemAuthorCommandRunner(), fileManager: .default, cherriURL: nil)
    }

    init(validator: CherriSourceValidator, runner: any AuthorCommandRunning, fileManager: FileManager, cherriURL: URL?) {
        self.validator = validator
        self.runner = runner
        self.fileManager = fileManager
        self.cherriURL = cherriURL
    }

    public func validate(sourceURL: URL) throws -> ShortcutAuthorValidationResult {
        let compiled = try compile(sourceURL: sourceURL)
        return ShortcutAuthorValidationResult(
            sourceSHA256: compiled.inspection.sourceSHA256,
            sourceBytes: compiled.inspection.sourceBytes,
            includeCount: compiled.inspection.includeCount,
            actionCount: compiled.metadata.actionCount,
            compiler: "cherri",
            compilerVersion: compiled.compilerVersion,
            clientVersion: compiled.metadata.clientVersion,
            experimental: true
        )
    }

    public func build(sourceURL: URL, outputURL: URL, signingMode: ShortcutSigningMode) throws -> ShortcutAuthorBuildResult {
        guard !fileManager.fileExists(atPath: outputURL.path) else { throw ShortcutsError.authorOutputExists }
        let compiled = try compile(sourceURL: sourceURL, retainTemporaryDirectory: true)
        defer { try? fileManager.removeItem(at: compiled.directory) }
        let signedURL = compiled.directory.appendingPathComponent("signed.shortcut")
        let sign = try runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/shortcuts"),
            arguments: Self.signingArguments(input: compiled.unsignedURL.path, output: signedURL.path, mode: signingMode),
            currentDirectory: compiled.directory,
            timeoutSeconds: Self.timeoutSeconds
        )
        guard !sign.timedOut else { throw ShortcutsError.authorTimedOut }
        guard sign.exitCode == 0, let signed = try? Data(contentsOf: signedURL), !signed.isEmpty, signed.count <= Self.maximumArtifactBytes else {
            throw ShortcutsError.authorSigningFailed
        }
        try signed.write(to: outputURL, options: [.withoutOverwriting])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
        return ShortcutAuthorBuildResult(
            sourceSHA256: compiled.inspection.sourceSHA256,
            sourceBytes: compiled.inspection.sourceBytes,
            compiledSHA256: CherriSourceValidator.hash(signed),
            compiledBytes: signed.count,
            actionCount: compiled.metadata.actionCount,
            compiler: "cherri",
            compilerVersion: compiled.compilerVersion,
            clientVersion: compiled.metadata.clientVersion,
            signingMode: signingMode,
            experimental: true
        )
    }

    public static func compilerArguments(inputName: String) -> [String] {
        [inputName, "--skip-sign", "--derive-uuids", "--no-ansi"]
    }

    public static func signingArguments(input: String, output: String, mode: ShortcutSigningMode) -> [String] {
        ["sign", "--mode", mode.rawValue, "--input", input, "--output", output]
    }

    public static func parseUnsignedArtifact(_ data: Data) throws -> ShortcutArtifactMetadata {
        guard data.count <= maximumArtifactBytes,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let actions = plist["WFWorkflowActions"] as? [[String: Any]],
              !actions.isEmpty,
              actions.count <= maximumActionCount + 1,
              actions.allSatisfy({ ($0["WFWorkflowActionIdentifier"] as? String)?.isEmpty == false }) else {
            throw ShortcutsError.authorArtifactInvalid
        }
        // Shortcuts Events excludes the terminal output node from its public
        // `number of actions` metadata. Use the same observable count so a
        // visible import can be verified without touching private storage.
        let visibleActions = actions.filter { ($0["WFWorkflowActionIdentifier"] as? String) != "is.workflow.actions.output" }
        guard !visibleActions.isEmpty, visibleActions.count <= maximumActionCount else {
            throw ShortcutsError.authorArtifactInvalid
        }
        return ShortcutArtifactMetadata(actionCount: visibleActions.count, clientVersion: plist["WFWorkflowClientVersion"] as? String)
    }

    private struct Compiled {
        let inspection: CherriSourceInspection
        let metadata: ShortcutArtifactMetadata
        let compilerVersion: String
        let directory: URL
        let unsignedURL: URL
    }

    private func compile(sourceURL: URL, retainTemporaryDirectory: Bool = false) throws -> Compiled {
        guard sourceURL.pathExtension.lowercased() == "cherri",
              fileManager.isReadableFile(atPath: sourceURL.path),
              ((try? sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))?.isRegularFile ?? false),
              !((try? sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? true),
              let source = try? Data(contentsOf: sourceURL, options: [.mappedIfSafe]) else {
            throw ShortcutsError.authorSourceInvalid
        }
        let inspection = try validator.validate(source)
        let executable = try resolveCherri()
        let version = try compilerVersion(executable: executable)
        guard version.hasPrefix("2.3.") else { throw ShortcutsError.cherriUnsupported }

        let directory = fileManager.temporaryDirectory.appendingPathComponent("macos-data-cherri-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var keep = false
        defer { if !keep { try? fileManager.removeItem(at: directory) } }
        let copiedSource = directory.appendingPathComponent("source.cherri")
        try source.write(to: copiedSource, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copiedSource.path)

        let result = try runner.run(executable: executable, arguments: Self.compilerArguments(inputName: copiedSource.lastPathComponent), currentDirectory: directory, timeoutSeconds: Self.timeoutSeconds)
        guard !result.timedOut else { throw ShortcutsError.authorTimedOut }
        guard result.exitCode == 0 else { throw ShortcutsError.authorCompilationFailed }
        let artifacts = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))?
            .filter { $0.lastPathComponent.hasSuffix("_unsigned.shortcut") } ?? []
        guard artifacts.count == 1,
              let artifact = try? Data(contentsOf: artifacts[0], options: [.mappedIfSafe]) else {
            throw ShortcutsError.authorArtifactInvalid
        }
        let metadata = try Self.parseUnsignedArtifact(artifact)
        keep = retainTemporaryDirectory
        return Compiled(inspection: inspection, metadata: metadata, compilerVersion: version, directory: directory, unsignedURL: artifacts[0])
    }

    private func resolveCherri() throws -> URL {
        if let cherriURL, fileManager.isExecutableFile(atPath: cherriURL.path) { return cherriURL }
        if let configured = ProcessInfo.processInfo.environment["MACOS_DATA_CHERRI"], configured.hasPrefix("/"), fileManager.isExecutableFile(atPath: configured) {
            return URL(fileURLWithPath: configured).resolvingSymlinksInPath()
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let candidates = path.split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("cherri") }
            + [URL(fileURLWithPath: "/opt/homebrew/bin/cherri"), URL(fileURLWithPath: "/usr/local/bin/cherri")]
        guard let value = candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw ShortcutsError.cherriUnavailable
        }
        return value.resolvingSymlinksInPath()
    }

    private func compilerVersion(executable: URL) throws -> String {
        let result = try runner.run(executable: executable, arguments: ["--version", "--no-ansi"], currentDirectory: fileManager.temporaryDirectory, timeoutSeconds: 5)
        guard !result.timedOut else { throw ShortcutsError.authorTimedOut }
        guard result.exitCode == 0, let text = String(data: result.stdout, encoding: .utf8),
              let match = text.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) else {
            throw ShortcutsError.cherriUnsupported
        }
        return String(text[match])
    }
}
