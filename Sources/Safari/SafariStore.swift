import Core
import CryptoKit
import Foundation

public struct SafariStore: Sendable {
    private let reader: any SafariBookmarksSnapshotReading
    private let mutationBridge: any SafariReadingListMutationBridging
    private let permission: SafariPermissionService

    public init() {
        self.reader = SystemSafariBookmarksSnapshotReader()
        self.mutationBridge = SystemSafariReadingListMutationBridge()
        self.permission = SafariPermissionService()
    }

    init(reader: any SafariBookmarksSnapshotReading, mutationBridge: any SafariReadingListMutationBridging, permission: SafariPermissionService) {
        self.reader = reader
        self.mutationBridge = mutationBridge
        self.permission = permission
    }

    public func bookmarks(query: SafariBookmarkQuery = .init(), limit: Int, cursor: String?) throws -> PagedResult<SafariBookmarkPayload> {
        guard (1...Pagination.maximumLimit).contains(limit) else { throw PaginationError.invalidLimit }
        if let folderID = query.folderID,
           !(folderID.hasPrefix("safarifolder_") && SafariOpaqueID.isBookmarkOrFolder(folderID)) {
            throw SafariError.invalidIdentifier
        }
        let snapshot = try reader.snapshot()
        if let folderID = query.folderID,
           !snapshot.bookmarks.contains(where: { $0.id == folderID && $0.kind == .folder }) {
            throw SafariError.notFound
        }
        let values = snapshot.bookmarks.filter { item in
            matches(text: query.text, title: item.title, url: item.url)
                && matchesURL(query.url, candidate: item.url)
                && (query.folderID == nil || item.parentID == query.folderID)
        }
        let scope = "\(query.text ?? "*")|\(query.url ?? "*")|\(query.folderID ?? "*")"
        return try Pagination.page(items: values, limit: limit, cursor: cursor, prefix: "safaribookmarkpage_\(shortDigest(scope))_\(snapshot.fingerprint.prefix(16))_")
    }

    public func bookmark(id: String) throws -> SafariBookmarkPayload {
        guard SafariOpaqueID.isBookmarkOrFolder(id) else { throw SafariError.invalidIdentifier }
        guard let value = try reader.snapshot().bookmarks.first(where: { $0.id == id }) else { throw SafariError.notFound }
        return value
    }

    public func readingList(query: SafariReadingListQuery = .init(), limit: Int, cursor: String?) throws -> PagedResult<SafariReadingListItemPayload> {
        guard (1...Pagination.maximumLimit).contains(limit) else { throw PaginationError.invalidLimit }
        let snapshot = try reader.snapshot()
        let values = snapshot.readingList.filter { item in
            matches(text: query.text, title: item.title, url: item.url)
                && matchesURL(query.url, candidate: item.url)
                && (query.read == nil || item.isRead == query.read)
        }
        let scope = "\(query.text ?? "*")|\(query.url ?? "*")|\(query.read.map(String.init) ?? "*")"
        return try Pagination.page(items: values, limit: limit, cursor: cursor, prefix: "safarireadingpage_\(shortDigest(scope))_\(snapshot.fingerprint.prefix(16))_")
    }

    public func readingListItem(id: String) throws -> SafariReadingListItemPayload {
        guard SafariOpaqueID.isReadingList(id) else { throw SafariError.invalidIdentifier }
        guard let value = try reader.snapshot().readingList.first(where: { $0.id == id }) else { throw SafariError.notFound }
        return value
    }

    public func addReadingList(_ input: SafariReadingListAddInput, apply: Bool) throws -> SafariReadingListAddResult {
        let before = try reader.snapshot()
        let normalized = Self.normalizedURL(input.url)
        let urlSHA256 = fullDigest(normalized)
        if let existing = before.readingList.first(where: { candidate in
            guard let url = URL(string: candidate.url) else { return false }
            return Self.normalizedURL(url) == normalized
        }) {
            return .init(operation: "already_exists", dryRun: !apply, changed: false, urlSHA256: urlSHA256, itemID: existing.id, verification: apply ? .readbackConfirmed : .notApplied, nextAction: nil)
        }
        guard apply else {
            return .init(operation: "add_preview", dryRun: true, changed: true, urlSHA256: urlSHA256, itemID: nil, verification: .notApplied, nextAction: nil)
        }
        try requireAutomation()
        do { try mutationBridge.add(url: input.url, title: input.title, previewText: input.previewText) }
        catch SafariReadingListBridgeError.automationDenied { throw SafariError.permissionDenied }
        catch SafariReadingListBridgeError.targetUnavailable { throw SafariError.targetUnavailable }
        catch SafariReadingListBridgeError.timedOut { throw SafariError.writeOutcomeUnknown }
        catch { throw SafariError.addFailed }

        let after: SafariBookmarksSnapshot
        do {
            after = try reader.snapshot()
        } catch {
            return pendingReadbackResult(urlSHA256: urlSHA256)
        }
        if let item = after.readingList.first(where: { candidate in
            guard let url = URL(string: candidate.url) else { return false }
            return Self.normalizedURL(url) == normalized
        }) {
            return .init(operation: "added", dryRun: false, changed: true, urlSHA256: urlSHA256, itemID: item.id, verification: .readbackConfirmed, nextAction: nil)
        }
        return pendingReadbackResult(urlSHA256: urlSHA256)
    }

    public func mutateLocally(
        _ input: SafariLocalMutationInput,
        apply: Bool,
        confirmation: String? = nil
    ) throws -> SafariLocalMutationResult {
        do {
            return try SafariLocalMutationService().execute(input, apply: apply, confirmation: confirmation)
        } catch let error as SafariError {
            throw error
        } catch let error as SafariLocalMutationError {
            switch error {
            case .invalidInput: throw SafariError.invalidInput
            case .invalidIdentifier, .targetNotFound: throw SafariError.invalidIdentifier
            case .folderNotEmpty, .cycle, .rootMutation, .protectedCollection,
                 .typeMismatch, .invalidParent, .invalidIndex, .duplicateIdentifier:
                throw SafariError.localMutationUnsafe
            case .schemaUnsupported, .preservationFailed: throw SafariError.schemaUnsupported
            }
        }
    }

    private func pendingReadbackResult(urlSHA256: String) -> SafariReadingListAddResult {
        .init(
            operation: "add_accepted",
            dryRun: false,
            changed: true,
            urlSHA256: urlSHA256,
            itemID: nil,
            verification: .saveAcceptedReadbackPending,
            nextAction: "Do not retry automatically. Query Reading List using the original URL after Safari finishes saving."
        )
    }

    private func requireAutomation() throws {
        switch permission.check().automation {
        case .available: return
        case .requiresConsent, .targetNotRunning: throw SafariError.permissionRequired
        case .denied: throw SafariError.permissionDenied
        case .targetUnavailable: throw SafariError.targetUnavailable
        case .unknown: throw SafariError.automationUnknown
        }
    }

    private func matches(text: String?, title: String, url: String?) -> Bool {
        guard let text, !text.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(text) || (url?.localizedCaseInsensitiveContains(text) ?? false)
    }

    private func matchesURL(_ expected: String?, candidate: String?) -> Bool {
        guard let expected else { return true }
        guard let expectedURL = URL(string: expected), let candidate, let candidateURL = URL(string: candidate) else { return false }
        return Self.normalizedURL(expectedURL) == Self.normalizedURL(candidateURL)
    }

    static func normalizedURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) { components.port = nil }
        return components.string ?? url.absoluteString
    }

    private func shortDigest(_ value: String) -> String { String(fullDigest(value).prefix(16)) }
    private func fullDigest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}
