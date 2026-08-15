import Core
import Foundation

public enum ShortcutAuthoringVerification: String, Codable, Equatable, Sendable {
    case notApplied = "not_applied"
    case readbackConfirmed = "readback_confirmed"
    case idempotencyReceiptReadbackConfirmed = "idempotency_receipt_readback_confirmed"
    case idempotencyReceiptPending = "idempotency_receipt_pending"
    case outcomeUnknown = "outcome_unknown"
}

public struct ShortcutAuthoringMutationResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let verification: ShortcutAuthoringVerification
    public let shortcutID: String?
    public let sourceSHA256: String
    public let compiledSHA256: String?
    public let sourceBytes: Int
    public let compiledBytes: Int?
    public let actionCount: Int?
    public let observedActionCount: Int?
    public let compilerVersion: String?
    public let signingMode: ShortcutSigningMode
    public let deduplicated: Bool
    public let registrySaved: Bool
    public let nextAction: String?
}

public enum ShortcutUpdateStrategy: String, Codable, Equatable, Sendable {
    case replace
    case retainOld = "retain-old"
}

public struct ShortcutAuthoringUpdateResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let verification: ShortcutAuthoringVerification
    public let previousShortcutID: String
    public let shortcutID: String?
    public let sourceSHA256: String
    public let compiledSHA256: String?
    public let actionCount: Int?
    public let observedActionCount: Int?
    public let strategy: ShortcutUpdateStrategy
    public let oldRetained: Bool
    public let registrySaved: Bool
    public let nextAction: String?
}

public struct ShortcutManagedForgetResult: Codable, Equatable, Sendable {
    public let operation: String
    public let dryRun: Bool
    public let changed: Bool
    public let shortcutID: String
    public let sourceSHA256: String
}

public struct ShortcutsAuthoringService: Sendable {
    private let builder: any ShortcutsAuthoringBuilding
    private let validator: CherriSourceValidator
    private let metadataBridge: any ShortcutsMetadataBridging
    private let importer: any ShortcutsVisibleImporting
    private let registry: ShortcutsManagedRegistry
    private let receipts: ShortcutsAuthoringReceiptStore

    public init(
        builder: any ShortcutsAuthoringBuilding = CherriAuthoringBridge(),
        validator: CherriSourceValidator = CherriSourceValidator(),
        metadataBridge: any ShortcutsMetadataBridging = SystemShortcutsMetadataBridge(),
        importer: (any ShortcutsVisibleImporting)? = nil,
        registry: ShortcutsManagedRegistry = ShortcutsManagedRegistry(),
        receipts: ShortcutsAuthoringReceiptStore = ShortcutsAuthoringReceiptStore()
    ) {
        self.builder = builder
        self.validator = validator
        self.metadataBridge = metadataBridge
        self.importer = importer ?? SystemShortcutsVisibleImporter(metadataBridge: metadataBridge)
        self.registry = registry
        self.receipts = receipts
    }

