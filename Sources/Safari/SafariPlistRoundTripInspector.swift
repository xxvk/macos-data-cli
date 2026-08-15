import CryptoKit
import CoreFoundation
import Darwin
import Foundation

enum SafariPlistFeasibilityError: Error, Equatable {
    case sourceUnsafe
    case destinationExists
    case plistInvalid
    case semanticMismatch
    case modeMismatch
    case ownerMismatch
    case groupMismatch
    case extendedAttributesMismatch(source: [String], destination: [String])
    case duplicateIdentifier
    case mutationTargetInvalid
    case appendVerificationMismatch(
        missingOldNodes: Int,
        unexpectedNewNodes: Int,
        changedUntouchedSubtrees: Int,
        fixtureValid: Bool,
        parentMatched: Bool,
        missingNodeTypes: [String: Int],
        unexpectedNodeTypes: [String: Int],
        missingVolatileInternalNodes: Int,
        unexpectedVolatileInternalNodes: Int,
        uuidStrippedEquivalent: Bool
    )
    case fileOperationFailed
}

enum SafariPlistFormat: String, Equatable {
    case binary
    case xml
}

struct SafariPlistFileMetadata: Equatable {
    let mode: UInt16
    let ownerID: UInt32
    let groupID: UInt32
    let extendedAttributeNames: [String]
}

struct SafariPlistRoundTripReport: Equatable {
    let sourceFormat: SafariPlistFormat
    let outputFormat: SafariPlistFormat
    let sourceBytes: Int
    let outputBytes: Int
    let sourceSHA256: String
    let outputSHA256: String
    let byteIdentical: Bool
    let semanticEqual: Bool
    let orderedChildrenEqual: Bool
    let sourceMetadata: SafariPlistFileMetadata
    let destinationMetadata: SafariPlistFileMetadata
    let destinationAddedExtendedAttributeNames: [String]
}

struct SafariPlistMutationSimulationReport: Equatable {
    let sourceSHA256: String
    let outputData: Data
    let existingNodeCount: Int
    let untouchedNodeCount: Int
    let changedAncestorCount: Int
    let addedNodeCount: Int
    let untouchedSubtreeHashesPreserved: Bool
}

struct SafariPlistAppendVerificationReport: Equatable {
    let existingNodeCount: Int
    let currentNodeCount: Int
    let untouchedNodeCount: Int
    let changedAncestorCount: Int
    let addedNodeCount: Int
    let fixtureParentMatched: Bool
    let untouchedSubtreeHashesPreserved: Bool
    let volatileInternalUUIDReplacements: Int
}

struct SafariPlistReplacementDiagnostic: Equatable {
    let nodeType: String
    let titleEqual: Bool
    let parentEqual: Bool
    let beforeChildCount: Int
    let afterChildCount: Int
    let uuidStrippedChangedKeys: [String]
    let adapterExposedBefore: Bool
    let adapterExposedAfter: Bool
}

struct SafariPlistChangedNodeDiagnostic: Equatable {
    let nodeType: String
    let changedKeys: [String]
    let adapterExposedBefore: Bool
    let adapterExposedAfter: Bool
}

struct SafariPlistSnapshotDiffDiagnostic: Equatable {
    let beforeBookmarkCount: Int
    let afterBookmarkCount: Int
    let beforeReadingListCount: Int
    let afterReadingListCount: Int
    let missingBookmarkCount: Int
    let missingReadingListCount: Int
    let missingInternalCount: Int
}

enum SafariExtendedAttributes {
    static let maximumTotalBytes = 1024 * 1024

    static func names(at url: URL) throws -> [String] {
        let length = listxattr(url.path, nil, 0, 0)
        guard length >= 0 else { throw SafariPlistFeasibilityError.fileOperationFailed }
        guard length > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: length)
        guard listxattr(url.path, &buffer, buffer.count, 0) == length else {
            throw SafariPlistFeasibilityError.fileOperationFailed
        }
        return buffer.split(separator: 0).map { bytes in
            bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }.sorted()
    }

    static func value(name: String, at url: URL) throws -> Data {
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length >= 0, length <= maximumTotalBytes else {
            throw SafariPlistFeasibilityError.fileOperationFailed
        }
        guard length > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: length)
        let result = bytes.withUnsafeMutableBytes { buffer in
            getxattr(url.path, name, buffer.baseAddress, buffer.count, 0, 0)
        }
        guard result == length else { throw SafariPlistFeasibilityError.fileOperationFailed }
        return Data(bytes)
    }

    static func set(name: String, value: Data, at url: URL) throws {
        guard value.count <= maximumTotalBytes else { throw SafariPlistFeasibilityError.fileOperationFailed }
        let result = value.withUnsafeBytes { buffer in
            setxattr(url.path, name, buffer.baseAddress, buffer.count, 0, 0)
        }
        guard result == 0 else { throw SafariPlistFeasibilityError.fileOperationFailed }
    }

    static func remove(name: String, at url: URL) throws {
        guard removexattr(url.path, name, 0) == 0 else {
            throw SafariPlistFeasibilityError.fileOperationFailed
        }
    }

    static func values(at url: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        var total = 0
        for name in try names(at: url) {
            let data = try value(name: name, at: url)
            total += data.count
            guard total <= maximumTotalBytes else { throw SafariPlistFeasibilityError.fileOperationFailed }
            result[name] = data
        }
        return result
    }
}

