import Core
import Foundation

public enum ShortcutAcquisitionArtifactKind: String, Codable, Equatable, Sendable {
    case cherriSource = "cherri_source"
    case unsignedShortcut = "unsigned_shortcut"
    case opaqueShortcut = "opaque_shortcut"
}

public enum ShortcutAcquisitionParseStatus: String, Codable, Equatable, Sendable {
    case sourceValidated = "source_validated"
    case artifactParsed = "artifact_parsed"
    case opaque
}

public enum ShortcutAcquisitionCapability: String, Codable, Equatable, Sendable {
    case managedSourceRoute = "managed_source_route"
    case semanticEditCandidate = "semantic_edit_candidate"
    case manualMigrationRequired = "manual_migration_required"
}

public enum ShortcutAcquisitionReason: String, Codable, Equatable, Sendable {
    case opaqueOrSignedArtifact = "opaque_or_signed_artifact"
    case unsupportedAction = "unsupported_action"
    case sensitiveValue = "sensitive_value"
    case deviceBoundReference = "device_bound_reference"
    case unsupportedStructure = "unsupported_structure"
    case invalidActionGraph = "invalid_action_graph"
}

public struct ShortcutAcquisitionResult: Codable, Equatable, Sendable {
    public let operation: String
    public let experimental: Bool
    public let inputSHA256: String
    public let inputBytes: Int
    public let artifactKind: ShortcutAcquisitionArtifactKind
    public let parseStatus: ShortcutAcquisitionParseStatus
    public let capability: ShortcutAcquisitionCapability
    public let actionCount: Int?
    public let unsupportedActionCount: Int
    public let sensitiveValueDetected: Bool
    public let deviceBoundReferenceDetected: Bool
    public let unsupportedStructureDetected: Bool
    public let canGenerateEditPlan: Bool
    public let canApplySemanticEdit: Bool
    public let requiresManualMigration: Bool
    public let reasons: [ShortcutAcquisitionReason]
}

public struct ShortcutAcquisitionClassifier: Sendable {
    public static let maximumInputBytes = 10 * 1024 * 1024
    private static let maximumNodeCount = 100_000
    private static let maximumDepth = 64

    private static let planActionAllowlist: Set<String> = [
        "is.workflow.actions.comment",
        "is.workflow.actions.nothing",
        "is.workflow.actions.output",
        "is.workflow.actions.text",
    ]

    public init() {}

    public func inspect(inputURL: URL) throws -> ShortcutAcquisitionResult {
        let extensionName = inputURL.pathExtension.lowercased()
        let data = try ShortcutLocalInputReader.read(inputURL, allowedExtensions: ["cherri", "shortcut"], maximumBytes: Self.maximumInputBytes)
        return try inspect(data: data, extensionName: extensionName)
    }

