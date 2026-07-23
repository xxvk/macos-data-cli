import Foundation

public struct EmlxLocation: Equatable, Sendable {
    public let fileURL: URL
    public let cacheState: MailCacheState

    public init(fileURL: URL, cacheState: MailCacheState) {
        self.fileURL = fileURL
        self.cacheState = cacheState
    }
}

public struct EmlxPayload: Equatable, Sendable {
    public let rfc822: Data
    public let cacheState: MailCacheState
}

public struct EmlxPathResolver {
    private let mailStoreURL: URL
    private let fileManager: FileManager

    public init(mailStoreURL: URL, fileManager: FileManager = .default) {
        self.mailStoreURL = mailStoreURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public static func hashDirectoryComponents(rowID: Int64) -> [String] {
        guard rowID > 0 else { return [] }
        var quotient = rowID / 1_000
        var result: [String] = []
        while quotient > 0 {
            result.append(String(quotient % 10))
            quotient /= 10
        }
        return result
    }

    public func resolve(rowID: Int64, mailboxURL: String) throws -> EmlxLocation? {
        guard rowID > 0, let mailbox = parseMailboxURL(mailboxURL) else { return nil }
        var mailboxDirectory = mailStoreURL.appendingPathComponent(mailbox.account, isDirectory: true)
        for segment in mailbox.pathSegments {
            mailboxDirectory.appendPathComponent(segment + ".mbox", isDirectory: true)
        }
        guard isContained(mailboxDirectory), !isSymbolicLink(mailboxDirectory) else { return nil }

        guard let children = try? fileManager.contentsOfDirectory(
            at: mailboxDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for storeDirectory in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard isUUID(storeDirectory.lastPathComponent), isDirectory(storeDirectory),
                  !isSymbolicLink(storeDirectory), isContained(storeDirectory) else { continue }
            var messagesDirectory = storeDirectory.appendingPathComponent("Data", isDirectory: true)
            Self.hashDirectoryComponents(rowID: rowID).forEach {
                messagesDirectory.appendPathComponent($0, isDirectory: true)
            }
            messagesDirectory.appendPathComponent("Messages", isDirectory: true)
            guard isContained(messagesDirectory), !isSymbolicLink(messagesDirectory) else { continue }

            let full = messagesDirectory.appendingPathComponent("\(rowID).emlx")
            if isRegularContainedFile(full) {
                return EmlxLocation(fileURL: full, cacheState: .complete)
            }
            let partial = messagesDirectory.appendingPathComponent("\(rowID).partial.emlx")
            if isRegularContainedFile(partial) {
                return EmlxLocation(fileURL: partial, cacheState: .partial)
            }
        }
        return nil
    }

    private func parseMailboxURL(_ value: String) -> (account: String, pathSegments: [String])? {
        guard let marker = value.range(of: "://") else { return nil }
        let remainder = value[marker.upperBound...]
        guard let slash = remainder.firstIndex(of: "/") else { return nil }
        let account = String(remainder[..<slash]).removingPercentEncoding ?? String(remainder[..<slash])
        let encodedPath = String(remainder[remainder.index(after: slash)...])
        let path = encodedPath.removingPercentEncoding ?? encodedPath
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard isSafePathComponent(account), !segments.isEmpty,
              segments.allSatisfy(isSafePathComponent) else { return nil }
        return (account, segments)
    }

    private func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
            !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    private func isUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func isRegularContainedFile(_ url: URL) -> Bool {
        guard isContained(url), !isSymbolicLink(url) else { return false }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isContained(_ url: URL) -> Bool {
        let root = mailStoreURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return candidate.count >= root.count && Array(candidate.prefix(root.count)) == root
    }
}

public struct EmlxReader: Sendable {
    public static let maximumRFC822Bytes = 64 * 1_024 * 1_024
    public static let readDeadlineMilliseconds: UInt64 = 100
    private static let maximumPrefixBytes = 64

    public init() {}

    public func read(location: EmlxLocation) throws -> EmlxPayload {
        let deadline = DispatchTime.now().uptimeNanoseconds + Self.readDeadlineMilliseconds * 1_000_000
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: location.fileURL)
        } catch {
            throw MailStoreError.contentNotCached
        }
        defer { try? handle.close() }

        let initial: Data
        do {
            initial = try handle.read(upToCount: 4_096) ?? Data()
        } catch {
            throw MailStoreError.contentNotCached
        }
        try checkDeadline(deadline)
        guard let newline = initial.firstIndex(of: 0x0A), newline <= Self.maximumPrefixBytes else {
            throw MailStoreError.emlxMalformed
        }
        let countBytes = initial[..<newline]
        guard let countText = String(data: countBytes, encoding: .ascii),
              let byteCount = Int(countText.trimmingCharacters(in: .whitespacesAndNewlines)),
              byteCount >= 0 else {
            throw MailStoreError.emlxMalformed
        }
        guard byteCount <= Self.maximumRFC822Bytes else { throw MailStoreError.contentTooLarge }

        let messageStart = initial.index(after: newline)
        var message = Data(initial[messageStart...].prefix(byteCount))
        while message.count < byteCount {
            try checkDeadline(deadline)
            let remaining = byteCount - message.count
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: min(64 * 1_024, remaining)) ?? Data()
            } catch {
                throw MailStoreError.emlxMalformed
            }
            guard !chunk.isEmpty else { throw MailStoreError.emlxMalformed }
            message.append(chunk.prefix(remaining))
        }
        try checkDeadline(deadline)
        return EmlxPayload(rfc822: message, cacheState: location.cacheState)
    }

    private func checkDeadline(_ deadline: UInt64) throws {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            throw MailStoreError.contentReadTimedOut
        }
    }
}
