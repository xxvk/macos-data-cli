import CryptoKit
import Core
import Darwin
import Foundation

enum SafariPlistAtomicMutationError: Error, Equatable {
    case safariRunning
    case plistInUse
    case staleSafetyGate
    case invalidPreparedMutation
    case candidateCopyFailed
    case candidateWriteFailed
    case candidateMetadataMismatch(fields: [String])
    case atomicSwapFailed
    case postWriteVerificationFailed
    case rollbackFailed
    case cleanupFailed
}

struct SafariPlistAtomicMutationResult: Equatable {
    let replaced: Bool
    let sourceSHA256Before: String
    let sourceSHA256After: String
    let destinationAddedExtendedAttributeNames: [String]
}

struct SafariPlistAtomicMutationWriter {
    typealias BooleanProbe = () throws -> Bool
    typealias FileProbe = (URL) throws -> Bool
    typealias PostSwapValidation = (URL, Data) throws -> Void

    private let safariRunning: BooleanProbe
    private let plistHasOpenHandles: FileProbe
    private let postSwapValidation: PostSwapValidation

    init(
        safariRunning: @escaping BooleanProbe = SafariPlistMutationSafetyGate.systemSafariRunning,
        plistHasOpenHandles: @escaping FileProbe = SafariPlistMutationSafetyGate.systemPlistHasOpenHandles,
        postSwapValidation: @escaping PostSwapValidation = { _, _ in }
    ) {
        self.safariRunning = safariRunning
        self.plistHasOpenHandles = plistHasOpenHandles
        self.postSwapValidation = postSwapValidation
    }

    func replace(
        source: URL,
        safety: SafariPlistMutationSafetyReport,
        mutation: SafariPlistMutationSimulationReport
    ) throws -> SafariPlistAtomicMutationResult {
        guard mutation.sourceSHA256 == safety.sourceSHA256,
              (-1...1).contains(mutation.addedNodeCount),
              mutation.untouchedSubtreeHashesPreserved,
              mutation.outputData.count <= SystemSafariBookmarksSnapshotReader.maximumBytes else {
            throw SafariPlistAtomicMutationError.invalidPreparedMutation
        }
        do { _ = try SafariBookmarksParser.parse(data: mutation.outputData) }
        catch { throw SafariPlistAtomicMutationError.invalidPreparedMutation }

        try assertQuiescent(source)
        let current = try currentSnapshot(source)
        guard current == safety.sourceSnapshot else {
            DiagnosticLogger.record(code: "SAFARI_LOCAL_MUTATION_STALE_CHECKPOINT", message: "checkpoint=source_after_recovery")
            throw SafariPlistAtomicMutationError.staleSafetyGate
        }
        try validateRecovery(safety)

        let candidate = source.deletingLastPathComponent()
            .appendingPathComponent(".mpia-safari-swap-" + UUID().uuidString.lowercased())
        var candidateExists = false
        var swapped = false
        defer {
            if candidateExists { try? FileManager.default.removeItem(at: candidate) }
        }

        try createCandidate(
            source: source,
            destination: candidate,
            data: mutation.outputData,
            expectedSource: current
        )
        candidateExists = true
        try assertQuiescent(source)
        guard try currentSnapshot(source) == current else {
            DiagnosticLogger.record(code: "SAFARI_LOCAL_MUTATION_STALE_CHECKPOINT", message: "checkpoint=source_after_candidate")
            throw SafariPlistAtomicMutationError.staleSafetyGate
        }

        guard atomicSwap(source, candidate) else {
            throw SafariPlistAtomicMutationError.atomicSwapFailed
        }
        swapped = true

        do {
            try syncDirectory(source.deletingLastPathComponent())
            let addedAttributes = try validateAfterSwap(
                source: source,
                oldSource: candidate,
                safety: safety,
                mutation: mutation
            )
            try postSwapValidation(source, mutation.outputData)
            guard try removeCandidate(candidate) else {
                throw SafariPlistAtomicMutationError.cleanupFailed
            }
            candidateExists = false
            swapped = false
            try? syncDirectory(source.deletingLastPathComponent())
            return .init(
                replaced: true,
                sourceSHA256Before: safety.sourceSHA256,
                sourceSHA256After: digest(mutation.outputData),
                destinationAddedExtendedAttributeNames: addedAttributes
            )
        } catch {
            guard swapped, atomicSwap(source, candidate) else {
                throw SafariPlistAtomicMutationError.rollbackFailed
            }
            swapped = false
            try? syncDirectory(source.deletingLastPathComponent())
            guard (try? currentSnapshot(source)) == safety.sourceSnapshot,
                  (try? Data(contentsOf: source)) == (try? Data(contentsOf: safety.backupURL)) else {
                throw SafariPlistAtomicMutationError.rollbackFailed
            }
            guard try removeCandidate(candidate) else {
                throw SafariPlistAtomicMutationError.rollbackFailed
            }
            candidateExists = false
            if let atomicError = error as? SafariPlistAtomicMutationError { throw atomicError }
            throw SafariPlistAtomicMutationError.postWriteVerificationFailed
        }
    }

