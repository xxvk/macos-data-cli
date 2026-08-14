import Core
import Foundation

public enum ShortcutEditOperationKind: String, Codable, Equatable, Sendable {
    case insertText = "insert_text"
    case replaceText = "replace_text"
    case deleteAction = "delete_action"
    case moveAction = "move_action"
}

public struct ShortcutEditOperationSummary: Codable, Equatable, Sendable {
    public let sequence: Int
    public let operation: ShortcutEditOperationKind
    public let index: Int?
    public let fromIndex: Int?
    public let toIndex: Int?
    public let valueBytes: Int?
    public let valueSHA256: String?
}

public struct ShortcutEditPlanResult: Codable, Equatable, Sendable {
    public let operation: String
    public let experimental: Bool
    public let inputSHA256: String
    public let inputBytes: Int
    public let planSHA256: String
    public let operationCount: Int
    public let initialActionCount: Int
    public let finalActionCount: Int
    public let operations: [ShortcutEditOperationSummary]
    public let canApplySemanticEdit: Bool
    public let nextAction: String
}

public struct ShortcutEditExecutionOperation: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let summary: ShortcutEditOperationSummary
    public let textValue: String?

    public init(summary: ShortcutEditOperationSummary, textValue: String?) {
        self.summary = summary
        self.textValue = textValue
    }

    public var description: String { "ShortcutEditExecutionOperation(sequence: \(summary.sequence), operation: \(summary.operation.rawValue), privateValue: redacted)" }
    public var debugDescription: String { description }
}

public struct ShortcutEditExecutionPlan: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let publicResult: ShortcutEditPlanResult
    public let operations: [ShortcutEditExecutionOperation]

    public init(publicResult: ShortcutEditPlanResult, operations: [ShortcutEditExecutionOperation]) {
        self.publicResult = publicResult
        self.operations = operations
    }

    public var description: String {
        "ShortcutEditExecutionPlan(planSHA256: \(publicResult.planSHA256), operationCount: \(operations.count), privateValues: redacted)"
    }
    public var debugDescription: String { description }
}

public struct ShortcutEditPlanService: Sendable {
    public static let maximumPatchBytes = 256 * 1024
    public static let maximumOperationCount = 64
    public static let maximumValueBytes = 64 * 1024

    private enum ActionKind { case text, comment, nothing }

    public init() {}

    public func plan(inputURL: URL, patchURL: URL) throws -> ShortcutEditPlanResult {
        let patchData = try ShortcutLocalInputReader.read(patchURL, allowedExtensions: ["json"], maximumBytes: Self.maximumPatchBytes)
        return try plan(inputURL: inputURL, patchData: patchData)
    }

    public func plan(inputURL: URL, patchData: Data) throws -> ShortcutEditPlanResult {
        try prepare(inputURL: inputURL, patchData: patchData).publicResult
    }

    public func prepare(inputURL: URL, patchURL: URL) throws -> ShortcutEditExecutionPlan {
        let patchData = try ShortcutLocalInputReader.read(patchURL, allowedExtensions: ["json"], maximumBytes: Self.maximumPatchBytes)
        return try prepare(inputURL: inputURL, patchData: patchData)
    }

