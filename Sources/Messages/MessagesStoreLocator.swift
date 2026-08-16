import Foundation

public struct MessagesStoreLocation: Sendable {
    public let databaseURL: URL
}

/// Resolves the local Messages SQLite store (`~/Library/Messages/chat.db`).
/// The store is a single file, not versioned like Mail's `V*` directories.
public struct MessagesStoreLocator {
    private let databaseURL: URL
    private let fileManager: FileManager

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db", isDirectory: false),
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    public func locate() throws -> MessagesStoreLocation {
        let values = try? databaseURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        if values?.isSymbolicLink == true {
            throw MessagesError.storeNotFound
        }
        if let size = values?.fileSize, size > 512 * 1024 * 1024 {
            throw MessagesError.storeNotFound
        }
        guard fileManager.isReadableFile(atPath: databaseURL.path) else {
            throw MessagesError.fullDiskAccessRequired
        }
        return MessagesStoreLocation(databaseURL: databaseURL)
    }
}
