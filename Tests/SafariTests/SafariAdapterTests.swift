import Foundation
import Testing
import Core
@testable import SafariAdapter

@Suite("Safari adapter 0.8")
struct SafariAdapterTests {
    @Test("Parser separates bookmarks and Reading List without exposing proxy nodes")
    func parserSeparatesCollections() throws {
        let snapshot = try SafariBookmarksParser.parse(data: fixtureData())

        #expect(snapshot.bookmarks.count == 2)
        #expect(snapshot.bookmarks.map(\.kind) == [.folder, .bookmark])
        #expect(snapshot.bookmarks[1].title == "Example")
        #expect(snapshot.bookmarks[1].url == "https://example.com/bookmark")
        #expect(snapshot.bookmarks[1].parentID == snapshot.bookmarks[0].id)
        #expect(snapshot.readingList.count == 2)
        #expect(snapshot.readingList[0].isRead == false)
        #expect(snapshot.readingList[1].isRead == true)
        #expect(snapshot.readingList[1].previewText == "Preview")
        #expect(snapshot.bookmarks.allSatisfy { !$0.id.contains("BOOKMARK-UUID") })
    }

    @Test("Duplicate Reading List containers fail closed")
    func duplicateReadingListFailsClosed() throws {
        var root = fixtureRoot()
        var children = root["Children"] as! [[String: Any]]
        children.append(readingListNode(uuid: "READING-LIST-SECOND"))
        root["Children"] = children
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)

