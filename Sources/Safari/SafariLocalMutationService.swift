import CryptoKit
import Core
import Darwin
import Foundation

struct SafariLocalMutationService {
    let source: URL
    let recoveryRoot: URL
    let safetyGate: SafariPlistMutationSafetyGate
    let writer: SafariPlistAtomicMutationWriter
    private let engine = SafariLocalMutationEngine()

    init(
        source: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist"),
        recoveryRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/macos-data-cli/recovery/safari-local", isDirectory: true),
        safetyGate: SafariPlistMutationSafetyGate = .init(),
        writer: SafariPlistAtomicMutationWriter = .init()
    ) {
        self.source = source
        self.recoveryRoot = recoveryRoot
        self.safetyGate = safetyGate
        self.writer = writer
    }

    func execute(_ input: SafariLocalMutationInput, apply: Bool, confirmation: String?) throws -> SafariLocalMutationResult {
        let data = try boundedSourceData()
        let beforeHash = digest(data)
        if apply {
            guard input.expectedSourceSHA256?.lowercased() == beforeHash else { throw SafariError.localMutationStale }
            try validateDeleteConfirmation(input, confirmation: confirmation)
        }
        let prepared = try engine.prepare(data: data, operation: try operation(input))
        let afterHash = digest(prepared.outputData)
        let changed = beforeHash != afterHash
        let targetID = apply ? resultTargetID(input, output: prepared.outputData) : input.id
        if !changed {
            return .init(
                operation: input.command.rawValue, dryRun: !apply, changed: false,
                targetID: input.id, parentID: input.parentID, sourceSHA256Before: beforeHash,
                sourceSHA256After: beforeHash, syncStatus: "local_only",
                verification: apply ? "readback_confirmed" : "not_applied",
                recoverySessionID: nil, nextAction: nil
            )
        }
        if !apply {
            return .init(
                operation: input.command.rawValue, dryRun: true, changed: true,
                targetID: targetID, parentID: input.parentID, sourceSHA256Before: beforeHash,
                sourceSHA256After: afterHash, syncStatus: "local_only", verification: "not_applied",
                recoverySessionID: nil,
                nextAction: "To apply locally, repeat with expectedSourceSHA256 set to sourceSHA256Before and --apply. Safari must be fully quit. This does not sync to iCloud."
            )
        }

        let session = UUID().uuidString.lowercased()
        let recovery = try recoveryDirectory(session: session)
        let safety: SafariPlistMutationSafetyReport
        do { safety = try safetyGate.prepare(source: source, recoveryDirectory: recovery) }
        catch {
            DiagnosticLogger.record(code: "SAFARI_LOCAL_MUTATION_GATE_FAILED", message: "stage=safety kind=\(safetyFailureKind(error))")
            throw mapSafety(error)
        }
        do { _ = try writer.replace(source: source, safety: safety, mutation: prepared) }
        catch {
            DiagnosticLogger.record(code: "SAFARI_LOCAL_MUTATION_WRITER_FAILED", message: "stage=atomic kind=\(writerFailureKind(error))")
            throw mapWriter(error)
        }
        return .init(
            operation: input.command.rawValue, dryRun: false, changed: true,
            targetID: targetID, parentID: input.parentID, sourceSHA256Before: beforeHash,
            sourceSHA256After: afterHash, syncStatus: "local_only", verification: "readback_confirmed",
            recoverySessionID: session,
            nextAction: "Local Safari plist mutation is confirmed. It does not sync to iCloud; keep the retained recovery until Safari UI read-back is complete."
        )
    }

