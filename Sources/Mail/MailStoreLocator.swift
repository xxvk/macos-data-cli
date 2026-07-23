import Foundation

public struct MailStoreLocation: Sendable {
    public let version: String
    public let databaseURL: URL
}

public struct MailStoreLocator {
    private let mailRoot: URL
    private let fileManager: FileManager

    public init(
        mailRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.mailRoot = mailRoot
        self.fileManager = fileManager
    }

    public func locate() throws -> MailStoreLocation {
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: mailRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                throw MailStoreError.fullDiskAccessRequired
            }
            throw MailStoreError.mailStoreNotFound
        }

        let versions = children.compactMap { url -> (URL, Int)? in
            guard let number = MailDoctor.mailStoreVersionNumber(url.lastPathComponent) else { return nil }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true ? (url, number) : nil
        }
        guard let selected = versions.max(by: { $0.1 < $1.1 }) else { throw MailStoreError.mailStoreNotFound }
        let databaseURL = selected.0.appendingPathComponent("MailData/Envelope Index")
        guard fileManager.isReadableFile(atPath: databaseURL.path) else { throw MailStoreError.fullDiskAccessRequired }
        return MailStoreLocation(version: selected.0.lastPathComponent, databaseURL: databaseURL)
    }
}
