import CryptoKit
import Foundation

enum SafariLocalMutationError: Error, Equatable {
    case invalidInput
    case invalidIdentifier
    case duplicateIdentifier
    case targetNotFound
    case typeMismatch
    case invalidParent
    case invalidIndex
    case rootMutation
    case protectedCollection
    case folderNotEmpty
    case cycle
    case schemaUnsupported
    case preservationFailed
}

enum SafariLocalMutationOperation: Equatable {
    case createBookmark(parentID: String, index: Int, uuid: String, title: String, url: String)
    case updateBookmark(id: String, title: String, url: String)
    case createFolder(parentID: String, index: Int, uuid: String, title: String)
    case renameFolder(id: String, title: String)
    case moveBookmark(id: String, parentID: String, index: Int)
    case deleteBookmark(id: String)
    case moveFolder(id: String, parentID: String, index: Int)
    case deleteFolder(id: String)
}

struct SafariLocalMutationEngine {
    private struct TreeIndex {
        var nodes: [String: [String: Any]] = [:]
        var parents: [String: String?] = [:]
    }

    func prepare(data: Data, operation: SafariLocalMutationOperation) throws -> SafariPlistMutationSimulationReport {
        let parsed = try parse(data)
        let before = try index(parsed.root)
        let rootUUID = try identifier(parsed.root)
        var affected = Set<String>()
        var root = parsed.root

        switch operation {
        case let .createBookmark(parentID, childIndex, uuid, title, rawURL):
            try validateTitle(title)
            let url = try validateURL(rawURL)
            try validateNewIdentifier(uuid, index: before)
            let parentUUID = try resolve(parentID, kind: .folder, index: before, rootUUID: rootUUID)
            try validateWritableFolder(parentUUID, index: before)
            affected.formUnion(try ancestors(of: parentUUID, index: before))
            let node: [String: Any] = [
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "WebBookmarkUUID": uuid,
                "URLString": url,
                "URIDictionary": ["title": title]
            ]
            root = try inserting(node, into: parentUUID, at: childIndex, node: root)

        case let .updateBookmark(id, title, rawURL):
            try validateTitle(title)
            let url = try validateURL(rawURL)
            let uuid = try resolve(id, kind: .bookmark, index: before, rootUUID: rootUUID)
            affected.formUnion(try ancestors(of: uuid, index: before))
            root = try replacing(uuid: uuid, node: root) { node in
                var result = node
                result["URLString"] = url
                var uri = result["URIDictionary"] as? [String: Any] ?? [:]
                uri["title"] = title
                result["URIDictionary"] = uri
                if result["Title"] != nil { result["Title"] = title }
                return result
            }

        case let .createFolder(parentID, childIndex, uuid, title):
            try validateTitle(title)
            try validateNewIdentifier(uuid, index: before)
            let parentUUID = try resolve(parentID, kind: .folder, index: before, rootUUID: rootUUID)
            try validateWritableFolder(parentUUID, index: before)
            affected.formUnion(try ancestors(of: parentUUID, index: before))
            let node: [String: Any] = [
                "WebBookmarkType": "WebBookmarkTypeList",
                "WebBookmarkUUID": uuid,
                "Title": title,
                "Children": [[String: Any]]()
            ]
            root = try inserting(node, into: parentUUID, at: childIndex, node: root)

        case let .renameFolder(id, title):
            try validateTitle(title)
            let uuid = try resolve(id, kind: .folder, index: before, rootUUID: rootUUID)
            try validateWritableFolder(uuid, index: before)
            affected.formUnion(try ancestors(of: uuid, index: before))
            root = try replacing(uuid: uuid, node: root) { node in
                var result = node
                result["Title"] = title
                return result
            }

        case let .moveBookmark(id, parentID, childIndex), let .moveFolder(id, parentID, childIndex):
            let expectedKind: Kind = {
                if case .moveBookmark = operation { return .bookmark }
                return .folder
            }()
            let uuid = try resolve(id, kind: expectedKind, index: before, rootUUID: rootUUID)
            let parentUUID = try resolve(parentID, kind: .folder, index: before, rootUUID: rootUUID)
            try validateWritableFolder(parentUUID, index: before)
            if try ancestors(of: parentUUID, index: before).contains(uuid) { throw SafariLocalMutationError.cycle }
            guard let moving = before.nodes[uuid] else { throw SafariLocalMutationError.targetNotFound }
            affected.formUnion(try ancestors(of: uuid, index: before))
            affected.formUnion(try ancestors(of: parentUUID, index: before))
            root = removing(uuid: uuid, node: root)
            root = try inserting(moving, into: parentUUID, at: childIndex, node: root)

        case let .deleteBookmark(id), let .deleteFolder(id):
            let expectedKind: Kind = {
                if case .deleteBookmark = operation { return .bookmark }
                return .folder
            }()
            let uuid = try resolve(id, kind: expectedKind, index: before, rootUUID: rootUUID)
            guard let target = before.nodes[uuid] else { throw SafariLocalMutationError.targetNotFound }
            if target["WebBookmarkType"] as? String == "WebBookmarkTypeList",
               let children = target["Children"] as? [[String: Any]], !children.isEmpty {
                throw SafariLocalMutationError.folderNotEmpty
            }
            try validateNotProtected(uuid, index: before)
            affected.formUnion(try ancestors(of: uuid, index: before))
            root = removing(uuid: uuid, node: root)
        }

        let semanticallyChanged = !NSDictionary(dictionary: parsed.root).isEqual(to: root)
        let output = semanticallyChanged ? try serialize(root, format: parsed.format) : data
        _ = try SafariBookmarksParser.parse(data: output)
        let after = try index(root)
        let untouched = Set(before.nodes.keys).subtracting(affected)
        guard untouched.allSatisfy({ raw in
            guard let lhs = before.nodes[raw], let rhs = after.nodes[raw] else { return false }
            return NSDictionary(dictionary: lhs).isEqual(to: rhs)
        }) else { throw SafariLocalMutationError.preservationFailed }

        return .init(
            sourceSHA256: digest(data),
            outputData: output,
            existingNodeCount: before.nodes.count,
            untouchedNodeCount: untouched.count,
            changedAncestorCount: affected.count,
            addedNodeCount: after.nodes.count - before.nodes.count,
            untouchedSubtreeHashesPreserved: true
        )
    }

