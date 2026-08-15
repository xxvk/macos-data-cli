import Darwin
import Foundation
import Testing
@testable import SafariAdapter

@Suite("Safari 0.8.1 plist mutation feasibility")
struct SafariPlistMutationFeasibilityTests {
    @Test("Safety gate refuses a running Safari before reading or backing up")
    func safetyGateRejectsRunningSafari() throws {
        var snapshots = 0
        let gate = SafariPlistMutationSafetyGate(
            safariRunning: { true },
            plistHasOpenHandles: { _ in false },
            pause: { _ in },
            snapshot: { _ in
                snapshots += 1
                throw SafariPlistMutationGateError.sourceUnstable
            }
        )

        #expect(throws: SafariPlistMutationGateError.safariRunning) {
            try gate.prepare(
                source: URL(fileURLWithPath: "/unused/Bookmarks.plist"),
                recoveryDirectory: URL(fileURLWithPath: "/unused/recovery")
            )
        }
        #expect(snapshots == 0)
    }

    @Test("Safety gate creates exact 0600 recovery data and private metadata")
    func safetyGateCreatesPrivateRecoveryBackup() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        let sourceData = try syntheticPlistData()
        try sourceData.write(to: source, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path)
        try SafariExtendedAttributes.set(
            name: "com.xvk.mpia.test",
            value: Data("backup-xattr".utf8),
            at: source
        )
        let gate = SafariPlistMutationSafetyGate(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false },
            pause: { _ in }
        )

        let report = try gate.prepare(source: source, recoveryDirectory: recovery)

        #expect(report.sourceStable)
        #expect(report.sourceSHA256.count == 64)
        #expect(try Data(contentsOf: report.backupURL) == sourceData)
        #expect(posixMode(recovery) == 0o700)
        #expect(posixMode(report.backupURL) == 0o600)
        #expect(posixMode(report.metadataURL) == 0o600)
        #expect(try SafariExtendedAttributes.value(
            name: "com.xvk.mpia.test", at: report.backupURL
        ) == Data("backup-xattr".utf8))
        let metadata = try Data(contentsOf: report.metadataURL)
        let object = try JSONSerialization.jsonObject(with: metadata) as! [String: Any]
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["sourceSHA256"] as? String == report.sourceSHA256)
        #expect(object["sourceBytes"] as? Int == sourceData.count)
        #expect(object["sourcePath"] == nil)
        #expect(String(decoding: metadata, as: UTF8.self).contains("First") == false)
        #expect(String(decoding: metadata, as: UTF8.self).contains("example.com") == false)
    }

    @Test("Safety gate rejects unstable source and leaves no recovery artifacts")
    func safetyGateRejectsUnstableSource() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        try syntheticPlistData().write(to: source, options: .withoutOverwriting)
        let stable = try SafariPlistMutationFileSnapshot.capture(source)
        var calls = 0
        let gate = SafariPlistMutationSafetyGate(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false },
            pause: { _ in },
            snapshot: { _ in
                calls += 1
                if calls == 1 { return stable }
                return stable.with(size: stable.size + 1)
            }
        )

        #expect(throws: SafariPlistMutationGateError.sourceUnstable) {
            try gate.prepare(source: source, recoveryDirectory: recovery)
        }
        #expect(FileManager.default.fileExists(atPath: recovery.path) == false)
    }

    @Test("Safety gate refuses open plist handles")
    func safetyGateRejectsOpenHandles() throws {
        let gate = SafariPlistMutationSafetyGate(
            safariRunning: { false },
            plistHasOpenHandles: { _ in true },
            pause: { _ in }
        )
        #expect(throws: SafariPlistMutationGateError.plistInUse) {
            try gate.prepare(
                source: URL(fileURLWithPath: "/unused/Bookmarks.plist"),
                recoveryDirectory: URL(fileURLWithPath: "/unused/recovery")
            )
        }
    }

    @Test("Atomic writer swaps one prepared mutation and preserves recovery")
    func atomicWriterAppliesPreparedMutation() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        let original = try syntheticPlistData()
        try original.write(to: source, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: source.path)
        try SafariExtendedAttributes.set(
            name: "com.xvk.mpia.test",
            value: Data("atomic-xattr".utf8),
            at: source
        )
        let gate = testSafetyGate()
        let safety = try gate.prepare(source: source, recoveryDirectory: recovery)
        let mutation = try disposableMutation(from: original)
        let writer = SafariPlistAtomicMutationWriter(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false }
        )

        let result = try writer.replace(source: source, safety: safety, mutation: mutation)

        #expect(result.replaced)
        #expect(result.sourceSHA256Before == safety.sourceSHA256)
        #expect(result.sourceSHA256After.count == 64)
        #expect(result.sourceSHA256After != result.sourceSHA256Before)
        #expect(try Data(contentsOf: source) == mutation.outputData)
        #expect(try Data(contentsOf: safety.backupURL) == original)
        #expect(posixMode(source) == 0o644)
        #expect(try SafariExtendedAttributes.value(
            name: "com.xvk.mpia.test", at: source
        ) == Data("atomic-xattr".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".mpia-safari-swap-") }.isEmpty)
    }

    @Test("Atomic writer rejects a stale gate before replacement")
    func atomicWriterRejectsStaleSource() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        let original = try syntheticPlistData()
        try original.write(to: source, options: .withoutOverwriting)
        let safety = try testSafetyGate().prepare(source: source, recoveryDirectory: recovery)
        let mutation = try disposableMutation(from: original)
        var changed = original
        changed.append(0)
        try changed.write(to: source, options: .atomic)
        let writer = SafariPlistAtomicMutationWriter(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false }
        )

        #expect(throws: SafariPlistAtomicMutationError.staleSafetyGate) {
            try writer.replace(source: source, safety: safety, mutation: mutation)
        }
        #expect(try Data(contentsOf: source) == changed)
    }

    @Test("Atomic writer restores the exact original after post-swap failure")
    func atomicWriterRollsBackFailedReadback() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        let original = try syntheticPlistData()
        try original.write(to: source, options: .withoutOverwriting)
        let safety = try testSafetyGate().prepare(source: source, recoveryDirectory: recovery)
        let mutation = try disposableMutation(from: original)
        let writer = SafariPlistAtomicMutationWriter(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false },
            postSwapValidation: { _, _ in
                throw SafariPlistAtomicMutationError.postWriteVerificationFailed
            }
        )

        #expect(throws: SafariPlistAtomicMutationError.postWriteVerificationFailed) {
            try writer.replace(source: source, safety: safety, mutation: mutation)
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(try Data(contentsOf: safety.backupURL) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".mpia-safari-swap-") }.isEmpty)
    }

    @Test("Atomic writer refuses a tampered recovery manifest")
    func atomicWriterRejectsTamperedRecovery() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Bookmarks.plist")
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        let original = try syntheticPlistData()
        try original.write(to: source, options: .withoutOverwriting)
        let safety = try testSafetyGate().prepare(source: source, recoveryDirectory: recovery)
        let handle = try FileHandle(forWritingTo: safety.metadataURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(#"{"schemaVersion":1}"#.utf8))
        try handle.synchronize()
        try handle.close()
        let writer = SafariPlistAtomicMutationWriter(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false }
        )

        #expect(throws: SafariPlistAtomicMutationError.staleSafetyGate) {
            try writer.replace(
                source: source,
                safety: safety,
                mutation: try disposableMutation(from: original)
            )
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test("Atomic writer treats provenance as file-instance metadata only")
    func atomicWriterAllowsRegeneratedProvenanceValue() {
        let source = [
            "com.apple.provenance": "source-instance-hash",
            "com.example.stable": "stable-hash"
        ]

        #expect(SafariPlistAtomicMutationWriter.preservesSourceExtendedAttributes(
            source,
            in: [
                "com.apple.provenance": "destination-instance-hash",
                "com.example.stable": "stable-hash"
            ]
        ))
        #expect(!SafariPlistAtomicMutationWriter.preservesSourceExtendedAttributes(
            source,
            in: [
                "com.apple.provenance": "destination-instance-hash",
                "com.example.stable": "changed-hash"
            ]
        ))
        #expect(!SafariPlistAtomicMutationWriter.preservesSourceExtendedAttributes(
            source,
            in: ["com.example.stable": "stable-hash"]
        ))
    }

    @Test("Binary round-trip preserves unknown values and ordered children")
    func roundTripPreservesSemanticValues() throws {
        let data = try syntheticPlistData()

        let report = try SafariPlistRoundTripInspector.inspect(data: data)

        #expect(report.sourceFormat == .binary)
        #expect(report.outputFormat == .binary)
        #expect(report.semanticEqual)
        #expect(report.orderedChildrenEqual)
        #expect(report.sourceSHA256.count == 64)
        #expect(report.outputSHA256.count == 64)
    }

    @Test("Private copy preserves mode owner group and xattr values")
    func privateCopyPreservesMetadata() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.plist")
        let destination = directory.appendingPathComponent("destination.plist")
        try syntheticPlistData().write(to: source, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        try SafariExtendedAttributes.set(name: "com.xvk.mpia.test", value: Data("fixture-xattr".utf8), at: source)

        let report = try SafariPlistRoundTripInspector.writePrivateCopy(source: source, destination: destination)

        #expect(report.semanticEqual)
        #expect(report.orderedChildrenEqual)
        #expect(report.sourceMetadata.mode == 0o640)
        #expect(report.destinationMetadata.mode == report.sourceMetadata.mode)
        #expect(report.destinationMetadata.ownerID == report.sourceMetadata.ownerID)
        #expect(report.destinationMetadata.groupID == report.sourceMetadata.groupID)
        #expect(report.destinationMetadata.extendedAttributeNames == report.sourceMetadata.extendedAttributeNames)
        #expect(report.destinationAddedExtendedAttributeNames.isEmpty)
        #expect(try SafariExtendedAttributes.value(name: "com.xvk.mpia.test", at: destination) == Data("fixture-xattr".utf8))
    }

    @Test("Copy gate rejects symlinks and refuses overwrite")
    func copyGateFailsClosed() throws {
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.plist")
        let symlink = directory.appendingPathComponent("source-link.plist")
        let destination = directory.appendingPathComponent("destination.plist")
        try syntheticPlistData().write(to: source, options: .withoutOverwriting)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)

        #expect(throws: SafariPlistFeasibilityError.sourceUnsafe) {
            try SafariPlistRoundTripInspector.writePrivateCopy(source: symlink, destination: destination)
        }

        try Data("occupied".utf8).write(to: destination, options: .withoutOverwriting)
        #expect(throws: SafariPlistFeasibilityError.destinationExists) {
            try SafariPlistRoundTripInspector.writePrivateCopy(source: source, destination: destination)
        }
    }

    @Test("Append simulation changes only target ancestry and adds one UUID")
    func appendSimulationPreservesUntouchedSubtrees() throws {
        let bookmark: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": "DISPOSABLE-UUID",
            "URLString": "https://example.com/disposable",
            "URIDictionary": ["title": "Disposable"]
        ]

        let report = try SafariPlistRoundTripInspector.simulateAppendBookmark(
            data: syntheticPlistData(),
            parentUUID: "ROOT-UUID",
            bookmark: bookmark
        )

        #expect(report.existingNodeCount == 3)
        #expect(report.untouchedNodeCount == 2)
        #expect(report.changedAncestorCount == 1)
        #expect(report.addedNodeCount == 1)
        #expect(report.untouchedSubtreeHashesPreserved)
        let parsed = try SafariBookmarksParser.parse(data: report.outputData)
        #expect(parsed.bookmarks.count == 3)
        let verification = try SafariPlistRoundTripInspector.verifySingleAppend(
            beforeData: syntheticPlistData(),
            afterData: report.outputData,
            parentUUID: "ROOT-UUID",
            fixtureUUID: "DISPOSABLE-UUID"
        )
        #expect(verification.addedNodeCount == 1)
        #expect(verification.fixtureParentMatched)
        #expect(verification.untouchedSubtreeHashesPreserved)
    }

    @Test("Append simulation rejects duplicate UUID and unknown node type")
    func appendSimulationFailsClosed() throws {
        let duplicate: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": "FIRST-UUID",
            "URLString": "https://example.com/duplicate"
        ]
        #expect(throws: SafariPlistFeasibilityError.duplicateIdentifier) {
            try SafariPlistRoundTripInspector.simulateAppendBookmark(
                data: syntheticPlistData(),
                parentUUID: "ROOT-UUID",
                bookmark: duplicate
            )
        }

        var malformed = try PropertyListSerialization.propertyList(
            from: syntheticPlistData(), options: [], format: nil
        ) as! [String: Any]
        var children = malformed["Children"] as! [[String: Any]]
        children[0]["WebBookmarkType"] = "WebBookmarkTypeFuture"
        malformed["Children"] = children
        let malformedData = try PropertyListSerialization.data(
            fromPropertyList: malformed, format: .binary, options: 0
        )
        #expect(throws: SafariPlistFeasibilityError.plistInvalid) {
            try SafariPlistRoundTripInspector.simulateAppendBookmark(
                data: malformedData,
                parentUUID: "ROOT-UUID",
                bookmark: [
                    "WebBookmarkType": "WebBookmarkTypeLeaf",
                    "WebBookmarkUUID": "NEW-UUID",
                    "URLString": "https://example.com/new"
                ]
            )
        }
    }

    @Test("Readback accepts only Safari's hidden root and proxy UUID regeneration")
    func readbackAcceptsHiddenRootProxyReplacement() throws {
        let before = try rootProxyReplacementData(
            rootUUID: "OLD-ROOT", proxyUUID: "OLD-PROXY", syncValue: "old", includeFixture: false
        )
        let after = try rootProxyReplacementData(
            rootUUID: "NEW-ROOT", proxyUUID: "NEW-PROXY", syncValue: "new", includeFixture: true
        )

        let report = try SafariPlistRoundTripInspector.verifySingleAppend(
            beforeData: before,
            afterData: after,
            parentUUID: "BOOKMARKS-BAR-UUID",
            fixtureUUID: "FIXTURE-UUID"
        )

        #expect(report.volatileInternalUUIDReplacements == 2)
        #expect(report.fixtureParentMatched)
        #expect(report.untouchedSubtreeHashesPreserved)
    }

    @Test("Readback rejects the same UUID regeneration for an adapter-visible folder")
    func readbackRejectsVisibleFolderReplacement() throws {
        let before = try rootProxyReplacementData(
            rootUUID: "OLD-FOLDER", proxyUUID: "OLD-PROXY", syncValue: "old",
            includeFixture: false, exposeReplacementList: true
        )
        let after = try rootProxyReplacementData(
            rootUUID: "NEW-FOLDER", proxyUUID: "NEW-PROXY", syncValue: "new",
            includeFixture: true, exposeReplacementList: true
        )

        #expect(throws: SafariPlistFeasibilityError.self) {
            try SafariPlistRoundTripInspector.verifySingleAppend(
                beforeData: before,
                afterData: after,
                parentUUID: "BOOKMARKS-BAR-UUID",
                fixtureUUID: "FIXTURE-UUID"
            )
        }
    }

    @Test("Built-in BookmarksBar selector requires exactly one matching folder")
    func bookmarksBarSelectorFailsClosed() throws {
        var root = try PropertyListSerialization.propertyList(
            from: syntheticPlistData(), options: [], format: nil
        ) as! [String: Any]
        var children = root["Children"] as! [[String: Any]]
        let bar: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkUUID": "BOOKMARKS-BAR-UUID",
            "Title": "BookmarksBar",
            "Children": []
        ]
        children.append(bar)
        root["Children"] = children
        let unique = try PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0
        )
        #expect(try SafariPlistRoundTripInspector.standardBookmarksBarUUID(data: unique) == "BOOKMARKS-BAR-UUID")

        var duplicateChildren = children
        var duplicate = bar
        duplicate["WebBookmarkUUID"] = "SECOND-BOOKMARKS-BAR-UUID"
        duplicateChildren.append(duplicate)
        root["Children"] = duplicateChildren
        let ambiguous = try PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0
        )
        #expect(throws: SafariPlistFeasibilityError.mutationTargetInvalid) {
            try SafariPlistRoundTripInspector.standardBookmarksBarUUID(data: ambiguous)
        }
    }

    @Test("Opt-in live plist audit mutates only an auto-deleted private copy")
    func liveCopyAudit() throws {
        guard ProcessInfo.processInfo.environment["MPIA_SAFARI_PLIST_COPY_AUDIT"] == "1" else { return }
        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Bookmarks.roundtrip.plist")
        let sourceBefore = try Data(contentsOf: source)

        let report = try SafariPlistRoundTripInspector.writePrivateCopy(source: source, destination: destination)

        let sourceAfter = try Data(contentsOf: source)
        #expect(sourceBefore == sourceAfter)
        #expect(report.semanticEqual)
        #expect(report.orderedChildrenEqual)
        #expect(report.destinationMetadata.mode == report.sourceMetadata.mode)
        #expect(report.destinationMetadata.ownerID == report.sourceMetadata.ownerID)
        #expect(report.destinationMetadata.groupID == report.sourceMetadata.groupID)
        #expect(Set(report.sourceMetadata.extendedAttributeNames).isSubset(of: report.destinationMetadata.extendedAttributeNames))
        #expect(Set(report.destinationAddedExtendedAttributeNames).isSubset(of: ["com.apple.provenance"]))
        print(
            "Safari plist copy audit passed: semanticEqual=\(report.semanticEqual) " +
            "orderedChildrenEqual=\(report.orderedChildrenEqual) byteIdentical=\(report.byteIdentical) " +
            "sourceBytes=\(report.sourceBytes) outputBytes=\(report.outputBytes) " +
            "sourceXattrCount=\(report.sourceMetadata.extendedAttributeNames.count) " +
            "addedSystemXattrs=\(report.destinationAddedExtendedAttributeNames.joined(separator: ",")) " +
            "sourceUnchanged=true"
        )
    }

    @Test("Opt-in live safety gate either blocks active Safari or creates an auto-deleted recovery")
    func liveSafetyGateAudit() throws {
        guard ProcessInfo.processInfo.environment["MPIA_SAFARI_SAFETY_GATE_AUDIT"] == "1" else { return }
        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        let sourceBefore = try Data(contentsOf: source)
        let report: SafariPlistMutationSafetyReport
        do {
            report = try SafariPlistMutationSafetyGate().prepare(
                source: source,
                recoveryDirectory: recovery
            )
        } catch let error as SafariPlistMutationGateError
            where error == .safariRunning || error == .plistInUse || error == .sourceUnstable {
            let sourceAfter = try Data(contentsOf: source)
            #expect(sourceBefore == sourceAfter)
            #expect(FileManager.default.fileExists(atPath: recovery.path) == false)
            print(
                "Safari safety gate audit blocked safely: reason=\(error) " +
                "recoveryCreated=false sourceUnchanged=true"
            )
            return
        }
        let sourceAfter = try Data(contentsOf: source)
        #expect(sourceBefore == sourceAfter)
        #expect(try Data(contentsOf: report.backupURL) == sourceBefore)
        #expect(posixMode(recovery) == 0o700)
        #expect(posixMode(report.backupURL) == 0o600)
        #expect(posixMode(report.metadataURL) == 0o600)
        print(
            "Safari safety gate audit passed: safariRunning=false openHandles=false " +
            "sourceStable=\(report.sourceStable) sourceBytes=\(report.sourceBytes) " +
            "sourceXattrCount=\(report.sourceExtendedAttributeNames.count) " +
            "backupMode=0600 metadataMode=0600 sourceUnchanged=true autoDelete=true"
        )
    }

    @Test("Opt-in private Framework gate retains one exact recovery session")
    func livePrivateFrameworkRecoveryPreparation() throws {
        guard let sessionID = ProcessInfo.processInfo.environment[
            "MPIA_SAFARI_PRIVATE_FRAMEWORK_RECOVERY_SESSION"
        ] else { return }
        guard let session = UUID(uuidString: sessionID) else {
            Issue.record("Invalid private Framework recovery session")
            return
        }
        let source = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        let recovery = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mpia-cli/recovery", isDirectory: true)
            .appendingPathComponent("safari-private-framework", isDirectory: true)
            .appendingPathComponent(session.uuidString.lowercased(), isDirectory: true)
        guard FileManager.default.fileExists(atPath: recovery.path) == false else {
            Issue.record("Private Framework recovery session already exists")
            return
        }

        let sourceBefore = try Data(contentsOf: source)
        let report = try SafariPlistMutationSafetyGate().prepare(
            source: source,
            recoveryDirectory: recovery
        )
        let sourceAfter = try Data(contentsOf: source)
        #expect(sourceBefore == sourceAfter)
        #expect(try Data(contentsOf: report.backupURL) == sourceBefore)
        #expect(posixMode(recovery) == 0o700)
        #expect(posixMode(report.backupURL) == 0o600)
        #expect(posixMode(report.metadataURL) == 0o600)
        print(
            "Safari private Framework recovery prepared: sessionID=\(session.uuidString.lowercased()) " +
            "sourceStable=true backupMode=0600 metadataMode=0600 sourceUnchanged=true retained=true"
        )
    }

    @Test("Opt-in atomic mutation audit uses only an auto-deleted copy of the live plist")
    func livePrivateCopyAtomicMutationAudit() throws {
        guard ProcessInfo.processInfo.environment["MPIA_SAFARI_ATOMIC_COPY_AUDIT"] == "1" else { return }
        let liveSource = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        let liveBefore = try Data(contentsOf: liveSource)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let working = directory.appendingPathComponent("Bookmarks.plist")
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        try liveBefore.write(to: working, options: .withoutOverwriting)
        let sourceMode = posixMode(liveSource)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: sourceMode)],
            ofItemAtPath: working.path
        )
        for (name, value) in try SafariExtendedAttributes.values(at: liveSource) {
            try SafariExtendedAttributes.set(name: name, value: value, at: working)
        }
        let bookmarksBarUUID = try SafariPlistRoundTripInspector.standardBookmarksBarUUID(data: liveBefore)
        let unique = UUID().uuidString
        let fixtureURL = "https://example.com/mpia-safari-private-copy/" + unique
        let mutation = try SafariPlistRoundTripInspector.simulateAppendBookmark(
            data: liveBefore,
            parentUUID: bookmarksBarUUID,
            bookmark: [
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "WebBookmarkUUID": unique,
                "URLString": fixtureURL,
                "URIDictionary": ["title": "mpia private copy fixture"]
            ]
        )
        let safety = try testSafetyGate().prepare(source: working, recoveryDirectory: recovery)
        let result = try SafariPlistAtomicMutationWriter(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false }
        ).replace(source: working, safety: safety, mutation: mutation)
        let parsed = try SafariBookmarksParser.parse(data: Data(contentsOf: working))
        let liveAfter = try Data(contentsOf: liveSource)

        #expect(result.replaced)
        #expect(parsed.bookmarks.filter { $0.url == fixtureURL }.count == 1)
        #expect(liveBefore == liveAfter)
        #expect(try Data(contentsOf: safety.backupURL) == liveBefore)
        print(
            "Safari atomic private-copy audit passed: addedNodes=\(mutation.addedNodeCount) " +
            "untouchedSubtrees=\(mutation.untouchedNodeCount) " +
            "recoveryMode=0600 sourceUnchanged=true autoDelete=true"
        )
    }

    @Test("Retired live mutation gate refuses another persistent fixture")
    func explicitLiveMutationGate() throws {
        let confirmation = ProcessInfo.processInfo.environment["MPIA_SAFARI_LIVE_MUTATION_CONFIRM"]
        guard confirmation != nil else { return }
        throw SafariPlistAtomicMutationError.invalidPreparedMutation
    }

    @Test("Opt-in live readback compares current plist with retained recovery")
    func liveFixtureReadbackAudit() throws {
        guard let sessionID = ProcessInfo.processInfo.environment["MPIA_SAFARI_READBACK_SESSION"] else {
            return
        }
        guard UUID(uuidString: sessionID) != nil else {
            throw SafariPlistFeasibilityError.mutationTargetInvalid
        }
        let recovery = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mpia-cli/recovery/safari", isDirectory: true)
            .appendingPathComponent(sessionID.lowercased(), isDirectory: true)
        let receiptURL = recovery.appendingPathComponent("fixture-receipt.json")
        let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as! [String: Any]
        guard receipt["state"] as? String == "created",
              let fixtureUUID = receipt["fixtureUUID"] as? String,
              let fixtureURL = receipt["fixtureURL"] as? String else {
            throw SafariPlistFeasibilityError.mutationTargetInvalid
        }
        let backupCandidates = try FileManager.default.contentsOfDirectory(
            at: recovery,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).filter { $0.lastPathComponent.hasPrefix("bookmarks-recovery-") && $0.pathExtension == "plist" }
        guard backupCandidates.count == 1,
              try backupCandidates[0].resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
              try backupCandidates[0].resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isSymbolicLink != true else {
            throw SafariPlistFeasibilityError.sourceUnsafe
        }
        let beforeData = try Data(contentsOf: backupCandidates[0])
        let currentSource = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        let afterData = try Data(contentsOf: currentSource)
        let parentUUID = try SafariPlistRoundTripInspector.standardBookmarksBarUUID(data: beforeData)
        let verification: SafariPlistAppendVerificationReport
        do {
            verification = try SafariPlistRoundTripInspector.verifySingleAppend(
                beforeData: beforeData,
                afterData: afterData,
                parentUUID: parentUUID,
                fixtureUUID: fixtureUUID
            )
        } catch {
            let diagnostics = try SafariPlistRoundTripInspector.replacementDiagnostics(
                beforeData: beforeData,
                afterData: afterData,
                fixtureUUID: fixtureUUID
            )
            for diagnostic in diagnostics {
                print(
                    "Safari replacement diagnostic: type=\(diagnostic.nodeType) " +
                    "titleEqual=\(diagnostic.titleEqual) parentEqual=\(diagnostic.parentEqual) " +
                    "childCounts=\(diagnostic.beforeChildCount)/\(diagnostic.afterChildCount) " +
                    "uuidStrippedChangedKeys=\(diagnostic.uuidStrippedChangedKeys.joined(separator: ",")) " +
                    "adapterExposed=\(diagnostic.adapterExposedBefore)/\(diagnostic.adapterExposedAfter)"
                )
            }
            let changedNodes = try SafariPlistRoundTripInspector.changedUntouchedDiagnostics(
                beforeData: beforeData,
                afterData: afterData,
                parentUUID: parentUUID
            )
            for diagnostic in changedNodes {
                print(
                    "Safari changed-node diagnostic: type=\(diagnostic.nodeType) " +
                    "changedKeys=\(diagnostic.changedKeys.joined(separator: ",")) " +
                    "adapterExposed=\(diagnostic.adapterExposedBefore)/\(diagnostic.adapterExposedAfter)"
                )
            }
            let snapshotDiff = try SafariPlistRoundTripInspector.snapshotDiffDiagnostic(
                beforeData: beforeData,
                afterData: afterData
            )
            print(
                "Safari snapshot-count diagnostic: bookmarks=\(snapshotDiff.beforeBookmarkCount)/" +
                "\(snapshotDiff.afterBookmarkCount) readingList=\(snapshotDiff.beforeReadingListCount)/" +
                "\(snapshotDiff.afterReadingListCount) missingBookmarks=\(snapshotDiff.missingBookmarkCount) " +
                "missingReadingList=\(snapshotDiff.missingReadingListCount) " +
                "missingInternal=\(snapshotDiff.missingInternalCount)"
            )
            throw error
        }
        let parsed = try SafariBookmarksParser.parse(data: afterData)
        #expect(parsed.bookmarks.filter { $0.url == fixtureURL }.count == 1)
        print(
            "Safari live readback audit passed: sessionID=\(sessionID.lowercased()) " +
            "addedNodes=\(verification.addedNodeCount) " +
            "untouchedSubtrees=\(verification.untouchedNodeCount) " +
            "changedAncestors=\(verification.changedAncestorCount) " +
            "fixtureParentMatched=\(verification.fixtureParentMatched) " +
            "volatileInternalUUIDReplacements=\(verification.volatileInternalUUIDReplacements) " +
            "parserMatches=1"
        )
    }

    private func syntheticPlistData() throws -> Data {
        let first: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": "FIRST-UUID",
            "URLString": "https://example.com/first",
            "URIDictionary": ["title": "First"],
            "UnknownData": Data([0x00, 0x7f, 0xff]),
            "UnknownDate": Date(timeIntervalSince1970: 1_234_567),
            "UnknownNumber": NSNumber(value: 42)
        ]
        let second: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "WebBookmarkUUID": "SECOND-UUID",
            "URLString": "https://example.com/second",
            "URIDictionary": ["title": "Second"],
            "UnknownNested": ["enabled": true, "values": [1, 2, 3]]
        ]
        let root: [String: Any] = [
            "WebBookmarkFileVersion": 1,
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkUUID": "ROOT-UUID",
            "Title": "Bookmarks",
            "Children": [first, second],
            "UnknownRoot": ["bytes": Data("opaque".utf8)]
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private func rootProxyReplacementData(
        rootUUID: String,
        proxyUUID: String,
        syncValue: String,
        includeFixture: Bool,
        exposeReplacementList: Bool = false
    ) throws -> Data {
        let proxy: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeProxy",
            "WebBookmarkUUID": proxyUUID,
            "Title": "InternalProxy"
        ]
        var barChildren: [[String: Any]] = []
        if includeFixture {
            barChildren.append([
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "WebBookmarkUUID": "FIXTURE-UUID",
                "URLString": "https://example.com/safari-fixture",
                "URIDictionary": ["title": "Fixture"]
            ])
        }
        let bar: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeList",
            "WebBookmarkUUID": "BOOKMARKS-BAR-UUID",
            "Title": "BookmarksBar",
            "Children": barChildren
        ]
        let root: [String: Any]
        if exposeReplacementList {
            let visible: [String: Any] = [
                "WebBookmarkType": "WebBookmarkTypeList",
                "WebBookmarkUUID": rootUUID,
                "Title": "Visible Folder",
                "Sync": ["value": syncValue],
                "Children": [proxy]
            ]
            root = [
                "WebBookmarkFileVersion": 1,
                "WebBookmarkType": "WebBookmarkTypeList",
                "WebBookmarkUUID": "STABLE-ROOT",
                "Title": "Bookmarks",
                "Children": [visible, bar]
            ]
        } else {
            root = [
                "WebBookmarkFileVersion": 1,
                "WebBookmarkType": "WebBookmarkTypeList",
                "WebBookmarkUUID": rootUUID,
                "Title": "Bookmarks",
                "Sync": ["value": syncValue],
                "Children": [proxy, bar]
            ]
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    private func disposableMutation(from data: Data) throws -> SafariPlistMutationSimulationReport {
        try SafariPlistRoundTripInspector.simulateAppendBookmark(
            data: data,
            parentUUID: "ROOT-UUID",
            bookmark: [
                "WebBookmarkType": "WebBookmarkTypeLeaf",
                "WebBookmarkUUID": "DISPOSABLE-UUID",
                "URLString": "https://example.com/disposable",
                "URIDictionary": ["title": "Disposable"]
            ]
        )
    }

    private func testSafetyGate() -> SafariPlistMutationSafetyGate {
        SafariPlistMutationSafetyGate(
            safariRunning: { false },
            plistHasOpenHandles: { _ in false },
            pause: { _ in }
        )
    }

    private func privateTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mpia-safari-feasibility-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func posixMode(_ url: URL) -> UInt16 {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return 0 }
        return UInt16(value.st_mode & 0o7777)
    }

}
