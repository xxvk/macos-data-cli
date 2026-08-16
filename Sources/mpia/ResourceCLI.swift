import Foundation
import Core
import Contacts
import ContactsAdapter
import MailAdapter
import CalendarAdapter
import RemindersAdapter
import PhotosAdapter
import NotesAdapter
@_spi(ShortcutsFixtureGate) import ShortcutsAdapter
import SafariAdapter
import MessagesAdapter
import PhoneAdapter

extension MpiaCLI {
    enum ValidatedMailStore {
        case sqlite(SQLiteMailStore)
        case mailApp(MailAppMetadataStore)

        func accounts() throws -> MailAccountListResult {
            switch self {
            case .sqlite(let store): MailAccountListResult(accounts: try store.accounts())
            case .mailApp(let store): try store.accounts()
            }
        }

        func mailboxes(accountID: String? = nil) throws -> MailboxListResult {
            switch self {
            case .sqlite(let store): MailboxListResult(mailboxes: try store.mailboxes(accountID: accountID))
            case .mailApp(let store): try store.mailboxes(accountID: accountID)
            }
        }

        func threads(limit: Int) throws -> MailThreadListResult {
            switch self {
            case .sqlite(let store): try store.threads(limit: limit)
            case .mailApp: throw MailStoreError.invalidArgument("Mail threads require the recognized SQLite fast path.")
            }
        }

        func query(_ query: MailQuery) throws -> MailQueryResult {
            switch self {
            case .sqlite(let store): try store.query(query)
            case .mailApp(let store): try store.query(query)
            }
        }

        func searchText(_ text: String, query: MailQuery, resultLimit: Int) throws -> MailTextSearchResult {
            switch self {
            case .sqlite(let store): try store.searchText(text, query: query, resultLimit: resultLimit)
            case .mailApp: throw MailStoreError.invalidArgument("Mail text search requires the recognized SQLite/EMLX fast path; it never falls back to Mail.app.")
            }
        }

        func get(id: String, projection: MailContentProjection) throws -> MailGetResult {
            switch self {
            case .sqlite(let store): try store.get(id: id, projection: projection)
            case .mailApp(let store): try store.get(id: id, projection: projection)
            }
        }

        func rawMessage(id: String) throws -> MailRawMessage {
            switch self {
            case .sqlite(let store): try store.rawMessage(id: id)
            case .mailApp: throw MailStoreError.contentNotCached
            }
        }

        func reveal(id: String) throws -> MailRevealResult {
            switch self {
            case .sqlite(let store): try store.reveal(id: id)
            case .mailApp(let store): try store.reveal(id: id)
            }
        }

        func verifyAttachments(id: String) throws -> MailAttachmentVerificationResult {
            switch self {
            case .sqlite(let store): try store.verifyAttachments(id: id)
            case .mailApp:
                throw MailStoreError.invalidArgument("Attachment verification requires the recognized SQLite/EMLX fast path.")
            }
        }

        func exportAttachments(id: String, directory: URL) throws -> MailAttachmentExportResult {
            switch self {
            case .sqlite(let store): try store.exportAttachments(id: id, to: directory)
            case .mailApp: throw MailStoreError.invalidArgument("Attachment export requires the recognized SQLite/EMLX fast path.")
            }
        }
    }

    static func makeValidatedMailStore() throws -> ValidatedMailStore {
        let report = MailDoctor(databaseProbe: SQLiteMailDatabaseProbe(performQuickCheck: false)).run()
        let forceMailApp = ProcessInfo.processInfo.environment["MPIA_MAIL_FORCE_APP_FALLBACK"] == "1"
        switch MailBackendSelector.select(report: report, forceMailAppFallback: forceMailApp) {
        case .sqlite:
            return .sqlite(SQLiteMailStore(databaseURL: try MailStoreLocator().locate().databaseURL))
        case .mailApp(let reason):
            return .mailApp(MailAppMetadataStore(fallbackReason: reason))
        case .unavailable(let error):
            throw error
        }
    }

