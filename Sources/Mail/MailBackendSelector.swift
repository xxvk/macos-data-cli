import Foundation

public enum MailBackendSelection: Equatable, Sendable {
    case sqlite
    case mailApp(fallbackReason: String)
    case unavailable(MailStoreError)
}

public enum MailBackendSelector {
    public static func select(
        report: MailDoctorReport,
        forceMailAppFallback: Bool = false
    ) -> MailBackendSelection {
        if report.fastPathAvailable && !forceMailAppFallback { return .sqlite }
        if report.automation == .available {
            if forceMailAppFallback { return .mailApp(fallbackReason: "developer_forced_mail_app_fallback") }
            if report.fullDiskAccess == .denied { return .mailApp(fallbackReason: "full_disk_access_required") }
            if report.schema.status == .unsupported { return .mailApp(fallbackReason: "mail_schema_unsupported") }
            if report.mailStoreVersion == nil { return .mailApp(fallbackReason: "mail_store_not_found") }
            return .mailApp(fallbackReason: "mail_database_unavailable")
        }
        if report.fullDiskAccess == .denied { return .unavailable(.fullDiskAccessRequired) }
        if report.mailStoreVersion == nil { return .unavailable(.mailStoreNotFound) }
        if report.schema.status == .unsupported { return .unavailable(.schemaUnsupported) }
        return .unavailable(.databaseUnavailable)
    }
}