    private enum Kind { case bookmark, folder }

    private func parse(_ data: Data) throws -> (root: [String: Any], format: PropertyListSerialization.PropertyListFormat) {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard data.count <= SystemSafariBookmarksSnapshotReader.maximumBytes,
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
              let root = value as? [String: Any],
              root["WebBookmarkType"] as? String == "WebBookmarkTypeList",
              root["Children"] is [[String: Any]] else { throw SafariLocalMutationError.schemaUnsupported }
        _ = try SafariBookmarksParser.parse(data: data)
        return (root, format)
    }

    private func index(_ root: [String: Any]) throws -> TreeIndex {
        var result = TreeIndex()
        try collect(root, parent: nil, result: &result)
        return result
    }

    private func collect(_ node: [String: Any], parent: String?, result: inout TreeIndex) throws {
        let uuid = try identifier(node)
        guard result.nodes[uuid] == nil else { throw SafariLocalMutationError.duplicateIdentifier }
        result.nodes[uuid] = node
        result.parents[uuid] = parent
        if let children = node["Children"] {
            guard node["WebBookmarkType"] as? String == "WebBookmarkTypeList",
                  let values = children as? [[String: Any]] else { throw SafariLocalMutationError.schemaUnsupported }
            for child in values { try collect(child, parent: uuid, result: &result) }
        }
    }

    private func identifier(_ node: [String: Any]) throws -> String {
        guard let uuid = node["WebBookmarkUUID"] as? String, !uuid.isEmpty else {
            throw SafariLocalMutationError.schemaUnsupported
        }
        return uuid
    }