    static func makeResourcesResult(
        permission: ContactsPermission,
        store: ContactsStore,
        calendarPermission: CalendarPermission,
        calendarStore: CalendarStore,
        remindersPermission: RemindersPermission,
        remindersStore: RemindersStore,
        photosPermission: PhotosPermission,
        notesPermission: NotesPermissionService,
        notesStore: NotesStore,
        shortcutsPermission: ShortcutsPermissionService,
        safariPermission: SafariPermissionService
    ) -> DataResourcesResult {
        var resources: [DataResource] = []
        var limitations: [String] = []

        switch permission.status {
        case .authorized, .limited:
            do {
                let containers = try store.containerDescriptions()
                let selectedID = try store.selectedContainerDescription().identifier
                resources.append(contentsOf: containers.map { container in
                    ContactsResourceMapper.map(container, selected: container.identifier == selectedID)
                })
            } catch {
                limitations.append("contacts_resource_discovery_failed")
            }
        case .notDetermined:
            limitations.append("contacts_permission_not_determined")
        case .denied:
            limitations.append("contacts_permission_denied")
        case .restricted:
            limitations.append("contacts_permission_restricted")
        }

        do {
            let mailAccounts = try makeValidatedMailStore().accounts()
            resources.append(contentsOf: mailAccounts.accounts.map { account in
                MailResourceMapper.map(account, selected: false)
            })
            limitations.append(contentsOf: mailAccounts.limitations)
            if !mailAccounts.accounts.isEmpty {
                limitations.append("mail_preferred_aim_tech_account_requires_explicit_verification")
            }
        } catch {
            limitations.append("mail_resource_discovery_unavailable")
        }

        switch calendarPermission.status {
        case .fullAccess:
            do {
                let result = try calendarStore.sourceDescriptions()
                resources.append(contentsOf: result.sources.map {
                    CalendarResourceMapper.map($0, selected: $0.identifier == result.selectedSourceID, permission: .available)
                })
            } catch {
                limitations.append("calendar_resource_discovery_failed")
            }
        case .notDetermined:
            limitations.append("calendar_permission_not_determined")
        case .denied:
            limitations.append("calendar_permission_denied")
        case .restricted:
            limitations.append("calendar_permission_restricted")
        case .writeOnly:
            limitations.append("calendar_full_access_required")
        }

        switch remindersPermission.status {
        case .fullAccess:
            do {
                let result = try remindersStore.sourceDescriptions()
                resources.append(contentsOf: result.sources.map {
                    RemindersResourceMapper.map($0, selected: $0.identifier == result.selectedSourceID, permission: .available)
                })
            } catch {
                limitations.append("reminders_resource_discovery_failed")
            }
        case .notDetermined:
            limitations.append("reminders_permission_not_determined")
        case .denied:
            limitations.append("reminders_permission_denied")
        case .restricted:
            limitations.append("reminders_permission_restricted")
        case .writeOnly:
            limitations.append("reminders_full_access_required")
        }
        resources.append(PhotosResourceMapper.map(status: photosPermission.status))
        switch photosPermission.status {
        case .authorized:
            break
        case .limited:
            limitations.append("photos_access_limited")
        case .notDetermined:
            limitations.append("photos_permission_not_determined")
        case .denied:
            limitations.append("photos_permission_denied")
        case .restricted:
            limitations.append("photos_permission_restricted")
        }
        let notesResult = notesPermission.check(requestConsent: false)
        let notesWriteStatus = notesStore.writeAccountStatus()
        resources.append(NotesResourceMapper.map(status: notesResult.access, writable: notesWriteStatus.valid))
        switch notesResult.access {
        case .available:
            if !notesWriteStatus.bound { limitations.append("notes_icloud_write_account_not_bound") }
            else if !notesWriteStatus.valid { limitations.append("notes_icloud_write_account_stale") }
        case .requiresConsent:
            limitations.append("notes_automation_requires_consent")
        case .denied:
            limitations.append("notes_automation_denied")
        case .targetNotRunning:
            limitations.append("notes_app_not_running")
        case .targetUnavailable:
            limitations.append("notes_app_unavailable")
        case .unknown:
            limitations.append("notes_automation_unknown")
        }
        let shortcutsResult = shortcutsPermission.check(requestConsent: false)
        resources.append(ShortcutsResourceMapper.map(status: shortcutsResult.access))
        switch shortcutsResult.access {
        case .available: break
        case .requiresConsent: limitations.append("shortcuts_automation_requires_consent")
        case .denied: limitations.append("shortcuts_automation_denied")
        case .targetNotRunning: limitations.append("shortcuts_events_not_running")
        case .targetUnavailable: limitations.append("shortcuts_events_unavailable")
        case .unknown: limitations.append("shortcuts_automation_unknown")
        }
        let safariResult = safariPermission.check(requestConsent: false)
        resources.append(SafariResourceMapper.map(permission: safariResult))
        if !safariResult.bookmarksReadable { limitations.append("safari_bookmarks_full_disk_access_required") }
        switch safariResult.automation {
        case .available: break
        case .requiresConsent: limitations.append("safari_automation_requires_consent")
        case .denied: limitations.append("safari_automation_denied")
        case .targetNotRunning: limitations.append("safari_not_running")
        case .targetUnavailable: limitations.append("safari_unavailable")
        case .unknown: limitations.append("safari_automation_unknown")
        }
        limitations.append("safari_bookmark_mutation_local_only_requires_safari_quit")
        limitations.append("safari_bookmark_mutation_does_not_sync_to_icloud")

        do {
            let reader = ChatDbReader(databaseURL: try MessagesStoreLocator().locate().databaseURL)
            let status = try reader.permission()
            resources.append(MessagesResourceMapper.map(status: status))
            if !status.readable { limitations.append("messages_full_disk_access_required") }
        } catch {
            limitations.append("messages_resource_discovery_unavailable")
        }

        do {
            let reader = CallHistoryReader(databaseURL: try PhoneStoreLocator().locate().databaseURL)
            let status = try reader.permission()
            resources.append(PhoneResourceMapper.map(status: status))
            if !status.readable { limitations.append("phone_calls_full_disk_access_required") }
        } catch {
            limitations.append("phone_calls_resource_discovery_unavailable")
        }

        return DataResourcesResult(resources: resources, limitations: limitations)
    }

}