enum SafariPlistRoundTripInspector {
    private struct ParsedPlist {
        let object: [String: Any]
        let format: SafariPlistFormat
        let serialized: Data
        let orderedChildren: [String]
    }

    static func inspect(data: Data) throws -> SafariPlistRoundTripReport {
        let parsed = try parseAndSerialize(data)
        let reparsed = try parseAndSerialize(parsed.serialized)
        let semanticEqual = NSDictionary(dictionary: parsed.object).isEqual(to: reparsed.object)
        let orderedChildrenEqual = parsed.orderedChildren == reparsed.orderedChildren
        return .init(
            sourceFormat: parsed.format,
            outputFormat: reparsed.format,
            sourceBytes: data.count,
            outputBytes: parsed.serialized.count,
            sourceSHA256: digest(data),
            outputSHA256: digest(parsed.serialized),
            byteIdentical: data == parsed.serialized,
            semanticEqual: semanticEqual,
            orderedChildrenEqual: orderedChildrenEqual,
            sourceMetadata: emptyMetadata,
            destinationMetadata: emptyMetadata,
            destinationAddedExtendedAttributeNames: []
        )
    }

    static func writePrivateCopy(source: URL, destination: URL) throws -> SafariPlistRoundTripReport {
        let sourceState = try fileState(at: source)
        guard sourceState.ownerID == UInt32(geteuid()) else { throw SafariPlistFeasibilityError.sourceUnsafe }
        guard lstatExists(destination.path) == false else { throw SafariPlistFeasibilityError.destinationExists }

        let sourceData = try boundedData(at: source)
        let parsed = try parseAndSerialize(sourceData)
        let roundTrip = try parseAndSerialize(parsed.serialized)
        guard NSDictionary(dictionary: parsed.object).isEqual(to: roundTrip.object),
              parsed.orderedChildren == roundTrip.orderedChildren else {
            throw SafariPlistFeasibilityError.semanticMismatch
        }

        let xattrs = try SafariExtendedAttributes.values(at: source)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".mpia-safari-" + UUID().uuidString + ".tmp")
        var destinationCreated = false
        var completed = false
        defer { try? FileManager.default.removeItem(at: temporary) }
        defer {
            if destinationCreated && !completed { try? FileManager.default.removeItem(at: destination) }
        }
        do {
            let copyFlags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_EXCL)
            guard copyfile(source.path, temporary.path, nil, copyFlags) == 0 else {
                throw SafariPlistFeasibilityError.fileOperationFailed
            }
            let handle = try FileHandle(forWritingTo: temporary)
            do {
                try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: parsed.serialized)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            guard chmod(temporary.path, mode_t(sourceState.mode)) == 0,
                  chown(temporary.path, uid_t(sourceState.ownerID), gid_t(sourceState.groupID)) == 0 else {
                throw SafariPlistFeasibilityError.fileOperationFailed
            }
            for name in try SafariExtendedAttributes.names(at: temporary) where xattrs[name] == nil {
                try SafariExtendedAttributes.remove(name: name, at: temporary)
            }
            for (name, value) in xattrs { try SafariExtendedAttributes.set(name: name, value: value, at: temporary) }
            for name in try SafariExtendedAttributes.names(at: temporary) where xattrs[name] == nil {
                try SafariExtendedAttributes.remove(name: name, at: temporary)
            }
            guard link(temporary.path, destination.path) == 0 else {
                if errno == EEXIST { throw SafariPlistFeasibilityError.destinationExists }
                throw SafariPlistFeasibilityError.fileOperationFailed
            }
            destinationCreated = true
            for name in try SafariExtendedAttributes.names(at: destination) where xattrs[name] == nil {
                try SafariExtendedAttributes.remove(name: name, at: destination)
            }
        } catch let error as SafariPlistFeasibilityError {
            throw error
        } catch {
            throw SafariPlistFeasibilityError.fileOperationFailed
        }

        let destinationState = try fileState(at: destination)
        guard destinationState.mode == sourceState.mode else { throw SafariPlistFeasibilityError.modeMismatch }
        guard destinationState.ownerID == sourceState.ownerID else { throw SafariPlistFeasibilityError.ownerMismatch }
        guard destinationState.groupID == sourceState.groupID else { throw SafariPlistFeasibilityError.groupMismatch }
        let destinationXattrs = try SafariExtendedAttributes.values(at: destination)
        guard xattrs.allSatisfy({ destinationXattrs[$0.key] == $0.value }) else {
            throw SafariPlistFeasibilityError.extendedAttributesMismatch(
                source: sourceState.extendedAttributeNames,
                destination: destinationState.extendedAttributeNames
            )
        }
        let addedXattrs = destinationState.extendedAttributeNames.filter { xattrs[$0] == nil }
        guard Set(addedXattrs).isSubset(of: ["com.apple.provenance"]) else {
            throw SafariPlistFeasibilityError.extendedAttributesMismatch(
                source: sourceState.extendedAttributeNames,
                destination: destinationState.extendedAttributeNames
            )
        }
        completed = true
        return .init(
            sourceFormat: parsed.format,
            outputFormat: roundTrip.format,
            sourceBytes: sourceData.count,
            outputBytes: parsed.serialized.count,
            sourceSHA256: digest(sourceData),
            outputSHA256: digest(parsed.serialized),
            byteIdentical: sourceData == parsed.serialized,
            semanticEqual: true,
            orderedChildrenEqual: true,
            sourceMetadata: sourceState,
            destinationMetadata: destinationState,
            destinationAddedExtendedAttributeNames: addedXattrs
        )
    }

    static func simulateAppendBookmark(
        data: Data,
        parentUUID: String,
        bookmark: [String: Any]
    ) throws -> SafariPlistMutationSimulationReport {
        let parsed = try parseAndSerialize(data)
        var beforeNodes: [String: [String: Any]] = [:]
        var parents: [String: String?] = [:]
        try collectNodes(parsed.object, parentUUID: nil, nodes: &beforeNodes, parents: &parents)

        guard let parent = beforeNodes[parentUUID],
              parent["WebBookmarkType"] as? String == "WebBookmarkTypeList",
              let newUUID = bookmark["WebBookmarkUUID"] as? String,
              !newUUID.isEmpty,
              bookmark["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf",
              bookmark["Children"] == nil,
              beforeNodes[newUUID] == nil else {
            if let newUUID = bookmark["WebBookmarkUUID"] as? String, beforeNodes[newUUID] != nil {
                throw SafariPlistFeasibilityError.duplicateIdentifier
            }
            throw SafariPlistFeasibilityError.mutationTargetInvalid
        }

        var changedAncestors = Set<String>()
        var cursor: String? = parentUUID
        while let identifier = cursor {
            guard changedAncestors.insert(identifier).inserted else {
                throw SafariPlistFeasibilityError.plistInvalid
            }
            cursor = parents[identifier] ?? nil
        }

        let mutatedRoot = try appending(bookmark, to: parentUUID, in: parsed.object)
        let outputData: Data
        do {
            let format: PropertyListSerialization.PropertyListFormat = parsed.format == .xml ? .xml : .binary
            outputData = try PropertyListSerialization.data(fromPropertyList: mutatedRoot, format: format, options: 0)
        } catch {
            throw SafariPlistFeasibilityError.plistInvalid
        }
        _ = try parseAndSerialize(outputData)

        var afterNodes: [String: [String: Any]] = [:]
        var afterParents: [String: String?] = [:]
        try collectNodes(mutatedRoot, parentUUID: nil, nodes: &afterNodes, parents: &afterParents)
        guard afterNodes.count == beforeNodes.count + 1, afterNodes[newUUID] != nil else {
            throw SafariPlistFeasibilityError.semanticMismatch
        }

        let untouched = beforeNodes.keys.filter { !changedAncestors.contains($0) }
        let preserved = try untouched.allSatisfy { identifier in
            guard let before = beforeNodes[identifier], let after = afterNodes[identifier] else { return false }
            return try subtreeDigest(before) == subtreeDigest(after)
        }
        guard preserved else { throw SafariPlistFeasibilityError.semanticMismatch }

        return .init(
            sourceSHA256: digest(data),
            outputData: outputData,
            existingNodeCount: beforeNodes.count,
            untouchedNodeCount: untouched.count,
            changedAncestorCount: changedAncestors.count,
            addedNodeCount: afterNodes.count - beforeNodes.count,
            untouchedSubtreeHashesPreserved: preserved
        )
    }

    static func standardBookmarksBarUUID(data: Data) throws -> String {
        let parsed = try parseAndSerialize(data)
        var nodes: [String: [String: Any]] = [:]
        var parents: [String: String?] = [:]
        try collectNodes(parsed.object, parentUUID: nil, nodes: &nodes, parents: &parents)
        let matches = nodes.compactMap { identifier, node -> String? in
            guard node["WebBookmarkType"] as? String == "WebBookmarkTypeList",
                  node["Title"] as? String == "BookmarksBar" else { return nil }
            return identifier
        }
        guard matches.count == 1 else { throw SafariPlistFeasibilityError.mutationTargetInvalid }
        return matches[0]
    }

    static func verifySingleAppend(
        beforeData: Data,
        afterData: Data,
        parentUUID: String,
        fixtureUUID: String
    ) throws -> SafariPlistAppendVerificationReport {
        let beforeRoot = try parseAndSerialize(beforeData).object
        let afterRoot = try parseAndSerialize(afterData).object
        let beforeSnapshot = try SafariBookmarksParser.parse(data: beforeData)
        let afterSnapshot = try SafariBookmarksParser.parse(data: afterData)
        var beforeNodes: [String: [String: Any]] = [:]
        var beforeParents: [String: String?] = [:]
        var afterNodes: [String: [String: Any]] = [:]
        var afterParents: [String: String?] = [:]
        try collectNodes(beforeRoot, parentUUID: nil, nodes: &beforeNodes, parents: &beforeParents)
        try collectNodes(afterRoot, parentUUID: nil, nodes: &afterNodes, parents: &afterParents)
        let missing = Set(beforeNodes.keys).subtracting(afterNodes.keys)
        let added = Set(afterNodes.keys).subtracting(beforeNodes.keys)
        let unexpected = added.subtracting([fixtureUUID])
        let fixture = afterNodes[fixtureUUID]
        let fixtureValid = beforeNodes[fixtureUUID] == nil &&
            fixture?["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf" &&
            fixture?["Children"] == nil

        var ancestors = Set<String>()
        var cursor: String? = parentUUID
        while let identifier = cursor {
            guard beforeNodes[identifier] != nil, ancestors.insert(identifier).inserted else {
                throw SafariPlistFeasibilityError.semanticMismatch
            }
            cursor = beforeParents[identifier] ?? nil
        }
        let untouched = beforeNodes.keys.filter { !ancestors.contains($0) }
        let changedUntouched = try untouched.filter { identifier in
            guard let before = beforeNodes[identifier], let after = afterNodes[identifier] else { return false }
            return try subtreeDigest(before) != subtreeDigest(after)
        }
        let parentMatched = afterParents[fixtureUUID] == parentUUID
        let volatileAnalysis = try analyzeVolatileReplacement(
            missing: missing,
            unexpected: unexpected,
            beforeNodes: beforeNodes,
            afterNodes: afterNodes,
            beforeParents: beforeParents,
            afterParents: afterParents,
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            fixtureUUID: fixtureUUID
        )
        guard (missing.isEmpty && unexpected.isEmpty || volatileAnalysis.allowed), added.contains(fixtureUUID),
              changedUntouched.isEmpty, fixtureValid, parentMatched else {
            throw SafariPlistFeasibilityError.appendVerificationMismatch(
                missingOldNodes: missing.count,
                unexpectedNewNodes: unexpected.count,
                changedUntouchedSubtrees: changedUntouched.count,
                fixtureValid: fixtureValid,
                parentMatched: parentMatched,
                missingNodeTypes: nodeTypeCounts(missing, nodes: beforeNodes),
                unexpectedNodeTypes: nodeTypeCounts(unexpected, nodes: afterNodes),
                missingVolatileInternalNodes: volatileAnalysis.missingInternal,
                unexpectedVolatileInternalNodes: volatileAnalysis.unexpectedInternal,
                uuidStrippedEquivalent: volatileAnalysis.uuidStrippedEquivalent
            )
        }
        return .init(
            existingNodeCount: beforeNodes.count,
            currentNodeCount: afterNodes.count,
            untouchedNodeCount: untouched.count,
            changedAncestorCount: ancestors.count,
            addedNodeCount: afterNodes.count - beforeNodes.count,
            fixtureParentMatched: true,
            untouchedSubtreeHashesPreserved: true,
            volatileInternalUUIDReplacements: volatileAnalysis.allowed ? missing.count : 0
        )
    }

    static func replacementDiagnostics(
        beforeData: Data,
        afterData: Data,
        fixtureUUID: String
    ) throws -> [SafariPlistReplacementDiagnostic] {
        let beforeRoot = try parseAndSerialize(beforeData).object
        let afterRoot = try parseAndSerialize(afterData).object
        let beforeSnapshot = try SafariBookmarksParser.parse(data: beforeData)
        let afterSnapshot = try SafariBookmarksParser.parse(data: afterData)
        var beforeNodes: [String: [String: Any]] = [:]
        var beforeParents: [String: String?] = [:]
        var afterNodes: [String: [String: Any]] = [:]
        var afterParents: [String: String?] = [:]
        try collectNodes(beforeRoot, parentUUID: nil, nodes: &beforeNodes, parents: &beforeParents)
        try collectNodes(afterRoot, parentUUID: nil, nodes: &afterNodes, parents: &afterParents)
        let missing = Set(beforeNodes.keys).subtracting(afterNodes.keys)
        let added = Set(afterNodes.keys).subtracting(beforeNodes.keys).subtracting([fixtureUUID])
        let types = Set(missing.compactMap { beforeNodes[$0]?["WebBookmarkType"] as? String })
            .union(added.compactMap { afterNodes[$0]?["WebBookmarkType"] as? String })
        return try types.sorted().compactMap { type in
            let beforeMatches = missing.compactMap { identifier -> (String, [String: Any])? in
                guard let node = beforeNodes[identifier], node["WebBookmarkType"] as? String == type else { return nil }
                return (identifier, node)
            }
            let afterMatches = added.compactMap { identifier -> (String, [String: Any])? in
                guard let node = afterNodes[identifier], node["WebBookmarkType"] as? String == type else { return nil }
                return (identifier, node)
            }
            guard beforeMatches.count == 1, afterMatches.count == 1 else { return nil }
            let before = beforeMatches[0]
            let after = afterMatches[0]
            let keys = Set(before.1.keys).union(after.1.keys).subtracting(["WebBookmarkUUID"])
            let changed = try keys.filter { key in
                guard let beforeValue = before.1[key], let afterValue = after.1[key] else { return true }
                return try canonicalRepresentation(strippingUUIDs(beforeValue)) !=
                    canonicalRepresentation(strippingUUIDs(afterValue))
            }.sorted()
            return .init(
                nodeType: type,
                titleEqual: before.1["Title"] as? String == after.1["Title"] as? String,
                parentEqual: beforeParents[before.0] == afterParents[after.0],
                beforeChildCount: (before.1["Children"] as? [[String: Any]])?.count ?? 0,
                afterChildCount: (after.1["Children"] as? [[String: Any]])?.count ?? 0,
                uuidStrippedChangedKeys: changed,
                adapterExposedBefore: type == "WebBookmarkTypeList" && beforeSnapshot.bookmarks.contains {
                    $0.id == SafariOpaqueID.folder(uuid: before.0)
                },
                adapterExposedAfter: type == "WebBookmarkTypeList" && afterSnapshot.bookmarks.contains {
                    $0.id == SafariOpaqueID.folder(uuid: after.0)
                }
            )
        }
    }

    static func changedUntouchedDiagnostics(
        beforeData: Data,
        afterData: Data,
        parentUUID: String
    ) throws -> [SafariPlistChangedNodeDiagnostic] {
        let beforeRoot = try parseAndSerialize(beforeData).object
        let afterRoot = try parseAndSerialize(afterData).object
        let beforeSnapshot = try SafariBookmarksParser.parse(data: beforeData)
        let afterSnapshot = try SafariBookmarksParser.parse(data: afterData)
        var beforeNodes: [String: [String: Any]] = [:]
        var beforeParents: [String: String?] = [:]
        var afterNodes: [String: [String: Any]] = [:]
        var afterParents: [String: String?] = [:]
        try collectNodes(beforeRoot, parentUUID: nil, nodes: &beforeNodes, parents: &beforeParents)
        try collectNodes(afterRoot, parentUUID: nil, nodes: &afterNodes, parents: &afterParents)
        var ancestors = Set<String>()
        var cursor: String? = parentUUID
        while let identifier = cursor {
            guard ancestors.insert(identifier).inserted else { break }
            cursor = beforeParents[identifier] ?? nil
        }
        return try Set(beforeNodes.keys).intersection(afterNodes.keys).subtracting(ancestors).compactMap { identifier in
            guard let before = beforeNodes[identifier], let after = afterNodes[identifier],
                  try subtreeDigest(before) != subtreeDigest(after) else { return nil }
            let type = before["WebBookmarkType"] as? String ?? "missingType"
            let keys = Set(before.keys).union(after.keys)
            let changed = try keys.filter { key in
                guard let beforeValue = before[key], let afterValue = after[key] else { return true }
                return try canonicalRepresentation(beforeValue) != canonicalRepresentation(afterValue)
            }.sorted()
            return .init(
                nodeType: type,
                changedKeys: changed,
                adapterExposedBefore: snapshot(beforeSnapshot, exposes: identifier, type: type),
                adapterExposedAfter: snapshot(afterSnapshot, exposes: identifier, type: type)
            )
        }.sorted { lhs, rhs in
            lhs.nodeType == rhs.nodeType
                ? lhs.changedKeys.joined() < rhs.changedKeys.joined()
                : lhs.nodeType < rhs.nodeType
        }
    }

    static func snapshotDiffDiagnostic(beforeData: Data, afterData: Data) throws -> SafariPlistSnapshotDiffDiagnostic {
        let beforeRoot = try parseAndSerialize(beforeData).object
        let afterRoot = try parseAndSerialize(afterData).object
        let beforeSnapshot = try SafariBookmarksParser.parse(data: beforeData)
        let afterSnapshot = try SafariBookmarksParser.parse(data: afterData)
        var beforeNodes: [String: [String: Any]] = [:]
        var beforeParents: [String: String?] = [:]
        var afterNodes: [String: [String: Any]] = [:]
        var afterParents: [String: String?] = [:]
        try collectNodes(beforeRoot, parentUUID: nil, nodes: &beforeNodes, parents: &beforeParents)
        try collectNodes(afterRoot, parentUUID: nil, nodes: &afterNodes, parents: &afterParents)
        let missing = Set(beforeNodes.keys).subtracting(afterNodes.keys)
        let missingBookmarks = missing.filter { identifier in
            beforeSnapshot.bookmarks.contains {
                $0.id == SafariOpaqueID.bookmark(uuid: identifier) || $0.id == SafariOpaqueID.folder(uuid: identifier)
            }
        }.count
        let missingReadingList = missing.filter { identifier in
            beforeSnapshot.readingList.contains { $0.id == SafariOpaqueID.readingList(uuid: identifier) }
        }.count
        return .init(
            beforeBookmarkCount: beforeSnapshot.bookmarks.count,
            afterBookmarkCount: afterSnapshot.bookmarks.count,
            beforeReadingListCount: beforeSnapshot.readingList.count,
            afterReadingListCount: afterSnapshot.readingList.count,
            missingBookmarkCount: missingBookmarks,
            missingReadingListCount: missingReadingList,
            missingInternalCount: missing.count - missingBookmarks - missingReadingList
        )
    }

    private static func snapshot(_ snapshot: SafariBookmarksSnapshot, exposes uuid: String, type: String) -> Bool {
        switch type {
        case "WebBookmarkTypeList":
            return snapshot.bookmarks.contains { $0.id == SafariOpaqueID.folder(uuid: uuid) }
        case "WebBookmarkTypeLeaf":
            return snapshot.bookmarks.contains { $0.id == SafariOpaqueID.bookmark(uuid: uuid) } ||
                snapshot.readingList.contains { $0.id == SafariOpaqueID.readingList(uuid: uuid) }
        default:
            return false
        }
    }

    private static var emptyMetadata: SafariPlistFileMetadata {
        .init(mode: 0, ownerID: 0, groupID: 0, extendedAttributeNames: [])
    }

    private static func parseAndSerialize(_ data: Data) throws -> ParsedPlist {
        guard data.count <= SystemSafariBookmarksSnapshotReader.maximumBytes else {
            throw SafariPlistFeasibilityError.sourceUnsafe
        }
        var propertyListFormat = PropertyListSerialization.PropertyListFormat.binary
        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(from: data, options: [], format: &propertyListFormat)
        } catch {
            throw SafariPlistFeasibilityError.plistInvalid
        }
        guard let root = value as? [String: Any],
              root["WebBookmarkFileVersion"] is NSNumber,
              root["WebBookmarkType"] as? String == "WebBookmarkTypeList",
              root["Children"] is [[String: Any]] else {
            throw SafariPlistFeasibilityError.plistInvalid
        }
        let outputFormat: PropertyListSerialization.PropertyListFormat = propertyListFormat == .xml ? .xml : .binary
        let serialized: Data
        do {
            serialized = try PropertyListSerialization.data(fromPropertyList: root, format: outputFormat, options: 0)
        } catch {
            throw SafariPlistFeasibilityError.plistInvalid
        }
        return .init(
            object: root,
            format: propertyListFormat == .xml ? .xml : .binary,
            serialized: serialized,
            orderedChildren: orderedChildIdentifiers(root)
        )
    }

    private static func orderedChildIdentifiers(_ node: [String: Any]) -> [String] {
        guard let children = node["Children"] as? [[String: Any]] else { return [] }
        return children.flatMap { child -> [String] in
            let identifier = child["WebBookmarkUUID"] as? String ?? "<missing>"
            return [identifier] + orderedChildIdentifiers(child)
        }
    }

    private static func collectNodes(
        _ node: [String: Any],
        parentUUID: String?,
        nodes: inout [String: [String: Any]],
        parents: inout [String: String?]
    ) throws {
        guard let type = node["WebBookmarkType"] as? String,
              ["WebBookmarkTypeList", "WebBookmarkTypeLeaf", "WebBookmarkTypeProxy"].contains(type),
              let identifier = node["WebBookmarkUUID"] as? String,
              !identifier.isEmpty,
              nodes[identifier] == nil else {
            if let identifier = node["WebBookmarkUUID"] as? String, nodes[identifier] != nil {
                throw SafariPlistFeasibilityError.duplicateIdentifier
            }
            throw SafariPlistFeasibilityError.plistInvalid
        }
        nodes[identifier] = node
        parents[identifier] = parentUUID
        if let value = node["Children"] {
            guard type == "WebBookmarkTypeList", let children = value as? [[String: Any]] else {
                throw SafariPlistFeasibilityError.plistInvalid
            }
            for child in children {
                try collectNodes(child, parentUUID: identifier, nodes: &nodes, parents: &parents)
            }
        }
    }

    private static func appending(
        _ bookmark: [String: Any],
        to parentUUID: String,
        in node: [String: Any]
    ) throws -> [String: Any] {
        var result = node
        guard let identifier = node["WebBookmarkUUID"] as? String else {
            throw SafariPlistFeasibilityError.plistInvalid
        }
        if identifier == parentUUID {
            guard var children = node["Children"] as? [[String: Any]] else {
                throw SafariPlistFeasibilityError.mutationTargetInvalid
            }
            children.append(bookmark)
            result["Children"] = children
            return result
        }
        if let children = node["Children"] as? [[String: Any]] {
            result["Children"] = try children.map { try appending(bookmark, to: parentUUID, in: $0) }
        }
        return result
    }

    private static func subtreeDigest(_ node: [String: Any]) throws -> String {
        digest(Data(try canonicalRepresentation(node).utf8))
    }

    private static func nodeTypeCounts(
        _ identifiers: Set<String>,
        nodes: [String: [String: Any]]
    ) -> [String: Int] {
        identifiers.reduce(into: [:]) { counts, identifier in
            let type = nodes[identifier]?["WebBookmarkType"] as? String ?? "missingType"
            counts[type, default: 0] += 1
        }
    }

    private static func analyzeVolatileReplacement(
        missing: Set<String>,
        unexpected: Set<String>,
        beforeNodes: [String: [String: Any]],
        afterNodes: [String: [String: Any]],
        beforeParents: [String: String?],
        afterParents: [String: String?],
        beforeSnapshot: SafariBookmarksSnapshot,
        afterSnapshot: SafariBookmarksSnapshot,
        fixtureUUID: String
    ) throws -> (allowed: Bool, missingInternal: Int, unexpectedInternal: Int, uuidStrippedEquivalent: Bool) {
        let missingInternal = missing.filter { identifier in
            beforeNodes[identifier].map(isVolatileInternalNode) == true
        }.count
        let unexpectedInternal = unexpected.filter { identifier in
            afterNodes[identifier].map(isVolatileInternalNode) == true
        }.count
        guard !missing.isEmpty, missing.count == unexpected.count else {
            return (false, missingInternal, unexpectedInternal, false)
        }
        let beforeHashes = try missing.map { identifier in
            digest(Data(try canonicalRepresentation(strippingUUIDs(beforeNodes[identifier]!)).utf8))
        }.sorted()
        let afterHashes = try unexpected.map { identifier in
            digest(Data(try canonicalRepresentation(strippingUUIDs(afterNodes[identifier]!)).utf8))
        }.sorted()
        let equivalent = beforeHashes == afterHashes
        let rootProxyEquivalent = try isHiddenRootProxyReplacement(
            missing: missing,
            unexpected: unexpected,
            beforeNodes: beforeNodes,
            afterNodes: afterNodes,
            beforeParents: beforeParents,
            afterParents: afterParents,
            beforeSnapshot: beforeSnapshot,
            afterSnapshot: afterSnapshot,
            fixtureUUID: fixtureUUID
        )
        return (
            missingInternal == missing.count && unexpectedInternal == unexpected.count && equivalent || rootProxyEquivalent,
            rootProxyEquivalent ? missing.count : missingInternal,
            rootProxyEquivalent ? unexpected.count : unexpectedInternal,
            equivalent || rootProxyEquivalent
        )
    }

    private static func isHiddenRootProxyReplacement(
        missing: Set<String>,
        unexpected: Set<String>,
        beforeNodes: [String: [String: Any]],
        afterNodes: [String: [String: Any]],
        beforeParents: [String: String?],
        afterParents: [String: String?],
        beforeSnapshot: SafariBookmarksSnapshot,
        afterSnapshot: SafariBookmarksSnapshot,
        fixtureUUID: String
    ) throws -> Bool {
        guard missing.count == 2, unexpected.count == 2,
              let oldRootID = missing.first(where: { beforeNodes[$0]?["WebBookmarkType"] as? String == "WebBookmarkTypeList" }),
              let newRootID = unexpected.first(where: { afterNodes[$0]?["WebBookmarkType"] as? String == "WebBookmarkTypeList" }),
              let oldProxyID = missing.first(where: { beforeNodes[$0]?["WebBookmarkType"] as? String == "WebBookmarkTypeProxy" }),
              let newProxyID = unexpected.first(where: { afterNodes[$0]?["WebBookmarkType"] as? String == "WebBookmarkTypeProxy" }),
              let oldRoot = beforeNodes[oldRootID], let newRoot = afterNodes[newRootID],
              let oldProxy = beforeNodes[oldProxyID], let newProxy = afterNodes[newProxyID],
              (beforeParents[oldRootID] ?? nil) == nil, (afterParents[newRootID] ?? nil) == nil,
              (beforeParents[oldProxyID] ?? nil) == oldRootID,
              (afterParents[newProxyID] ?? nil) == newRootID,
              beforeSnapshot.bookmarks.contains(where: { $0.id == SafariOpaqueID.folder(uuid: oldRootID) }) == false,
              afterSnapshot.bookmarks.contains(where: { $0.id == SafariOpaqueID.folder(uuid: newRootID) }) == false else {
            return false
        }
        let replacements = [newRootID: oldRootID, newProxyID: oldProxyID]
        return try canonicalRepresentation(normalizingRootReplacement(oldRoot, replacements: [:])) ==
            canonicalRepresentation(normalizingRootReplacement(
                removingNode(uuid: fixtureUUID, from: newRoot), replacements: replacements
            )) &&
            canonicalRepresentation(normalizingReplacement(oldProxy, replacements: [:])) ==
            canonicalRepresentation(normalizingReplacement(newProxy, replacements: replacements))
    }

    private static func normalizingRootReplacement(
        _ node: [String: Any],
        replacements: [String: String]
    ) -> Any {
        var result = node
        result.removeValue(forKey: "Sync")
        return normalizingReplacement(result, replacements: replacements)
    }

    private static func removingNode(uuid: String, from node: [String: Any]) -> [String: Any] {
        var result = node
        if let children = node["Children"] as? [[String: Any]] {
            let filtered: [[String: Any]] = children.compactMap { child -> [String: Any]? in
                guard child["WebBookmarkUUID"] as? String != uuid else { return nil }
                return removingNode(uuid: uuid, from: child)
            }
            result["Children"] = filtered
        }
        return result
    }

    private static func normalizingReplacement(_ value: Any, replacements: [String: String]) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = normalizingReplacement(entry.value, replacements: replacements)
            }
        }
        if let array = value as? [Any] {
            return array.map { normalizingReplacement($0, replacements: replacements) }
        }
        if let string = value as? String { return replacements[string] ?? string }
        return value
    }

    private static func isVolatileInternalNode(_ node: [String: Any]) -> Bool {
        if node["WebBookmarkType"] as? String == "WebBookmarkTypeProxy" { return true }
        return node["WebBookmarkType"] as? String == "WebBookmarkTypeList" &&
            node["Title"] as? String == "com.apple.ReadingList"
    }

    private static func strippingUUIDs(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                guard entry.key != "WebBookmarkUUID" else { return }
                result[entry.key] = strippingUUIDs(entry.value)
            }
        }
        if let array = value as? [Any] { return array.map(strippingUUIDs) }
        return value
    }

    private static func canonicalRepresentation(_ value: Any) throws -> String {
        if let dictionary = value as? [String: Any] {
            let fields = try dictionary.keys.sorted().map { key in
                "\(lengthPrefixed(key))\(try canonicalRepresentation(dictionary[key]!))"
            }.joined()
            return "d\(lengthPrefixed(fields))"
        }
        if let array = value as? [Any] {
            let elements = try array.map(canonicalRepresentation).joined()
            return "a\(lengthPrefixed(elements))"
        }
        if let string = value as? String { return "s\(lengthPrefixed(string))" }
        if let data = value as? Data { return "x\(lengthPrefixed(data.base64EncodedString()))" }
        if let date = value as? Date {
            return "t\(date.timeIntervalSinceReferenceDate.bitPattern)"
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "b1" : "b0" }
            let type = String(cString: number.objCType)
            return "n\(lengthPrefixed(type))\(lengthPrefixed(number.stringValue))"
        }
        throw SafariPlistFeasibilityError.plistInvalid
    }

    private static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    private static func fileState(at url: URL) throws -> SafariPlistFileMetadata {
        var information = stat()
        guard lstat(url.path, &information) == 0,
              (information.st_mode & S_IFMT) == S_IFREG,
              information.st_size >= 0,
              information.st_size <= SystemSafariBookmarksSnapshotReader.maximumBytes else {
            throw SafariPlistFeasibilityError.sourceUnsafe
        }
        return .init(
            mode: UInt16(information.st_mode & 0o7777),
            ownerID: UInt32(information.st_uid),
            groupID: UInt32(information.st_gid),
            extendedAttributeNames: try SafariExtendedAttributes.names(at: url)
        )
    }

    private static func boundedData(at url: URL) throws -> Data {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
        catch { throw SafariPlistFeasibilityError.fileOperationFailed }
        guard data.count <= SystemSafariBookmarksSnapshotReader.maximumBytes else {
            throw SafariPlistFeasibilityError.sourceUnsafe
        }
        return data
    }

    private static func lstatExists(_ path: String) -> Bool {
        var information = stat()
        return lstat(path, &information) == 0
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