    public func create(sourceURL: URL, signingMode: ShortcutSigningMode, apply: Bool, idempotent: Bool) throws -> ShortcutAuthoringMutationResult {
        guard sourceURL.pathExtension.lowercased() == "cherri", let source = try? Data(contentsOf: sourceURL, options: [.mappedIfSafe]) else {
            throw ShortcutsError.authorSourceInvalid
        }
        let inspection = try validator.validate(source)

        if apply, idempotent, let receipt = try receipts.receipt(sourceSHA256: inspection.sourceSHA256) {
            if receipt.state == .inFlight {
                return result(operation: "create", apply: true, inspection: inspection, build: nil, observedActionCount: nil, verification: .outcomeUnknown, shortcutID: nil, deduplicated: true, registrySaved: false, signingMode: signingMode, nextAction: "A recent visible import may still be pending. Do not retry automatically; use shortcuts list and inspect Shortcuts.app after the receipt expires.")
            }
            if let shortcutID = receipt.shortcutID {
                let snapshot = try loadSnapshot()
                let confirmed = snapshot.shortcuts.first { ShortcutsOpaqueID.shortcut(scriptingID: $0.scriptingID) == shortcutID }
                let registrySaved = (try? registry.record(shortcutID: shortcutID)) != nil
                let nextAction: String?
                if confirmed == nil {
                    nextAction = "A completed receipt prevented a duplicate, but current metadata did not confirm it. Do not retry automatically; use shortcuts get with the returned ID."
                } else if !registrySaved {
                    nextAction = "The completed receipt and visible Shortcut were confirmed, but the private managed registry is missing. Do not recreate or update it automatically; repair the local registry before continuing."
                } else {
                    nextAction = nil
                }
                return result(operation: "create", apply: true, inspection: inspection, build: nil, observedActionCount: confirmed?.actionCount, verification: confirmed == nil ? .idempotencyReceiptPending : .idempotencyReceiptReadbackConfirmed, shortcutID: shortcutID, deduplicated: true, registrySaved: registrySaved, signingMode: signingMode, nextAction: nextAction)
            }
        }

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mpia-shortcuts-create-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let artifact = temporary.appendingPathComponent("\(inspection.declaredName).shortcut")
        let build = try builder.build(sourceURL: sourceURL, outputURL: artifact, signingMode: signingMode)
        guard build.sourceSHA256 == inspection.sourceSHA256 else { throw ShortcutsError.authorArtifactInvalid }
        guard apply else {
            return result(operation: "create_preview", apply: false, inspection: inspection, build: build, observedActionCount: nil, verification: .notApplied, shortcutID: nil, deduplicated: false, registrySaved: false, signingMode: signingMode, nextAction: nil)
        }

        let before = try loadSnapshot()
        guard before.complete else { throw ShortcutsError.incompleteMetadata }
        guard !before.shortcuts.contains(where: { $0.name == inspection.declaredName }) else { throw ShortcutsError.authorNameConflict }
        if idempotent { try receipts.saveInFlight(build: build) }
        let imported = try importer.importArtifact(at: artifact, expectedName: inspection.declaredName, excludingShortcutIDs: Set(before.shortcuts.map(\.scriptingID)))
        guard let imported else {
            return result(operation: "create", apply: true, inspection: inspection, build: build, observedActionCount: nil, verification: .outcomeUnknown, shortcutID: nil, deduplicated: false, registrySaved: false, signingMode: signingMode, nextAction: "The visible import was opened but read-back was not confirmed. Do not retry automatically; inspect Shortcuts.app and use shortcuts list.")
        }
        let opaqueID = ShortcutsOpaqueID.shortcut(scriptingID: imported.scriptingID)
        let timestamp = Date()
        let record = ManagedShortcutRecord(shortcutID: opaqueID, sourceSHA256: build.sourceSHA256, compiledSHA256: build.compiledSHA256, actionCount: build.actionCount, compilerVersion: build.compilerVersion, createdAt: timestamp, updatedAt: timestamp)
        let registrySaved = (try? registry.upsert(record)) != nil
        if idempotent { try? receipts.saveCompleted(build: build, shortcutID: opaqueID) }
        let countLimitation = imported.actionCount == build.actionCount ? nil : "The public Shortcuts action count differs from the compiled graph. Do not use it as graph proof; run an explicitly safe black-box fixture before relying on this Shortcut."
        let nextAction = registrySaved ? countLimitation : "Import was confirmed but the private registry could not be saved. Do not retry or update automatically; preserve the source and repair local registry permissions."
        return result(operation: "created", apply: true, inspection: inspection, build: build, observedActionCount: imported.actionCount, verification: .readbackConfirmed, shortcutID: opaqueID, deduplicated: false, registrySaved: registrySaved, signingMode: signingMode, nextAction: nextAction)
    }