    private func resolve(_ opaque: String, kind: Kind, index: TreeIndex, rootUUID: String) throws -> String {
        let matches = index.nodes.compactMap { uuid, node -> String? in
            let type = node["WebBookmarkType"] as? String
            let expected = kind == .folder ? SafariOpaqueID.folder(uuid: uuid) : SafariOpaqueID.bookmark(uuid: uuid)
            return expected == opaque && ((kind == .folder && type == "WebBookmarkTypeList") || (kind == .bookmark && type == "WebBookmarkTypeLeaf")) ? uuid : nil
        }
        guard matches.count == 1 else { throw SafariLocalMutationError.invalidIdentifier }
        if matches[0] == rootUUID { throw SafariLocalMutationError.rootMutation }
        return matches[0]
    }

    private func validateNewIdentifier(_ uuid: String, index: TreeIndex) throws {
        guard !uuid.isEmpty, uuid.utf8.count <= 256 else { throw SafariLocalMutationError.invalidInput }
        guard index.nodes[uuid] == nil else { throw SafariLocalMutationError.duplicateIdentifier }
    }

    private func validateTitle(_ title: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 500 else { throw SafariLocalMutationError.invalidInput }
    }

    private func validateURL(_ raw: String) throws -> String {
        guard raw.utf8.count <= 4_096, let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else {
            throw SafariLocalMutationError.invalidInput
        }
        return url.absoluteString
    }

    private func validateWritableFolder(_ uuid: String, index: TreeIndex) throws {
        guard let node = index.nodes[uuid], node["WebBookmarkType"] as? String == "WebBookmarkTypeList" else {
            throw SafariLocalMutationError.invalidParent
        }
        try validateNotProtected(uuid, index: index)
    }

    private func validateNotProtected(_ uuid: String, index: TreeIndex) throws {
        guard let node = index.nodes[uuid] else { throw SafariLocalMutationError.targetNotFound }
        if node["Title"] as? String == "com.apple.ReadingList" || node["WebBookmarkType"] as? String == "WebBookmarkTypeProxy" {
            throw SafariLocalMutationError.protectedCollection
        }
    }

    private func ancestors(of uuid: String, index: TreeIndex) throws -> Set<String> {
        var result = Set<String>()
        var current: String? = uuid
        while let value = current {
            guard result.insert(value).inserted else { throw SafariLocalMutationError.schemaUnsupported }
            current = index.parents[value] ?? nil
        }
        return result
    }

    private func inserting(_ value: [String: Any], into parent: String, at index: Int, node: [String: Any]) throws -> [String: Any] {
        var result = node
        if try identifier(node) == parent {
            guard node["WebBookmarkType"] as? String == "WebBookmarkTypeList" else {
                throw SafariLocalMutationError.invalidParent
            }
            var children = node["Children"] as? [[String: Any]] ?? []
            guard index >= 0, index <= children.count else {
                throw SafariLocalMutationError.invalidIndex
            }
            children.insert(value, at: index)
            result["Children"] = children
            return result
        }
        if let children = node["Children"] as? [[String: Any]] {
            result["Children"] = try children.map { try inserting(value, into: parent, at: index, node: $0) }
        }
        return result
    }

    private func replacing(uuid: String, node: [String: Any], transform: ([String: Any]) -> [String: Any]) throws -> [String: Any] {
        if try identifier(node) == uuid { return transform(node) }
        var result = node
        if let children = node["Children"] as? [[String: Any]] {
            result["Children"] = try children.map { try replacing(uuid: uuid, node: $0, transform: transform) }
        }
        return result
    }

    private func removing(uuid: String, node: [String: Any]) -> [String: Any] {
        var result = node
        if let children = node["Children"] as? [[String: Any]] {
            result["Children"] = children.filter { ($0["WebBookmarkUUID"] as? String) != uuid }
                .map { removing(uuid: uuid, node: $0) }
        }
        return result
    }

    private func serialize(_ root: [String: Any], format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        do { return try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0) }
        catch { throw SafariLocalMutationError.schemaUnsupported }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