        #expect(throws: SafariError.schemaUnsupported) {
            try SafariBookmarksParser.parse(data: data)
        }
    }

    @Test("Bookmark and Reading List queries use AND filters and stable pagination")
    func queriesAndPagination() throws {
        let reader = QueueSnapshotReader([try SafariBookmarksParser.parse(data: fixtureData())])
        let store = SafariStore(reader: reader, mutationBridge: RecordingMutationBridge(), permission: allowedPermission())

        let bookmarks = try store.bookmarks(query: .init(text: "exam", url: "https://example.com/bookmark", folderID: nil), limit: 1, cursor: nil)
        #expect(bookmarks.items.count == 1)
        #expect(bookmarks.items[0].kind == .bookmark)

        let unread = try store.readingList(query: .init(text: "Unread", url: nil, read: false), limit: 50, cursor: nil)
        #expect(unread.items.count == 1)
        #expect(unread.items[0].isRead == false)
    }

    @Test("Strict add input rejects unknown fields and unsafe URLs")
    func strictAddInput() throws {
        #expect(throws: SafariError.invalidInput) {
            try SafariReadingListAddInput.decode(Data(#"{"url":"https://example.com","unknown":true}"#.utf8))
        }
        #expect(throws: SafariError.invalidInput) {
            try SafariReadingListAddInput.decode(Data(#"{"url":"file:///tmp/private"}"#.utf8))
        }
        let input = try SafariReadingListAddInput.decode(Data(#"{"url":"https://example.com/article","title":"Title","previewText":"Preview"}"#.utf8))
        #expect(input.url.absoluteString == "https://example.com/article")
    }

    @Test("Malformed plist and stale folders fail closed")
    func malformedAndStaleFolderFailClosed() throws {
        #expect(throws: SafariError.schemaUnsupported) {
            try SafariBookmarksParser.parse(data: Data("not-a-plist".utf8))
        }
        let snapshot = try SafariBookmarksParser.parse(data: fixtureData())
        let store = SafariStore(reader: QueueSnapshotReader([snapshot]), mutationBridge: RecordingMutationBridge(), permission: allowedPermission())
        #expect(throws: SafariError.notFound) {
            try store.bookmarks(
                query: .init(folderID: "safarifolder_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
                limit: 50,
                cursor: nil
            )
        }
    }

    @Test("Cursors are bound to the exact plist snapshot")
    func staleCursorFailsAfterSnapshotChange() throws {
        let before = try SafariBookmarksParser.parse(data: fixtureData())
        let after = try SafariBookmarksParser.parse(data: fixtureData(extraReadingURL: "https://example.com/changed"))
        let store = SafariStore(reader: QueueSnapshotReader([before, after]), mutationBridge: RecordingMutationBridge(), permission: allowedPermission())
        let first = try store.bookmarks(limit: 1, cursor: nil)
        #expect(first.nextCursor != nil)
        #expect(throws: PaginationError.invalidCursor) {
            try store.bookmarks(limit: 1, cursor: first.nextCursor)
        }
    }

    @Test("URL normalization makes retry with fragment a safe no-op")
    func normalizedURLNoop() throws {
        let snapshot = try SafariBookmarksParser.parse(data: fixtureData())
        let bridge = RecordingMutationBridge()
        let store = SafariStore(reader: QueueSnapshotReader([snapshot]), mutationBridge: bridge, permission: allowedPermission())
        let input = try SafariReadingListAddInput.decode(Data(#"{"url":"https://EXAMPLE.com:443/unread#section"}"#.utf8))
        let result = try store.addReadingList(input, apply: true)
        #expect(result.operation == "already_exists")
        #expect(bridge.callCount == 0)
    }

    @Test("Permission result keeps file access and Automation separate")
    func permissionSeparation() {
        let service = SafariPermissionService(fileProbe: { true }, automationProbe: FixedAutomationProbe(.requiresConsent))
        let result = service.check(requestConsent: false)
        #expect(result.bookmarksReadable == true)
        #expect(result.readingListAddAvailable == false)
        #expect(result.requested == false)
    }

    @Test("Dry-run and existing URL never invoke the mutation bridge")
    func dryRunAndNoopDoNotMutate() throws {
        let snapshot = try SafariBookmarksParser.parse(data: fixtureData())
        let bridge = RecordingMutationBridge()
        let store = SafariStore(reader: QueueSnapshotReader([snapshot, snapshot]), mutationBridge: bridge, permission: allowedPermission())
        let fresh = try SafariReadingListAddInput.decode(Data(#"{"url":"https://example.com/new"}"#.utf8))
        let preview = try store.addReadingList(fresh, apply: false)
        #expect(preview.verification == .notApplied)
        #expect(bridge.callCount == 0)

        let existing = try SafariReadingListAddInput.decode(Data(#"{"url":"https://example.com/unread"}"#.utf8))
        let noOp = try store.addReadingList(existing, apply: true)
        #expect(noOp.operation == "already_exists")
        #expect(noOp.changed == false)
        #expect(bridge.callCount == 0)
    }

    @Test("Apply distinguishes confirmed read-back, pending, and unknown outcome")
    func applyVerificationStates() throws {
        let before = try SafariBookmarksParser.parse(data: fixtureData())
        let after = try SafariBookmarksParser.parse(data: fixtureData(extraReadingURL: "https://example.com/new"))
        let input = try SafariReadingListAddInput.decode(Data(#"{"url":"https://example.com/new"}"#.utf8))

        let confirmedBridge = RecordingMutationBridge()
        let confirmed = try SafariStore(reader: QueueSnapshotReader([before, after]), mutationBridge: confirmedBridge, permission: allowedPermission()).addReadingList(input, apply: true)
        #expect(confirmed.verification == .readbackConfirmed)
        #expect(confirmed.itemID != nil)
        #expect(confirmedBridge.callCount == 1)

        let pending = try SafariStore(reader: QueueSnapshotReader([before, before]), mutationBridge: RecordingMutationBridge(), permission: allowedPermission()).addReadingList(input, apply: true)
        #expect(pending.verification == .saveAcceptedReadbackPending)
        #expect(pending.nextAction != nil)

        let failedReadback = try SafariStore(
            reader: FailingReadbackSnapshotReader(before: before),
            mutationBridge: RecordingMutationBridge(),
            permission: allowedPermission()
        ).addReadingList(input, apply: true)
        #expect(failedReadback.verification == .saveAcceptedReadbackPending)
        #expect(failedReadback.nextAction != nil)

        let timeoutBridge = RecordingMutationBridge(error: .timedOut)
        #expect(throws: SafariError.writeOutcomeUnknown) {
            try SafariStore(reader: QueueSnapshotReader([before]), mutationBridge: timeoutBridge, permission: allowedPermission()).addReadingList(input, apply: true)
        }
    }

    @Test("Generated AppleScript escapes data and keeps a bounded timeout")
    func appleScriptEscaping() {
        let source = SystemSafariReadingListMutationBridge.script(
            url: "https://example.com/a?x=\\\"",
            title: "A \"title\"",
            previewText: "line\\value"
        )
        #expect(source.contains("with timeout of 5 seconds"))
        #expect(source.contains(#"A \"title\""#))
        #expect(source.contains(#"line\\value"#))
    }

    private func allowedPermission() -> SafariPermissionService {
        SafariPermissionService(fileProbe: { true }, automationProbe: FixedAutomationProbe(.available))
    }

    private func fixtureData(extraReadingURL: String? = nil) throws -> Data {
        var root = fixtureRoot(extraReadingURL: extraReadingURL)
        root["WebBookmarkFileVersion"] = 1
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private func fixtureRoot(extraReadingURL: String? = nil) -> [String: Any] {
        let bookmark: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": "BOOKMARK-UUID",
            "URLString": "https://example.com/bookmark",
            "URIDictionary": ["title": "Example"],
            "dateAdded": Date(timeIntervalSince1970: 100)
        ]
        let folder: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkUUID": "FOLDER-UUID",
            "Title": "Folder",
            "Children": [bookmark]
        ]
        let proxy: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeProxy",
            "WebBookmarkUUID": "PROXY-UUID",
            "Title": "History"
        ]
        return [
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkUUID": "ROOT-UUID",
            "Title": "Bookmarks",
            "Children": [proxy, folder, readingListNode(uuid: "READING-LIST-UUID", extraURL: extraReadingURL)]
        ]
    }

    private func readingListNode(uuid: String, extraURL: String? = nil) -> [String: Any] {
        var items: [[String: Any]] = [
            [
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "WebBookmarkUUID": "READING-UNREAD-UUID",
                "URLString": "https://example.com/unread",
                "URIDictionary": ["title": "Unread article"],
                "ReadingList": ["DateAdded": Date(timeIntervalSince1970: 200)]
            ],
            [
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "WebBookmarkUUID": "READING-READ-UUID",
                "URLString": "https://example.com/read",
                "URIDictionary": ["title": "Read article"],
                "ReadingList": ["DateAdded": Date(timeIntervalSince1970: 300), "DateLastViewed": Date(timeIntervalSince1970: 400), "PreviewText": "Preview"]
            ]
        ]
        if let extraURL {
            items.append([
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "WebBookmarkUUID": "READING-NEW-UUID",
                "URLString": extraURL,
                "URIDictionary": ["title": "New article"],
                "ReadingList": ["DateAdded": Date(timeIntervalSince1970: 500)]
            ])
        }
        return [
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkUUID": uuid,
            "Title": "com.apple.ReadingList",
            "Children": items
        ]
    }
}

private final class QueueSnapshotReader: SafariBookmarksSnapshotReading, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [SafariBookmarksSnapshot]
    init(_ snapshots: [SafariBookmarksSnapshot]) { self.snapshots = snapshots }
    func snapshot() throws -> SafariBookmarksSnapshot {
        lock.lock(); defer { lock.unlock() }
        guard !snapshots.isEmpty else { throw SafariError.readFailed }
        if snapshots.count == 1 { return snapshots[0] }
        return snapshots.removeFirst()
    }
}

private final class RecordingMutationBridge: SafariReadingListMutationBridging, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var callCount = 0
    let error: SafariReadingListBridgeError?
    init(error: SafariReadingListBridgeError? = nil) { self.error = error }
    func add(url: URL, title: String?, previewText: String?) throws {
        lock.lock(); callCount += 1; lock.unlock()
        if let error { throw error }
    }
}

private final class FailingReadbackSnapshotReader: SafariBookmarksSnapshotReading, @unchecked Sendable {
    private let lock = NSLock()
    private let before: SafariBookmarksSnapshot
    private var calls = 0

    init(before: SafariBookmarksSnapshot) { self.before = before }

    func snapshot() throws -> SafariBookmarksSnapshot {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        if calls == 1 { return before }
        throw SafariError.readFailed
    }
}

private struct FixedAutomationProbe: SafariAutomationProbing {
    let value: SafariAutomationStatus
    init(_ value: SafariAutomationStatus) { self.value = value }
    func status(requestConsent: Bool) -> SafariAutomationStatus { value }
}