    private func operation(_ input: SafariLocalMutationInput) throws -> SafariLocalMutationOperation {
        switch input.command {
        case .bookmarkCreate:
            guard let parent = input.parentID, let index = input.index, let title = input.title, let url = input.url else { throw SafariError.invalidInput }
            return .createBookmark(parentID: parent, index: index, uuid: UUID().uuidString, title: title, url: url)
        case .bookmarkEdit:
            guard let id = input.id, let title = input.title, let url = input.url else { throw SafariError.invalidInput }
            return .updateBookmark(id: id, title: title, url: url)
        case .bookmarkMove:
            guard let id = input.id, let parent = input.parentID, let index = input.index else { throw SafariError.invalidInput }
            return .moveBookmark(id: id, parentID: parent, index: index)
        case .folderMove:
            guard let id = input.id, let parent = input.parentID, let index = input.index else { throw SafariError.invalidInput }
            return .moveFolder(id: id, parentID: parent, index: index)
        case .bookmarkDelete:
            guard let id = input.id else { throw SafariError.invalidInput }
            return .deleteBookmark(id: id)
        case .folderDelete:
            guard let id = input.id else { throw SafariError.invalidInput }
            return .deleteFolder(id: id)
        case .folderCreate:
            guard let parent = input.parentID, let index = input.index, let title = input.title else { throw SafariError.invalidInput }
            return .createFolder(parentID: parent, index: index, uuid: UUID().uuidString, title: title)
        case .folderRename:
            guard let id = input.id, let title = input.title else { throw SafariError.invalidInput }
            return .renameFolder(id: id, title: title)
        }
    }

    private func validateDeleteConfirmation(_ input: SafariLocalMutationInput, confirmation: String?) throws {
        let required: String?
        switch input.command {
        case .bookmarkDelete: required = "DELETE SAFARI BOOKMARK"
        case .folderDelete: required = "DELETE SAFARI FOLDER"
        default: required = nil
        }
        if let required, confirmation != required { throw SafariError.localMutationConfirmationRequired }
    }

    private func resultTargetID(_ input: SafariLocalMutationInput, output: Data) -> String? {
        if let id = input.id { return id }
        guard let snapshot = try? SafariBookmarksParser.parse(data: output) else { return nil }
        switch input.command {
        case .bookmarkCreate:
            return snapshot.bookmarks.last(where: { $0.parentID == input.parentID && $0.title == input.title && $0.url == input.url })?.id
        case .folderCreate:
            return snapshot.bookmarks.last(where: { $0.parentID == input.parentID && $0.kind == .folder && $0.title == input.title })?.id
        default: return nil
        }
    }

    private func boundedSourceData() throws -> Data {
        guard FileManager.default.isReadableFile(atPath: source.path),
              let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= SystemSafariBookmarksSnapshotReader.maximumBytes,
              let data = try? Data(contentsOf: source), data.count <= SystemSafariBookmarksSnapshotReader.maximumBytes else {
            throw SafariError.bookmarksUnavailable
        }
        return data
    }

    private func recoveryDirectory(session: String) throws -> URL {
        let base = recoveryRoot
        try ensurePrivateDirectory(base.deletingLastPathComponent())
        try ensurePrivateDirectory(base)
        return base.appendingPathComponent(session, isDirectory: true)
    }

    private func ensurePrivateDirectory(_ url: URL) throws {
        var value = stat()
        if lstat(url.path, &value) == 0 {
            guard (value.st_mode & S_IFMT) == S_IFDIR, value.st_uid == geteuid() else { throw SafariError.localMutationUnsafe }
            if UInt16(value.st_mode & 0o7777) != 0o700, chmod(url.path, 0o700) != 0 { throw SafariError.localMutationUnsafe }
            return
        }
        guard errno == ENOENT else { throw SafariError.localMutationUnsafe }
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { throw SafariError.localMutationUnsafe }
        guard chmod(url.path, 0o700) == 0 else { throw SafariError.localMutationUnsafe }
    }

    private func mapSafety(_ error: Error) -> SafariError {
        switch error as? SafariPlistMutationGateError {
        case .safariRunning: .localMutationSafariRunning
        case .sourceUnstable, .plistInUse: .localMutationStale
        default: .localMutationUnsafe
        }
    }

    private func mapWriter(_ error: Error) -> SafariError {
        switch error as? SafariPlistAtomicMutationError {
        case .safariRunning: .localMutationSafariRunning
        case .staleSafetyGate, .plistInUse: .localMutationStale
        default: .localMutationUnsafe
        }
    }

    private func safetyFailureKind(_ error: Error) -> String {
        guard let value = error as? SafariPlistMutationGateError else { return "unknown" }
        return String(describing: value)
    }

    private func writerFailureKind(_ error: Error) -> String {
        guard let value = error as? SafariPlistAtomicMutationError else { return "unknown" }
        switch value {
        case .candidateMetadataMismatch: return "candidateMetadataMismatch"
        default: return String(describing: value)
        }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
