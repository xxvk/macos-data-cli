import Foundation

public enum MailCapabilityStatus: String, Codable, Equatable, Sendable {
    case available
    case unavailable
    case denied
    case notChecked = "not_checked"
}

public enum MailSchemaStatus: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
    case unavailable
}

public enum MailAutomationStatus: String, Codable, Equatable, Sendable {
    case available
    case denied
    case requiresConsent = "requires_consent"
    case targetNotRunning = "target_not_running"
    case targetUnavailable = "target_unavailable"
    case unknown
}

public struct MailSQLiteCapability: Codable, Equatable, Sendable {
    public let status: MailCapabilityStatus
    public let journalMode: String?
    public let quickCheck: String?
    public let walPresent: Bool
    public let shmPresent: Bool
}

public struct MailSchemaCapability: Codable, Equatable, Sendable {
    public let status: MailSchemaStatus
    public let fingerprint: String?
    public let recognition: String?
}

public struct MailDoctorReport: Codable, Equatable, Sendable {
    public let osVersion: String
    public let sdkBaseline: String
    public let mailStoreVersion: String?
    public let fullDiskAccess: MailCapabilityStatus
    public let automation: MailAutomationStatus
    public let sqlite: MailSQLiteCapability
    public let schema: MailSchemaCapability
    public let fastPathAvailable: Bool
    public let limitations: [String]
}

public protocol MailAutomationProbing: Sendable {
    func status() -> MailAutomationStatus
}

public struct MailDoctor {
    private let mailRoot: URL
    private let databaseProbe: any MailDatabaseProbing
    private let automationProbe: any MailAutomationProbing
    private let fileManager: FileManager

    public init(
        mailRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail", isDirectory: true),
        databaseProbe: any MailDatabaseProbing = SQLiteMailDatabaseProbe(),
        automationProbe: any MailAutomationProbing = SystemMailAutomationProbe(),
        fileManager: FileManager = .default
    ) {
        self.mailRoot = mailRoot
        self.databaseProbe = databaseProbe
        self.automationProbe = automationProbe
        self.fileManager = fileManager
    }

    public func run() -> MailDoctorReport {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let automation = automationProbe.status()

        let versions: [(name: String, number: Int)]
        do {
            versions = try fileManager.contentsOfDirectory(
                at: mailRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ).compactMap { url in
                guard let number = Self.mailStoreVersionNumber(url.lastPathComponent) else { return nil }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { return nil }
                return (url.lastPathComponent, number)
            }
        } catch let error as NSError {
            let denied = error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError
            return unavailableReport(
                osVersion: osVersion,
                fullDiskAccess: denied ? .denied : .unavailable,
                automation: automation,
                limitation: denied ? "full_disk_access_required" : "mail_store_not_found"
            )
        }

        guard let selected = versions.max(by: { $0.number < $1.number }) else {
            return unavailableReport(
                osVersion: osVersion,
                fullDiskAccess: .available,
                automation: automation,
                limitation: "mail_store_not_found"
            )
        }

        let databaseURL = mailRoot
            .appendingPathComponent(selected.name, isDirectory: true)
            .appendingPathComponent("MailData", isDirectory: true)
            .appendingPathComponent("Envelope Index")
        let walPresent = fileManager.fileExists(atPath: databaseURL.path + "-wal")
        let shmPresent = fileManager.fileExists(atPath: databaseURL.path + "-shm")

        guard fileManager.isReadableFile(atPath: databaseURL.path) else {
            return MailDoctorReport(
                osVersion: osVersion,
                sdkBaseline: "macOS 26.0",
                mailStoreVersion: selected.name,
                fullDiskAccess: .denied,
                automation: automation,
                sqlite: MailSQLiteCapability(status: .unavailable, journalMode: nil, quickCheck: nil, walPresent: walPresent, shmPresent: shmPresent),
                schema: MailSchemaCapability(status: .unavailable, fingerprint: nil, recognition: nil),
                fastPathAvailable: false,
                limitations: ["full_disk_access_required"]
            )
        }

        let database = databaseProbe.inspect(databaseURL: databaseURL)
        let schemaSupported = selected.name == "V10" && database.requiredSchemaPresent && database.timestampRangeValid
        let quickCheckAccepted = database.quickCheck == "ok" || database.quickCheck == "skipped"
        let sqliteAvailable = database.readable && quickCheckAccepted
        let fastPathAvailable = sqliteAvailable && database.journalMode == "wal" && schemaSupported
        var limitations: [String] = []
        if !database.readable { limitations.append("mail_database_unreadable") }
        if !quickCheckAccepted { limitations.append("mail_database_check_failed") }
        if database.journalMode != "wal" { limitations.append("mail_wal_unavailable") }
        if !schemaSupported { limitations.append("mail_schema_unsupported") }
        if automation != .available { limitations.append("mail_automation_\(automation.rawValue)") }

        return MailDoctorReport(
            osVersion: osVersion,
            sdkBaseline: "macOS 26.0",
            mailStoreVersion: selected.name,
            fullDiskAccess: database.readable ? .available : .denied,
            automation: automation,
            sqlite: MailSQLiteCapability(
                status: sqliteAvailable ? .available : .unavailable,
                journalMode: database.journalMode,
                quickCheck: database.quickCheck,
                walPresent: walPresent,
                shmPresent: shmPresent
            ),
            schema: MailSchemaCapability(
                status: schemaSupported ? .supported : .unsupported,
                fingerprint: database.schemaFingerprint,
                recognition: schemaSupported ? "mail_v10_required_structure_v1" : nil
            ),
            fastPathAvailable: fastPathAvailable,
            limitations: limitations.sorted()
        )
    }

    static func mailStoreVersionNumber(_ name: String) -> Int? {
        guard name.first == "V", name.count > 1 else { return nil }
        return Int(name.dropFirst())
    }

    private func unavailableReport(
        osVersion: String,
        fullDiskAccess: MailCapabilityStatus,
        automation: MailAutomationStatus,
        limitation: String
    ) -> MailDoctorReport {
        MailDoctorReport(
            osVersion: osVersion,
            sdkBaseline: "macOS 26.0",
            mailStoreVersion: nil,
            fullDiskAccess: fullDiskAccess,
            automation: automation,
            sqlite: MailSQLiteCapability(status: .unavailable, journalMode: nil, quickCheck: nil, walPresent: false, shmPresent: false),
            schema: MailSchemaCapability(status: .unavailable, fingerprint: nil, recognition: nil),
            fastPathAvailable: false,
            limitations: [limitation]
        )
    }
}
