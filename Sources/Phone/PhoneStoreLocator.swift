import Foundation

public struct PhoneStoreLocation: Sendable {
    public let databaseURL: URL
}

/// Resolves the local Call History Core Data SQLite store
/// (`~/Library/Application Support/CallHistoryDB/CallHistory.storedata`).
/// The store is a single file in WAL mode, not versioned like Mail's `V*`
/// directories.
public struct PhoneStoreLocator {
    private let databaseURL: URL
    private let fileManager: FileManager

    public init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CallHistoryDB/CallHistory.storedata", isDirectory: false),
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    public func locate() throws -> PhoneStoreLocation {
        let values = try? databaseURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
        if values?.isSymbolicLink == true {
            throw PhoneCallsError.storeNotFound
        }
        if let size = values?.fileSize, size > 512 * 1024 * 1024 {
            throw PhoneCallsError.storeNotFound
        }
        guard fileManager.isReadableFile(atPath: databaseURL.path) else {
            throw PhoneCallsError.fullDiskAccessRequired
        }
        return PhoneStoreLocation(databaseURL: databaseURL)
    }
}