    private func assertQuiescent(_ source: URL) throws {
        do {
            if try safariRunning() { throw SafariPlistAtomicMutationError.safariRunning }
            if try plistHasOpenHandles(source) { throw SafariPlistAtomicMutationError.plistInUse }
        } catch let error as SafariPlistAtomicMutationError {
            throw error
        } catch {
            throw SafariPlistAtomicMutationError.plistInUse
        }
    }

    private func currentSnapshot(_ url: URL) throws -> SafariPlistMutationFileSnapshot {
        do { return try SafariPlistMutationFileSnapshot.capture(url) }
        catch { throw SafariPlistAtomicMutationError.staleSafetyGate }
    }

    private func validateRecovery(_ safety: SafariPlistMutationSafetyReport) throws {
        var failed: [String] = []
        if directoryMode(safety.backupURL.deletingLastPathComponent()) != 0o700 { failed.append("directoryMode") }
        if privateMode(safety.backupURL) != 0o600 { failed.append("backupMode") }
        if privateMode(safety.metadataURL) != 0o600 { failed.append("metadataMode") }

        let backupData = try? Data(contentsOf: safety.backupURL)
        if backupData.map(digest) != safety.sourceSHA256 { failed.append("backupSHA256") }
        let backupSnapshot = try? SafariPlistMutationFileSnapshot.capture(safety.backupURL)
        if let backupSnapshot {
            if !Self.preservesSourceExtendedAttributes(
                safety.sourceSnapshot.extendedAttributeHashes,
                in: backupSnapshot.extendedAttributeHashes
            ) { failed.append("backupSourceXattrs") }
            let added = backupSnapshot.extendedAttributeHashes.keys.filter {
                safety.sourceSnapshot.extendedAttributeHashes[$0] == nil
            }
            if !Set(added).isSubset(of: ["com.apple.provenance"]) { failed.append("backupAddedXattrs") }
        } else {
            failed.append("backupSnapshot")
        }

        let metadataData = try? Data(contentsOf: safety.metadataURL)
        let manifest = metadataData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        if let manifest {
            if (manifest["schemaVersion"] as? NSNumber)?.intValue != 1 { failed.append("schemaVersion") }
            if manifest["sourceSHA256"] as? String != safety.sourceSHA256 { failed.append("sourceSHA256") }
            if (manifest["sourceBytes"] as? NSNumber)?.int64Value != safety.sourceSnapshot.size { failed.append("sourceBytes") }
            if (manifest["sourceDevice"] as? NSNumber)?.uint64Value != safety.sourceSnapshot.device { failed.append("sourceDevice") }
            if (manifest["sourceInode"] as? NSNumber)?.uint64Value != safety.sourceSnapshot.inode { failed.append("sourceInode") }
            if (manifest["sourceModificationSeconds"] as? NSNumber)?.int64Value != safety.sourceSnapshot.modificationSeconds { failed.append("sourceModificationSeconds") }
            if (manifest["sourceModificationNanoseconds"] as? NSNumber)?.int64Value != safety.sourceSnapshot.modificationNanoseconds { failed.append("sourceModificationNanoseconds") }
            if (manifest["sourceMode"] as? NSNumber)?.uint16Value != safety.sourceSnapshot.mode { failed.append("sourceMode") }
            if (manifest["sourceOwnerID"] as? NSNumber)?.uint32Value != safety.sourceSnapshot.ownerID { failed.append("sourceOwnerID") }
            if (manifest["sourceGroupID"] as? NSNumber)?.uint32Value != safety.sourceSnapshot.groupID { failed.append("sourceGroupID") }
            if manifest["sourceExtendedAttributeNames"] as? [String] != safety.sourceExtendedAttributeNames { failed.append("sourceExtendedAttributeNames") }
        } else {
            failed.append("manifestJSON")
        }

        guard failed.isEmpty else {
            DiagnosticLogger.record(
                code: "SAFARI_LOCAL_MUTATION_STALE_CHECKPOINT",
                message: "checkpoint=recovery_manifest failedFields=\(failed.sorted().joined(separator: ","))"
            )
            throw SafariPlistAtomicMutationError.staleSafetyGate
        }
    }