    public func prepare(inputURL: URL, patchData: Data) throws -> ShortcutEditExecutionPlan {
        guard inputURL.pathExtension.lowercased() == "shortcut",
              !patchData.isEmpty,
              patchData.count <= Self.maximumPatchBytes else {
            throw ShortcutsError.editPlanInvalid
        }
        let inputData = try ShortcutLocalInputReader.read(inputURL, allowedExtensions: ["shortcut"], maximumBytes: ShortcutAcquisitionClassifier.maximumInputBytes)
        let inspection = try ShortcutAcquisitionClassifier().inspect(data: inputData, extensionName: "shortcut")
        guard inspection.capability == .semanticEditCandidate else { throw ShortcutsError.editCapabilityUnsupported }
        let parsed = try Self.parsePatch(patchData)
        guard parsed.expectedInputSHA256 == inspection.inputSHA256 else { throw ShortcutsError.editSourceConflict }
        guard var graph = Self.visibleGraph(inputData), !graph.isEmpty else { throw ShortcutsError.editPlanInvalid }
        let initialCount = graph.count
        var applyCapable = true
        var summaries: [ShortcutEditOperationSummary] = []
        var executionOperations: [ShortcutEditExecutionOperation] = []

        for (sequence, operation) in parsed.operations.enumerated() {
            switch operation {
            case let .insertText(index, value):
                guard (0...graph.count).contains(index) else { throw ShortcutsError.editPlanInvalid }
                applyCapable = applyCapable && index == graph.count && graph.contains(.text)
                graph.insert(.text, at: index)
                let summary = Self.summary(sequence, .insertText, index: index, value: value)
                summaries.append(summary)
                executionOperations.append(.init(summary: summary, textValue: value))
            case let .replaceText(index, value):
                guard graph.indices.contains(index), graph[index] == .text else { throw ShortcutsError.editPlanInvalid }
                let summary = Self.summary(sequence, .replaceText, index: index, value: value)
                summaries.append(summary)
                executionOperations.append(.init(summary: summary, textValue: value))
            case let .deleteAction(index):
                guard graph.indices.contains(index), graph.count > 1 else { throw ShortcutsError.editPlanInvalid }
                graph.remove(at: index)
                let summary = ShortcutEditOperationSummary(sequence: sequence, operation: .deleteAction, index: index, fromIndex: nil, toIndex: nil, valueBytes: nil, valueSHA256: nil)
                summaries.append(summary)
                executionOperations.append(.init(summary: summary, textValue: nil))
            case let .moveAction(fromIndex, toIndex):
                guard graph.indices.contains(fromIndex), graph.indices.contains(toIndex) else { throw ShortcutsError.editPlanInvalid }
                let action = graph.remove(at: fromIndex)
                graph.insert(action, at: min(toIndex, graph.count))
                let summary = ShortcutEditOperationSummary(sequence: sequence, operation: .moveAction, index: nil, fromIndex: fromIndex, toIndex: toIndex, valueBytes: nil, valueSHA256: nil)
                summaries.append(summary)
                executionOperations.append(.init(summary: summary, textValue: nil))
            }
        }

        let operationFamilies = Set(summaries.map { $0.operation.rawValue })
        let canApplySemanticEdit = applyCapable && operationFamilies.count == 1
        let publicResult = ShortcutEditPlanResult(
            operation: "edit_plan",
            experimental: true,
            inputSHA256: inspection.inputSHA256,
            inputBytes: inspection.inputBytes,
            planSHA256: CherriSourceValidator.hash(patchData),
            operationCount: summaries.count,
            initialActionCount: initialCount,
            finalActionCount: graph.count,
            operations: summaries,
            canApplySemanticEdit: canApplySemanticEdit,
            nextAction: canApplySemanticEdit
                ? "Review this redacted plan, then use shortcuts edit copy with the same input and patch. Apply creates and verifies a distinct recovery copy."
                : "This plan contains operations that are not apply-capable. Do not send it to Accessibility; use manual migration."
        )
        return ShortcutEditExecutionPlan(publicResult: publicResult, operations: executionOperations)
    }

    private enum ParsedOperation {
        case insertText(Int, String)
        case replaceText(Int, String)
        case deleteAction(Int)
        case moveAction(Int, Int)
    }

    private struct ParsedPatch {
        let expectedInputSHA256: String
        let operations: [ParsedOperation]
    }

    private static func parsePatch(_ data: Data) throws -> ParsedPatch {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == ["expectedInputSHA256", "operations"],
              let hash = root["expectedInputSHA256"] as? String,
              hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              let rawOperations = root["operations"] as? [[String: Any]],
              (1...maximumOperationCount).contains(rawOperations.count) else {
            throw ShortcutsError.editPlanInvalid
        }
        return ParsedPatch(expectedInputSHA256: hash, operations: try rawOperations.map(parseOperation))
    }

    private static func parseOperation(_ value: [String: Any]) throws -> ParsedOperation {
        guard let name = value["operation"] as? String,
              let operation = ShortcutEditOperationKind(rawValue: name) else { throw ShortcutsError.editPlanInvalid }
        switch operation {
        case .insertText, .replaceText:
            guard Set(value.keys) == ["operation", "index", "value"],
                  let index = strictInteger(value["index"]), index >= 0,
                  let text = value["value"] as? String,
                  text.lengthOfBytes(using: .utf8) <= maximumValueBytes else { throw ShortcutsError.editPlanInvalid }
            return operation == .insertText ? .insertText(index, text) : .replaceText(index, text)
        case .deleteAction:
            guard Set(value.keys) == ["operation", "index"],
                  let index = strictInteger(value["index"]), index >= 0 else { throw ShortcutsError.editPlanInvalid }
            return .deleteAction(index)
        case .moveAction:
            guard Set(value.keys) == ["operation", "fromIndex", "toIndex"],
                  let from = strictInteger(value["fromIndex"]), from >= 0,
                  let to = strictInteger(value["toIndex"]), to >= 0,
                  from != to else { throw ShortcutsError.editPlanInvalid }
            return .moveAction(from, to)
        }
    }

    private static func strictInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private static func visibleGraph(_ data: Data) -> [ActionKind]? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let actions = plist["WFWorkflowActions"] as? [[String: Any]] else { return nil }
        return actions.compactMap { action in
            switch action["WFWorkflowActionIdentifier"] as? String {
            case "is.workflow.actions.text": .text
            case "is.workflow.actions.comment": .comment
            case "is.workflow.actions.nothing": .nothing
            case "is.workflow.actions.output": nil
            default: nil
            }
        }
    }

    private static func summary(_ sequence: Int, _ operation: ShortcutEditOperationKind, index: Int, value: String) -> ShortcutEditOperationSummary {
        let data = Data(value.utf8)
        return ShortcutEditOperationSummary(sequence: sequence, operation: operation, index: index, fromIndex: nil, toIndex: nil, valueBytes: data.count, valueSHA256: CherriSourceValidator.hash(data))
    }
}
