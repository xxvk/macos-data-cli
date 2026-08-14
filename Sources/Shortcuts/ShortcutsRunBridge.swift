import CryptoKit
import Core
import Darwin
import Foundation

public struct ShortcutsRunDescriptor: Equatable, Sendable {
    public let output: Data?
    public let outputPath: URL?
    public let outputBytes: Int
    public let outputSHA256: String

    public init(output: Data?, outputPath: URL?, outputBytes: Int, outputSHA256: String) {
        self.output = output
        self.outputPath = outputPath
        self.outputBytes = outputBytes
        self.outputSHA256 = outputSHA256
    }
}

public protocol ShortcutsRunBridging: Sendable {
    func run(identifier: String, inputPaths: [URL], outputPath: URL?, outputType: String, timeoutSeconds: Int) throws -> ShortcutsRunDescriptor
}

public struct SystemShortcutsRunBridge: ShortcutsRunBridging {
    public static let maximumInlineOutputBytes = 256 * 1024
    public init() {}

    public static func arguments(identifier: String, inputPaths: [URL], outputPath: URL?, outputType: String) -> [String] {
        var result = ["run", identifier]
        for path in inputPaths { result += ["--input-path", path.path] }
        if let outputPath {
            result += ["--output-path", outputPath.path, "--output-type", outputType]
        }
        return result
    }

    public func run(identifier: String, inputPaths: [URL], outputPath: URL?, outputType: String, timeoutSeconds: Int) throws -> ShortcutsRunDescriptor {
        let fileManager = FileManager.default
        if let outputPath, fileManager.fileExists(atPath: outputPath.path) { throw ShortcutsError.outputExists }
        let temporary = fileManager.temporaryDirectory.appendingPathComponent("macos-data-shortcuts-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: temporary) }
        let capturesPlaintext = outputType == "public.utf8-plain-text"
        let actualOutput: URL
        if capturesPlaintext {
            actualOutput = temporary.appendingPathComponent("stdout")
        } else if let outputPath {
            let parent = outputPath.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ShortcutsError.invalidRunInput
            }
            actualOutput = parent.appendingPathComponent(".macos-data-shortcuts-\(UUID().uuidString).tmp")
        } else {
            actualOutput = temporary.appendingPathComponent("output")
        }
        defer { try? fileManager.removeItem(at: actualOutput) }
        if capturesPlaintext {
            fileManager.createFile(atPath: actualOutput.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let errorURL = temporary.appendingPathComponent("stderr")
        fileManager.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        guard let errorHandle = try? FileHandle(forWritingTo: errorURL) else { throw ShortcutsError.executionFailed }
        defer { try? errorHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = Self.arguments(identifier: identifier, inputPaths: inputPaths, outputPath: capturesPlaintext ? nil : actualOutput, outputType: outputType)
        process.standardInput = FileHandle.nullDevice
        let outputHandle = capturesPlaintext ? try FileHandle(forWritingTo: actualOutput) : nil
        defer { try? outputHandle?.close() }
        process.standardOutput = outputHandle ?? FileHandle.nullDevice
        process.standardError = errorHandle
        do { try process.run() } catch { throw ShortcutsError.executionFailed }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw ShortcutsError.runOutcomeUnknown
        }
        process.waitUntilExit()
        try? outputHandle?.close()
        guard process.terminationStatus == 0 else { throw ShortcutsError.runFailed }
        guard fileManager.fileExists(atPath: actualOutput.path) else {
            return ShortcutsRunDescriptor(output: Data(), outputPath: outputPath, outputBytes: 0, outputSHA256: Self.hash(Data()))
        }
        let attributes = try fileManager.attributesOfItem(atPath: actualOutput.path)
        let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if outputPath == nil && bytes > Self.maximumInlineOutputBytes { throw ShortcutsError.outputTooLarge }
        let data = outputPath == nil ? try Data(contentsOf: actualOutput, options: .mappedIfSafe) : nil
        let hash = try Self.hashFile(actualOutput)
        if let outputPath {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: actualOutput.path)
            do { try fileManager.moveItem(at: actualOutput, to: outputPath) }
            catch { throw ShortcutsError.executionFailed }
        }
        return ShortcutsRunDescriptor(output: data, outputPath: outputPath, outputBytes: bytes, outputSHA256: hash)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
