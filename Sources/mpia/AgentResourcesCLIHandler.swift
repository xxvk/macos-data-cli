import Core
import ContactsAdapter
import CalendarAdapter
import RemindersAdapter
import PhotosAdapter
import NotesAdapter
import ShortcutsAdapter
import SafariAdapter

extension MpiaCLI {
    static func handleAgentResources(
        _ arguments: [String],
        manifest: CommandManifest,
        containerSelector: String?,
        calendarSourceSelector: String?,
        remindersSourceSelector: String?
    ) throws -> Bool {
        switch arguments {
        case ["agent", "manifest"]:
            emitJSONSuccess(manifest)
        case ["agent", "version"]:
            emitJSONSuccess(["version": CLIVersion.current])
        case ["agent", "help"]:
            emitJSONSuccess(["usage": restUsage])
        case ["resources"]:
            let contactsPermission = ContactsPermission()
            let contactsStore = ContactsStore(permission: contactsPermission, containerSelector: containerSelector)
            let calendarPermission = CalendarPermission()
            let calendarStore = CalendarStore(permission: calendarPermission, sourceSelector: calendarSourceSelector)
            let remindersPermission = RemindersPermission()
            let remindersStore = RemindersStore(permission: remindersPermission, sourceSelector: remindersSourceSelector)
            let photosPermission = PhotosPermission()
            let notesPermission = NotesPermissionService()
            let notesStore = NotesStore(permission: notesPermission)
            emitJSONSuccess(makeResourcesResult(
                permission: contactsPermission,
                store: contactsStore,
                calendarPermission: calendarPermission,
                calendarStore: calendarStore,
                remindersPermission: remindersPermission,
                remindersStore: remindersStore,
                photosPermission: photosPermission,
                notesPermission: notesPermission,
                notesStore: notesStore,
                shortcutsPermission: ShortcutsPermissionService(),
                safariPermission: SafariPermissionService()
            ))
        default:
            return false
        }
        return true
    }
}
