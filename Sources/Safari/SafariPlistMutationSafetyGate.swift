import AppKit
import CryptoKit
import Darwin
import Foundation

enum SafariPlistMutationGateError: Error, Equatable {
    case safariRunning
    case plistInUse
    case processProbeFailed
    case sourceUnsafe
    case sourceUnstable
    case recoveryDirectoryUnsafe
    case recoveryWriteFailed
}

struct SafariPlistMutationFileSnapshot: Equatable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let mode: UInt16
    let ownerID: UInt32
    let groupID: UInt32
    let sha256: String
    let extendedAttributeHashes: [String: String]

    static func capture(_ url: URL) throws -> SafariPlistMutationFileSnapshot {
        let before = try safeStat(url)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SafariPlistMutationGateError.sourceUnsafe
        }
        guard data.count == Int(before.st_size),
              data.count <= SystemSafariBookmarksSnapshotReader.maximumBytes else {
            throw SafariPlistMutationGateError.sourceUnstable
        }
        let xattrs: [String: Data]
        do {
            xattrs = try SafariExtendedAttributes.values(at: url)
        } catch {
            throw SafariPlistMutationGateError.sourceUnsafe
        }
        let after = try safeStat(url)
        guard sameIdentityAndRevision(before, after) else {
            throw SafariPlistMutationGateError.sourceUnstable
        }
        return .init(
            device: UInt64(before.st_dev),
            inode: UInt64(before.st_ino),
            size: before.st_size,
            modificationSeconds: Int64(before.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(before.st_mtimespec.tv_nsec),
            mode: UInt16(before.st_mode & 0o7777),
            ownerID: before.st_uid,
            groupID: before.st_gid,
            sha256: digest(data),
            extendedAttributeHashes: xattrs.mapValues(digest)
        )
    }

    func with(size: Int64) -> SafariPlistMutationFileSnapshot {
        .init(
            device: device,
            inode: inode,
            size: size,
            modificationSeconds: modificationSeconds,
            modificationNanoseconds: modificationNanoseconds,
            mode: mode,
            ownerID: ownerID,
            groupID: groupID,
            sha256: sha256,
            extendedAttributeHashes: extendedAttributeHashes
        )
    }

    private static func safeStat(_ url: URL) throws -> stat {
        var value = stat()
        guard lstat(url.path, &value) == 0,
              (value.st_mode & S_IFMT) == S_IFREG,
              value.st_uid == geteuid(),
              value.st_size >= 0,
              value.st_size <= SystemSafariBookmarksSnapshotReader.maximumBytes else {
            throw SafariPlistMutationGateError.sourceUnsafe
        }
        return value
    }

    private static func sameIdentityAndRevision(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev &&
            lhs.st_ino == rhs.st_ino &&
            lhs.st_size == rhs.st_size &&
            lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec &&
            lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec &&
            lhs.st_mode == rhs.st_mode &&
            lhs.st_uid == rhs.st_uid &&
            lhs.st_gid == rhs.st_gid
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct SafariPlistMutationSafetyReport: Equatable {
    let sourceStable: Bool
    let sourceSHA256: String
    let sourceBytes: Int
    let sourceExtendedAttributeNames: [String]
    let backupURL: URL
    let metadataURL: URL
    let sourceSnapshot: SafariPlistMutationFileSnapshot
}

struct SafariPlistMutationSafetyGate {
    typealias BooleanProbe = () throws -> Bool
    typealias FileProbe = (URL) throws -> Bool
    typealias Pause = (TimeInterval) -> Void
    typealias Snapshot = (URL) throws -> SafariPlistMutationFileSnapshot

    private let safariRunning: BooleanProbe
    private let plistHasOpenHandles: FileProbe
    private let pause: Pause
    private let snapshot: Snapshot

    init(
        safariRunning: @escaping BooleanProbe = Self.systemSafariRunning,
        plistHasOpenHandles: @escaping FileProbe = Self.systemPlistHasOpenHandles,
        pause: @escaping Pause = { Thread.sleep(forTimeInterval: $0) },
        snapshot: @escaping Snapshot = SafariPlistMutationFileSnapshot.capture
    ) {
        self.safariRunning = safariRunning
        self.plistHasOpenHandles = plistHasOpenHandles
        self.pause = pause
        self.snapshot = snapshot
    }

    func prepare(source: URL, recoveryDirectory: URL) throws -> SafariPlistMutationSafetyReport {
        try assertQuiescent(source)
        let first = try snapshot(source)
        pause(0.5)
        try assertQuiescent(source)
        let second = try snapshot(source)
        guard first == second else { throw SafariPlistMutationGateError.sourceUnstable }

        let createdDirectory = try prepareRecoveryDirectory(recoveryDirectory)
        let token = UUID().uuidString.lowercased()
        let backup = recoveryDirectory.appendingPathComponent("bookmarks-recovery-\(token).plist")
        let metadata = recoveryDirectory.appendingPathComponent("bookmarks-recovery-\(token).json")
        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.removeItem(at: metadata)
                if createdDirectory { try? FileManager.default.removeItem(at: recoveryDirectory) }
            }
        }

        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: source)
        } catch {
            throw SafariPlistMutationGateError.recoveryWriteFailed
        }
        guard sourceData.count == Int(first.size), digest(sourceData) == first.sha256 else {
            throw SafariPlistMutationGateError.sourceUnstable
        }
        try writePrivateFile(sourceData, to: backup)
        try copySourceExtendedAttributes(source, to: backup)
        guard try SafariPlistMutationFileSnapshot.capture(backup).sha256 == first.sha256,
              privateMode(backup) == 0o600 else {
            throw SafariPlistMutationGateError.recoveryWriteFailed
        }

        let plistVersion = try plistSchemaVersion(sourceData)
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "plistVersion": plistVersion,
            "sourceSHA256": first.sha256,
            "sourceBytes": Int(first.size),
            "sourceDevice": first.device,
            "sourceInode": first.inode,
            "sourceModificationSeconds": first.modificationSeconds,
            "sourceModificationNanoseconds": first.modificationNanoseconds,
            "sourceMode": first.mode,
            "sourceOwnerID": first.ownerID,
            "sourceGroupID": first.groupID,
            "sourceExtendedAttributeNames": first.extendedAttributeHashes.keys.sorted()
        ]
        let metadataData: Data
        do {
            metadataData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        } catch {
            throw SafariPlistMutationGateError.recoveryWriteFailed
        }
        try writePrivateFile(metadataData, to: metadata)

        try assertQuiescent(source)
        let third = try snapshot(source)
        guard third == first else { throw SafariPlistMutationGateError.sourceUnstable }
        completed = true
        return .init(
            sourceStable: true,
            sourceSHA256: first.sha256,
            sourceBytes: Int(first.size),
            sourceExtendedAttributeNames: first.extendedAttributeHashes.keys.sorted(),
            backupURL: backup,
            metadataURL: metadata,
            sourceSnapshot: first
        )
    }

    static func systemSafariRunning() throws -> Bool {
        let identifiers = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
        return identifiers.contains { identifier in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .contains { !$0.isTerminated }
        }
    }

    static func systemPlistHasOpenHandles(_ url: URL) throws -> Bool {
        let executable = URL(fileURLWithPath: "/usr/sbin/lsof")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw SafariPlistMutationGateError.processProbeFailed
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-F", "p", "--", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() }
        catch { throw SafariPlistMutationGateError.processProbeFailed }

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard !process.isRunning else {
            process.terminate()
            throw SafariPlistMutationGateError.processProbeFailed
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        switch process.terminationStatus {
        case 0:
            return data.split(separator: 0x0A).contains { $0.first == 0x70 }
        case 1:
            return false
        default:
            throw SafariPlistMutationGateError.processProbeFailed
        }
    }

    private func assertQuiescent(_ source: URL) throws {
        if try safariRunning() { throw SafariPlistMutationGateError.safariRunning }
        if try plistHasOpenHandles(source) { throw SafariPlistMutationGateError.plistInUse }
    }

    private func prepareRecoveryDirectory(_ url: URL) throws -> Bool {
        var value = stat()
        if lstat(url.path, &value) == 0 {
            guard (value.st_mode & S_IFMT) == S_IFDIR,
                  value.st_uid == geteuid(),
                  UInt16(value.st_mode & 0o7777) == 0o700 else {
                throw SafariPlistMutationGateError.recoveryDirectoryUnsafe
            }
            return false
        }
        guard errno == ENOENT else { throw SafariPlistMutationGateError.recoveryDirectoryUnsafe }
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw SafariPlistMutationGateError.recoveryDirectoryUnsafe
        }
        guard privateMode(url) == 0o700 else {
            try? FileManager.default.removeItem(at: url)
            throw SafariPlistMutationGateError.recoveryDirectoryUnsafe
        }
        return true
    }

    private func writePrivateFile(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw SafariPlistMutationGateError.recoveryWriteFailed }
        var succeeded = false
        defer {
            close(descriptor)
            if !succeeded { unlink(url.path) }
        }
        do {
            try data.withUnsafeBytes { buffer in
                guard var address = buffer.baseAddress else { return }
                var remaining = buffer.count
                while remaining > 0 {
                    let count = write(descriptor, address, remaining)
                    guard count > 0 else { throw SafariPlistMutationGateError.recoveryWriteFailed }
                    remaining -= count
                    address = address.advanced(by: count)
                }
            }
            guard fsync(descriptor) == 0, fchmod(descriptor, 0o600) == 0 else {
                throw SafariPlistMutationGateError.recoveryWriteFailed
            }
            succeeded = true
        } catch let error as SafariPlistMutationGateError {
            throw error
        } catch {
            throw SafariPlistMutationGateError.recoveryWriteFailed
        }
    }

    private func copySourceExtendedAttributes(_ source: URL, to destination: URL) throws {
        let attributes: [String: Data]
        do { attributes = try SafariExtendedAttributes.values(at: source) }
        catch { throw SafariPlistMutationGateError.recoveryWriteFailed }
        do {
            for (name, value) in attributes {
                try SafariExtendedAttributes.set(name: name, value: value, at: destination)
            }
        } catch {
            throw SafariPlistMutationGateError.recoveryWriteFailed
        }
    }

    private func plistSchemaVersion(_ data: Data) throws -> Int {
        let object: Any
        do { object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) }
        catch { throw SafariPlistMutationGateError.sourceUnsafe }
        guard let root = object as? [String: Any],
              let value = root["WebBookmarkFileVersion"] as? NSNumber else {
            throw SafariPlistMutationGateError.sourceUnsafe
        }
        return value.intValue
    }

    private func privateMode(_ url: URL) -> UInt16 {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return 0 }
        return UInt16(value.st_mode & 0o7777)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