    public func update(id: String, sourceURL: URL, expectedSourceSHA256: String, strategy: ShortcutUpdateStrategy, signingMode: ShortcutSigningMode, apply: Bool) throws -> ShortcutAuthoringUpdateResult {
        guard ShortcutsOpaqueID.isShortcut(id), expectedSourceSHA256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw ShortcutsError.authorSourceInvalid
        }
        guard let managed = try registry.record(shortcutID: id) else { throw ShortcutsError.authorManagedOnly }
        guard managed.sourceSHA256 == expectedSourceSHA256 else { throw ShortcutsError.authorSourceConflict }
        guard sourceURL.pathExtension.lowercased() == "cherri", let source = try? Data(contentsOf: sourceURL, options: [.mappedIfSafe]) else {
            throw ShortcutsError.authorSourceInvalid
        }
        let inspection = try validator.validate(source)
        let snapshot = try loadSnapshot()
        guard snapshot.complete,
              let previous = snapshot.shortcuts.first(where: { ShortcutsOpaqueID.shortcut(scriptingID: $0.scriptingID) == id }) else {
            throw ShortcutsError.invalidIdentifier
        }
        guard snapshot.shortcuts.filter({ $0.name == previous.name }).count == 1 else {
            throw ShortcutsError.authorNameConflict
        }
        let previousManagedCandidateName = candidateName(base: inspection.declaredName, sourceSHA256: managed.sourceSHA256)
        guard previous.name == inspection.declaredName || previous.name == previousManagedCandidateName else {
            throw ShortcutsError.authorSourceConflict
        }
        if inspection.sourceSHA256 == managed.sourceSHA256 {
            return ShortcutAuthoringUpdateResult(operation: "update_noop", dryRun: !apply, changed: false, verification: .notApplied, previousShortcutID: id, shortcutID: id, sourceSHA256: inspection.sourceSHA256, compiledSHA256: managed.compiledSHA256, actionCount: managed.actionCount, observedActionCount: previous.actionCount, strategy: strategy, oldRetained: true, registrySaved: true, nextAction: nil)
        }
        if apply, let receipt = try receipts.receipt(sourceSHA256: inspection.sourceSHA256) {
            return ShortcutAuthoringUpdateResult(operation: "update", dryRun: false, changed: false, verification: receipt.state == .saved ? .idempotencyReceiptPending : .outcomeUnknown, previousShortcutID: id, shortcutID: receipt.shortcutID, sourceSHA256: inspection.sourceSHA256, compiledSHA256: receipt.compiledSHA256, actionCount: receipt.actionCount, observedActionCount: nil, strategy: strategy, oldRetained: true, registrySaved: false, nextAction: "A recent managed update import may already exist. Do not retry automatically; inspect Shortcuts.app and the registry first.")
        }

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("mpia-shortcuts-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let expectedImportName = strategy == .replace ? previous.name : candidateName(base: inspection.declaredName, sourceSHA256: inspection.sourceSHA256)
        if strategy == .retainOld, snapshot.shortcuts.contains(where: { $0.name == expectedImportName }) {
            throw ShortcutsError.authorNameConflict
        }
        let artifact = temporary.appendingPathComponent("\(expectedImportName).shortcut")
        let buildSourceURL: URL
        let compiledSourceInspection: CherriSourceInspection
        if expectedImportName == inspection.declaredName {
            buildSourceURL = sourceURL
            compiledSourceInspection = inspection
        } else {
            let compiledSource = try Self.source(source, replacingDeclaredNameWith: expectedImportName)
            buildSourceURL = temporary.appendingPathComponent("candidate.cherri")
            try compiledSource.write(to: buildSourceURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: buildSourceURL.path)
            compiledSourceInspection = try validator.validate(compiledSource)
        }
        let compiledBuild = try builder.build(sourceURL: buildSourceURL, outputURL: artifact, signingMode: signingMode)
        guard compiledBuild.sourceSHA256 == compiledSourceInspection.sourceSHA256 else { throw ShortcutsError.authorArtifactInvalid }
        let build = Self.normalizedBuild(compiledBuild, sourceInspection: inspection)
        if strategy == .replace {
            guard previous.actionCount == managed.actionCount, build.actionCount != previous.actionCount else {
                throw ShortcutsError.authorUpdateUnverifiable
            }
        }
        guard apply else {
            return ShortcutAuthoringUpdateResult(operation: "update_preview", dryRun: true, changed: false, verification: .notApplied, previousShortcutID: id, shortcutID: nil, sourceSHA256: build.sourceSHA256, compiledSHA256: build.compiledSHA256, actionCount: build.actionCount, observedActionCount: nil, strategy: strategy, oldRetained: true, registrySaved: true, nextAction: nil)
        }

        try receipts.saveInFlight(build: build)
        let imported: ShortcutDescriptor?
        if strategy == .replace {
            imported = try importer.replaceArtifact(at: artifact, expectedName: expectedImportName, actionCount: build.actionCount, previousShortcutID: previous.scriptingID, previousActionCount: previous.actionCount)
        } else {
            imported = try importer.importArtifact(at: artifact, expectedName: expectedImportName, excludingShortcutIDs: Set(snapshot.shortcuts.map(\.scriptingID)))
        }
        guard let imported else {
            return ShortcutAuthoringUpdateResult(operation: "update", dryRun: false, changed: false, verification: .outcomeUnknown, previousShortcutID: id, shortcutID: nil, sourceSHA256: build.sourceSHA256, compiledSHA256: build.compiledSHA256, actionCount: build.actionCount, observedActionCount: nil, strategy: strategy, oldRetained: true, registrySaved: true, nextAction: "The visible update import was opened but not confirmed. Do not retry automatically; inspect Shortcuts.app and list metadata.")
        }
        let newID = ShortcutsOpaqueID.shortcut(scriptingID: imported.scriptingID)
        let timestamp = Date()
        let record = ManagedShortcutRecord(shortcutID: newID, sourceSHA256: build.sourceSHA256, compiledSHA256: build.compiledSHA256, actionCount: build.actionCount, compilerVersion: build.compilerVersion, createdAt: timestamp, updatedAt: timestamp)
        let registrySaved = (try? registry.replace(previousShortcutID: id, with: record)) != nil
        if registrySaved {
            try? receipts.remove(sourceSHA256: managed.sourceSHA256)
            try? receipts.saveCompleted(build: build, shortcutID: newID)
        }
        let countLimitation = imported.actionCount == build.actionCount ? nil : "The public Shortcuts action count differs from the compiled graph. Verify the candidate with an explicitly safe black-box run before cleanup or adoption."
        let nextAction = registrySaved ? countLimitation : "Update import was confirmed but registry replacement failed. Do not retry or delete either shortcut; repair registry permissions first."
        return ShortcutAuthoringUpdateResult(operation: "updated", dryRun: false, changed: true, verification: .readbackConfirmed, previousShortcutID: id, shortcutID: newID, sourceSHA256: build.sourceSHA256, compiledSHA256: build.compiledSHA256, actionCount: build.actionCount, observedActionCount: imported.actionCount, strategy: strategy, oldRetained: strategy == .retainOld, registrySaved: registrySaved, nextAction: nextAction)
    }

