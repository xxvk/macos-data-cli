import Core
import CryptoKit
import Foundation

public struct ShortcutsStore: Sendable {
    private let permission: ShortcutsPermissionService
    private let metadataBridge: any ShortcutsMetadataBridging
    private let mutationBridge: any ShortcutsMutationBridging
    private let runBridge: any ShortcutsRunBridging

    public init(
        permission: ShortcutsPermissionService = ShortcutsPermissionService(),
        metadataBridge: any ShortcutsMetadataBridging = SystemShortcutsMetadataBridge(),
        mutationBridge: any ShortcutsMutationBridging = SystemShortcutsMutationBridge(),
        runBridge: any ShortcutsRunBridging = SystemShortcutsRunBridge()
    ) {
        self.permission = permission
        self.metadataBridge = metadataBridge
        self.mutationBridge = mutationBridge
        self.runBridge = runBridge
    }

    public func list(limit: Int, cursor: String?, folderID: String?) throws -> PagedResult<ShortcutPayload> {
        guard (1...Pagination.maximumLimit).contains(limit) else { throw ShortcutsError.invalidLimit }
        let snapshot = try loadSnapshot()
        let folderMap = Dictionary(uniqueKeysWithValues: snapshot.folders.map { ($0.scriptingID, ShortcutsOpaqueID.folder(scriptingID: $0.scriptingID)) })
        if let folderID, !folderMap.values.contains(folderID) { throw ShortcutsError.invalidIdentifier }
        let values = snapshot.shortcuts.map { value in
            ShortcutPayload(
                id: ShortcutsOpaqueID.shortcut(scriptingID: value.scriptingID),
                name: value.name,
                subtitle: value.subtitle,
                folderID: value.folderScriptingID.flatMap { folderMap[$0] },
                acceptsInput: value.acceptsInput,
                actionCount: value.actionCount,
                color: value.color,
                iconAvailable: value.iconAvailable
            )
        }.filter { folderID == nil || $0.folderID == folderID }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return try Pagination.page(items: values, limit: limit, cursor: cursor, prefix: "shortcutspage_\(digest(folderID ?? "*"))_")
    }

    public func folders(limit: Int, cursor: String?) throws -> PagedResult<ShortcutFolderPayload> {
        guard (1...Pagination.maximumLimit).contains(limit) else { throw ShortcutsError.invalidLimit }
        let snapshot = try loadSnapshot()
        let values = snapshot.folders.map {
            ShortcutFolderPayload(id: ShortcutsOpaqueID.folder(scriptingID: $0.scriptingID), name: $0.name)
        }.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return try Pagination.page(items: values, limit: limit, cursor: cursor, prefix: "shortcutfolderpage_")
    }

    public func get(id: String) throws -> ShortcutPayload {
        guard ShortcutsOpaqueID.isShortcut(id) else { throw ShortcutsError.invalidIdentifier }
        let snapshot = try loadSnapshot()
        let folderMap = Dictionary(uniqueKeysWithValues: snapshot.folders.map { ($0.scriptingID, ShortcutsOpaqueID.folder(scriptingID: $0.scriptingID)) })
        guard let value = snapshot.shortcuts.first(where: { ShortcutsOpaqueID.shortcut(scriptingID: $0.scriptingID) == id }) else {
            throw ShortcutsError.invalidIdentifier
        }
        return ShortcutPayload(id: id, name: value.name, subtitle: value.subtitle, folderID: value.folderScriptingID.flatMap { folderMap[$0] }, acceptsInput: value.acceptsInput, actionCount: value.actionCount, color: value.color, iconAvailable: value.iconAvailable)
    }