    private func createCandidate(
        source: URL,
        destination: URL,
        data: Data,
        expectedSource: SafariPlistMutationFileSnapshot
    ) throws {
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_EXCL)
        guard copyfile(source.path, destination.path, nil, flags) == 0 else {
            throw SafariPlistAtomicMutationError.candidateCopyFailed
        }
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: destination) }
        }
        let descriptor = open(destination.path, O_WRONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw SafariPlistAtomicMutationError.candidateWriteFailed }
        defer { close(descriptor) }
        guard ftruncate(descriptor, 0) == 0 else {
            throw SafariPlistAtomicMutationError.candidateWriteFailed
        }
        do {
            try data.withUnsafeBytes { buffer in
                guard var address = buffer.baseAddress else { return }
                var remaining = buffer.count
                while remaining > 0 {
                    let count = write(descriptor, address, remaining)
                    guard count > 0 else { throw SafariPlistAtomicMutationError.candidateWriteFailed }
                    remaining -= count
                    address = address.advanced(by: count)
                }
            }
        } catch let error as SafariPlistAtomicMutationError {
            throw error
        } catch {
            throw SafariPlistAtomicMutationError.candidateWriteFailed
        }
        guard fchmod(descriptor, mode_t(expectedSource.mode)) == 0,
              fsync(descriptor) == 0 else {
            throw SafariPlistAtomicMutationError.candidateWriteFailed
        }
        let sourceXattrs: [String: Data]
        do { sourceXattrs = try SafariExtendedAttributes.values(at: source) }
        catch { throw SafariPlistAtomicMutationError.candidateWriteFailed }
        guard sourceXattrs.count == expectedSource.extendedAttributeHashes.count,
              sourceXattrs.allSatisfy({ expectedSource.extendedAttributeHashes[$0.key] == digest($0.value) }) else {
            DiagnosticLogger.record(code: "SAFARI_LOCAL_MUTATION_STALE_CHECKPOINT", message: "checkpoint=source_xattrs")
            throw SafariPlistAtomicMutationError.staleSafetyGate
        }
        do {
            for (name, value) in sourceXattrs {
                try SafariExtendedAttributes.set(name: name, value: value, at: destination)
            }
        } catch {
            throw SafariPlistAtomicMutationError.candidateWriteFailed
        }
        let candidate: SafariPlistMutationFileSnapshot
        do { candidate = try SafariPlistMutationFileSnapshot.capture(destination) }
        catch { throw SafariPlistAtomicMutationError.candidateWriteFailed }
        let added = candidate.extendedAttributeHashes.keys.filter {
            expectedSource.extendedAttributeHashes[$0] == nil
        }
        var mismatches: [String] = []
        if candidate.sha256 != digest(data) { mismatches.append("sha256") }
        if candidate.mode != expectedSource.mode { mismatches.append("mode") }
        if candidate.ownerID != expectedSource.ownerID { mismatches.append("owner") }
        if candidate.groupID != expectedSource.groupID { mismatches.append("group") }
        if !Self.preservesSourceExtendedAttributes(
            expectedSource.extendedAttributeHashes,
            in: candidate.extendedAttributeHashes
        ) { mismatches.append("sourceXattrValues") }
        if !Set(added).isSubset(of: ["com.apple.provenance"]) {
            mismatches.append("addedXattrPolicy")
        }
        guard mismatches.isEmpty else {
            throw SafariPlistAtomicMutationError.candidateMetadataMismatch(fields: mismatches)
        }
        completed = true
    }

    private func validateAfterSwap(
        source: URL,
        oldSource: URL,
        safety: SafariPlistMutationSafetyReport,
        mutation: SafariPlistMutationSimulationReport
    ) throws -> [String] {
        let newSnapshot: SafariPlistMutationFileSnapshot
        let oldSnapshot: SafariPlistMutationFileSnapshot
        do {
            newSnapshot = try SafariPlistMutationFileSnapshot.capture(source)
            oldSnapshot = try SafariPlistMutationFileSnapshot.capture(oldSource)
        } catch {
            throw SafariPlistAtomicMutationError.postWriteVerificationFailed
        }
        let added = newSnapshot.extendedAttributeHashes.keys.filter {
            safety.sourceSnapshot.extendedAttributeHashes[$0] == nil
        }.sorted()
        guard newSnapshot.sha256 == digest(mutation.outputData),
              newSnapshot.mode == safety.sourceSnapshot.mode,
              newSnapshot.ownerID == safety.sourceSnapshot.ownerID,
              newSnapshot.groupID == safety.sourceSnapshot.groupID,
              Self.preservesSourceExtendedAttributes(
                  safety.sourceSnapshot.extendedAttributeHashes,
                  in: newSnapshot.extendedAttributeHashes
              ),
              Set(added).isSubset(of: ["com.apple.provenance"]),
              oldSnapshot == safety.sourceSnapshot,
              let backupData = try? Data(contentsOf: safety.backupURL),
              digest(backupData) == safety.sourceSHA256 else {
            throw SafariPlistAtomicMutationError.postWriteVerificationFailed
        }
        do { _ = try SafariBookmarksParser.parse(data: mutation.outputData) }
        catch { throw SafariPlistAtomicMutationError.postWriteVerificationFailed }
        return added
    }

    /// `com.apple.provenance` is file-instance metadata. macOS may regenerate its
    /// value when a private recovery or swap candidate is created, so its
    /// presence is enforced while its digest is deliberately not compared.
    static func preservesSourceExtendedAttributes(
        _ source: [String: String],
        in destination: [String: String]
    ) -> Bool {
        source.allSatisfy { name, hash in
            guard let destinationHash = destination[name] else { return false }
            return name == "com.apple.provenance" || destinationHash == hash
        }
    }

    private func atomicSwap(_ lhs: URL, _ rhs: URL) -> Bool {
        renameatx_np(AT_FDCWD, lhs.path, AT_FDCWD, rhs.path, UInt32(RENAME_SWAP)) == 0
    }

    private func removeCandidate(_ url: URL) throws -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw SafariPlistAtomicMutationError.atomicSwapFailed }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw SafariPlistAtomicMutationError.atomicSwapFailed }
    }

    private func privateMode(_ url: URL) -> UInt16 {
        var value = stat()
        guard lstat(url.path, &value) == 0,
              (value.st_mode & S_IFMT) == S_IFREG,
              value.st_uid == geteuid() else { return 0 }
        return UInt16(value.st_mode & 0o7777)
    }

    private func directoryMode(_ url: URL) -> UInt16 {
        var value = stat()
        guard lstat(url.path, &value) == 0,
              (value.st_mode & S_IFMT) == S_IFDIR,
              value.st_uid == geteuid() else { return 0 }
        return UInt16(value.st_mode & 0o7777)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