    func inspect(data: Data, extensionName: String) throws -> ShortcutAcquisitionResult {
        guard !data.isEmpty else { throw ShortcutsError.acquisitionInputInvalid }
        let hash = CherriSourceValidator.hash(data)

        if extensionName == "cherri" {
            _ = try CherriSourceValidator().validate(data)
            return ShortcutAcquisitionResult(
                operation: "inspect",
                experimental: true,
                inputSHA256: hash,
                inputBytes: data.count,
                artifactKind: .cherriSource,
                parseStatus: .sourceValidated,
                capability: .managedSourceRoute,
                actionCount: nil,
                unsupportedActionCount: 0,
                sensitiveValueDetected: false,
                deviceBoundReferenceDetected: false,
                unsupportedStructureDetected: false,
                canGenerateEditPlan: false,
                canApplySemanticEdit: false,
                requiresManualMigration: false,
                reasons: []
            )
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let actions = plist["WFWorkflowActions"] as? [[String: Any]] else {
            return manualResult(
                hash: hash,
                bytes: data.count,
                kind: .opaqueShortcut,
                status: .opaque,
                actionCount: nil,
                unsupportedActionCount: 0,
                sensitive: false,
                deviceBound: false,
                unsupportedStructure: false,
                reasons: [.opaqueOrSignedArtifact]
            )
        }

        guard !actions.isEmpty, actions.count <= CherriAuthoringBridge.maximumActionCount + 1 else {
            return manualResult(hash: hash, bytes: data.count, kind: .unsignedShortcut, status: .artifactParsed, actionCount: nil, unsupportedActionCount: 0, sensitive: false, deviceBound: false, unsupportedStructure: false, reasons: [.invalidActionGraph])
        }

        var unsupportedActionCount = 0
        var deviceBound = false
        var sensitive = false
        var unsupportedStructure = false
        var structureInvalid = false
        var visibleActionCount = 0
        for action in actions {
            guard let identifier = action["WFWorkflowActionIdentifier"] as? String, !identifier.isEmpty else {
                structureInvalid = true
                continue
            }
            if identifier != "is.workflow.actions.output" { visibleActionCount += 1 }
            if !Self.planActionAllowlist.contains(identifier) { unsupportedActionCount += 1 }
            if Self.looksDeviceBound(identifier) { deviceBound = true }
            guard let parameters = action["WFWorkflowActionParameters"] as? [String: Any] else {
                structureInvalid = true
                continue
            }
            let scan = Self.scan(parameters)
            sensitive = sensitive || scan.sensitive
            deviceBound = deviceBound || scan.deviceBound
            unsupportedStructure = unsupportedStructure || scan.unsupportedStructure
            structureInvalid = structureInvalid || scan.exceededBounds
        }

        var reasons: [ShortcutAcquisitionReason] = []
        if structureInvalid || visibleActionCount == 0 { reasons.append(.invalidActionGraph) }
        if unsupportedActionCount > 0 { reasons.append(.unsupportedAction) }
        if sensitive { reasons.append(.sensitiveValue) }
        if deviceBound { reasons.append(.deviceBoundReference) }
        if unsupportedStructure { reasons.append(.unsupportedStructure) }
        if !reasons.isEmpty {
            return manualResult(
                hash: hash,
                bytes: data.count,
                kind: .unsignedShortcut,
                status: .artifactParsed,
                actionCount: visibleActionCount,
                unsupportedActionCount: unsupportedActionCount,
                sensitive: sensitive,
                deviceBound: deviceBound,
                unsupportedStructure: unsupportedStructure,
                reasons: reasons
            )
        }

        return ShortcutAcquisitionResult(
            operation: "inspect",
            experimental: true,
            inputSHA256: hash,
            inputBytes: data.count,
            artifactKind: .unsignedShortcut,
            parseStatus: .artifactParsed,
            capability: .semanticEditCandidate,
            actionCount: visibleActionCount,
            unsupportedActionCount: 0,
            sensitiveValueDetected: false,
            deviceBoundReferenceDetected: false,
            unsupportedStructureDetected: false,
            canGenerateEditPlan: true,
            canApplySemanticEdit: false,
            requiresManualMigration: false,
            reasons: []
        )
    }

    private func manualResult(hash: String, bytes: Int, kind: ShortcutAcquisitionArtifactKind, status: ShortcutAcquisitionParseStatus, actionCount: Int?, unsupportedActionCount: Int, sensitive: Bool, deviceBound: Bool, unsupportedStructure: Bool, reasons: [ShortcutAcquisitionReason]) -> ShortcutAcquisitionResult {
        ShortcutAcquisitionResult(
            operation: "inspect",
            experimental: true,
            inputSHA256: hash,
            inputBytes: bytes,
            artifactKind: kind,
            parseStatus: status,
            capability: .manualMigrationRequired,
            actionCount: actionCount,
            unsupportedActionCount: unsupportedActionCount,
            sensitiveValueDetected: sensitive,
            deviceBoundReferenceDetected: deviceBound,
            unsupportedStructureDetected: unsupportedStructure,
            canGenerateEditPlan: false,
            canApplySemanticEdit: false,
            requiresManualMigration: true,
            reasons: reasons
        )
    }

    private struct ScanResult {
        var sensitive = false
        var deviceBound = false
        var unsupportedStructure = false
        var exceededBounds = false
    }

    private struct ScanNode {
        let key: String?
        let value: Any
        let depth: Int
    }

    private static func scan(_ root: Any) -> ScanResult {
        var result = ScanResult()
        var nodes = [ScanNode(key: nil, value: root, depth: 0)]
        var visited = 0
        while let node = nodes.popLast() {
            visited += 1
            if visited > maximumNodeCount || node.depth > maximumDepth {
                result.exceededBounds = true
                break
            }
            if let key = node.key {
                result.sensitive = result.sensitive || looksSensitiveKey(key)
                result.deviceBound = result.deviceBound || looksDeviceBound(key)
            }
            if let dictionary = node.value as? [String: Any] {
                if node.depth > 0 { result.unsupportedStructure = true }
                nodes.append(contentsOf: dictionary.map { ScanNode(key: $0.key, value: $0.value, depth: node.depth + 1) })
            } else if let array = node.value as? [Any] {
                if node.depth > 0 { result.unsupportedStructure = true }
                nodes.append(contentsOf: array.map { ScanNode(key: nil, value: $0, depth: node.depth + 1) })
            } else if node.depth > 0, node.value is Data {
                result.unsupportedStructure = true
            } else if let text = node.value as? String {
                result.sensitive = result.sensitive || looksSensitiveText(text)
            }
        }
        return result
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func looksSensitiveKey(_ value: String) -> Bool {
        let key = normalized(value)
        return ["apikey", "apitoken", "accesstoken", "authorization", "bearer", "password", "secret"].contains { key.contains($0) }
    }

    private static func looksSensitiveText(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.range(of: #"(?:api[_-]?key|api[_-]?token|access[_-]?token|password|secret)\s*="# , options: .regularExpression) != nil {
            return true
        }
        if lower.hasPrefix("bearer "), lower.count > 16 { return true }
        guard let components = URLComponents(string: value), components.scheme != nil else { return false }
        if components.user != nil || components.password != nil { return true }
        return components.queryItems?.contains(where: { looksSensitiveKey($0.name) }) ?? false
    }

    private static func looksDeviceBound(_ value: String) -> Bool {
        let key = normalized(value)
        return ["homeaccessory", "homekit", "healthsample", "deviceidentifier", "bluetoothdevice", "nfc", "carplay"].contains { key.contains($0) }
    }
}