    public func managedRecords() throws -> [ManagedShortcutRecord] { try registry.list() }

    public func forgetManaged(id: String, apply: Bool) throws -> ShortcutManagedForgetResult {
        guard ShortcutsOpaqueID.isShortcut(id), let record = try registry.record(shortcutID: id) else {
            throw ShortcutsError.authorManagedOnly
        }
        guard apply else { return ShortcutManagedForgetResult(operation: "forget_preview", dryRun: true, changed: false, shortcutID: id, sourceSHA256: record.sourceSHA256) }
        try registry.remove(shortcutID: id)
        try? receipts.remove(sourceSHA256: record.sourceSHA256)
        return ShortcutManagedForgetResult(operation: "forgotten", dryRun: false, changed: true, shortcutID: id, sourceSHA256: record.sourceSHA256)
    }

    private func loadSnapshot() throws -> ShortcutsMetadataSnapshot {
        do {
            return try SystemShortcutsMetadataBridge.validate(metadataBridge.snapshot(maximumShortcuts: SystemShortcutsMetadataBridge.maximumShortcuts, maximumFolders: SystemShortcutsMetadataBridge.maximumFolders))
        } catch ShortcutsBridgeError.automationDenied { throw ShortcutsError.permissionDenied }
        catch ShortcutsBridgeError.targetNotRunning { throw ShortcutsError.targetNotRunning }
        catch ShortcutsBridgeError.timedOut { throw ShortcutsError.timedOut }
        catch { throw ShortcutsError.executionFailed }
    }

    private func result(operation: String, apply: Bool, inspection: CherriSourceInspection, build: ShortcutAuthorBuildResult?, observedActionCount: Int?, verification: ShortcutAuthoringVerification, shortcutID: String?, deduplicated: Bool, registrySaved: Bool, signingMode: ShortcutSigningMode, nextAction: String?) -> ShortcutAuthoringMutationResult {
        ShortcutAuthoringMutationResult(operation: operation, dryRun: !apply, changed: verification == .readbackConfirmed, verification: verification, shortcutID: shortcutID, sourceSHA256: inspection.sourceSHA256, compiledSHA256: build?.compiledSHA256, sourceBytes: inspection.sourceBytes, compiledBytes: build?.compiledBytes, actionCount: build?.actionCount, observedActionCount: observedActionCount, compilerVersion: build?.compilerVersion, signingMode: build?.signingMode ?? signingMode, deduplicated: deduplicated, registrySaved: registrySaved, nextAction: nextAction)
    }

    private func candidateName(base: String, sourceSHA256: String) -> String {
        let suffix = " (mpia \(sourceSHA256.prefix(8)))"
        var prefix = base
        while Data((prefix + suffix).utf8).count > 240, !prefix.isEmpty { prefix.removeLast() }
        return prefix + suffix
    }

    static func source(_ data: Data, replacingDeclaredNameWith name: String) throws -> Data {
        guard let source = String(data: data, encoding: .utf8),
              let expression = try? NSRegularExpression(pattern: #"(?m)^(\s*#define\s+name\s+)(.+?)(\s*)$"#),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let valueRange = Range(match.range(at: 2), in: source) else {
            throw ShortcutsError.authorSourceInvalid
        }
        var rewritten = source
        rewritten.replaceSubrange(valueRange, with: name)
        guard let result = rewritten.data(using: .utf8),
              try CherriSourceValidator().validate(result).declaredName == name else {
            throw ShortcutsError.authorSourceInvalid
        }
        return result
    }

    private static func normalizedBuild(_ build: ShortcutAuthorBuildResult, sourceInspection: CherriSourceInspection) -> ShortcutAuthorBuildResult {
        ShortcutAuthorBuildResult(
            sourceSHA256: sourceInspection.sourceSHA256,
            sourceBytes: sourceInspection.sourceBytes,
            compiledSHA256: build.compiledSHA256,
            compiledBytes: build.compiledBytes,
            actionCount: build.actionCount,
            compiler: build.compiler,
            compilerVersion: build.compilerVersion,
            clientVersion: build.clientVersion,
            signingMode: build.signingMode,
            experimental: build.experimental
        )
    }
}