    public func move(id: String, destinationFolderID: String, apply: Bool) throws -> ShortcutMoveResult {
        guard ShortcutsOpaqueID.isShortcut(id), ShortcutsOpaqueID.isFolder(destinationFolderID) else { throw ShortcutsError.invalidIdentifier }
        let snapshot = try loadSnapshot()
        guard snapshot.complete else { throw ShortcutsError.incompleteMetadata }
        guard let shortcut = snapshot.shortcuts.first(where: { ShortcutsOpaqueID.shortcut(scriptingID: $0.scriptingID) == id }),
              let destination = snapshot.folders.first(where: { ShortcutsOpaqueID.folder(scriptingID: $0.scriptingID) == destinationFolderID }) else {
            throw ShortcutsError.invalidIdentifier
        }
        let previous = shortcut.folderScriptingID.map { ShortcutsOpaqueID.folder(scriptingID: $0) }
        let changed = previous != destinationFolderID
        guard apply && changed else {
            return ShortcutMoveResult(operation: changed ? "move_preview" : "move_noop", dryRun: !apply, changed: changed, shortcutID: id, previousFolderID: previous, destinationFolderID: destinationFolderID, verification: .notApplied)
        }
        do {
            let readback = try mutationBridge.move(shortcutScriptingID: shortcut.scriptingID, destinationFolderScriptingID: destination.scriptingID)
            guard readback == destination.scriptingID else { throw ShortcutsError.moveVerificationFailed }
        } catch let error as ShortcutsError { throw error }
        catch ShortcutsBridgeError.automationDenied { throw ShortcutsError.permissionDenied }
        catch ShortcutsBridgeError.targetNotRunning { throw ShortcutsError.targetNotRunning }
        catch ShortcutsBridgeError.timedOut { throw ShortcutsError.moveVerificationFailed }
        catch { throw ShortcutsError.executionFailed }
        return ShortcutMoveResult(operation: "moved", dryRun: false, changed: true, shortcutID: id, previousFolderID: previous, destinationFolderID: destinationFolderID, verification: .readbackConfirmed)
    }

    public func run(id: String, inputPaths: [URL], outputPath: URL?, outputType: String, timeoutSeconds: Int) throws -> ShortcutRunResult {
        guard ShortcutsOpaqueID.isShortcut(id), inputPaths.count <= 16,
              (1...300).contains(timeoutSeconds), !outputType.isEmpty, outputType.count <= 200,
              inputPaths.allSatisfy({
                  FileManager.default.isReadableFile(atPath: $0.path)
                      && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) == true
              }) else {
            throw ShortcutsError.invalidRunInput
        }
        let snapshot = try loadSnapshot()
        guard let shortcut = snapshot.shortcuts.first(where: { ShortcutsOpaqueID.shortcut(scriptingID: $0.scriptingID) == id }) else {
            throw ShortcutsError.invalidIdentifier
        }
        let value = try runBridge.run(identifier: shortcut.scriptingID, inputPaths: inputPaths, outputPath: outputPath, outputType: outputType, timeoutSeconds: timeoutSeconds)
        let output: String?
        if let data = value.output {
            guard data.count <= SystemShortcutsRunBridge.maximumInlineOutputBytes else { throw ShortcutsError.outputTooLarge }
            output = String(data: data, encoding: .utf8)
            if !data.isEmpty && output == nil { throw ShortcutsError.invalidRunInput }
        } else { output = nil }
        return ShortcutRunResult(shortcutID: id, verification: .completed, output: output, outputPath: value.outputPath?.path, outputBytes: value.outputBytes, outputSHA256: value.outputSHA256)
    }

    private func loadSnapshot() throws -> ShortcutsMetadataSnapshot {
        try requirePermission()
        do {
            return try SystemShortcutsMetadataBridge.validate(metadataBridge.snapshot(maximumShortcuts: SystemShortcutsMetadataBridge.maximumShortcuts, maximumFolders: SystemShortcutsMetadataBridge.maximumFolders))
        } catch ShortcutsBridgeError.automationDenied { throw ShortcutsError.permissionDenied }
        catch ShortcutsBridgeError.targetNotRunning { throw ShortcutsError.targetNotRunning }
        catch ShortcutsBridgeError.timedOut { throw ShortcutsError.timedOut }
        catch { throw ShortcutsError.executionFailed }
    }

    private func requirePermission() throws {
        switch permission.check().access {
        case .available: break
        case .requiresConsent: throw ShortcutsError.permissionRequired
        case .denied: throw ShortcutsError.permissionDenied
        case .targetUnavailable: throw ShortcutsError.targetUnavailable
        // Shortcuts Events is an on-demand helper and commonly is not running
        // between commands. Let the actual Apple Event bridge launch it; that
        // bridge still maps a genuine launch/connection failure explicitly.
        case .targetNotRunning: break
        case .unknown: throw ShortcutsError.automationUnknown
        }
    }

    private func digest(_ value: String) -> String {
        String(SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16))
    }
}
