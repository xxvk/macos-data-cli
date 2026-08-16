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
    static func handlePhotos(_ arguments: [String]) async throws -> Bool {
        let photosPermission = PhotosPermission()
        let photosStore = PhotosStore(permission: photosPermission)
        switch arguments {
        case ["photos", "permission"]:
            emitJSONSuccess(PhotosPermissionResult(
                access: photosPermission.status.rawValue,
                readable: photosPermission.status.canRead,
                complete: photosPermission.status.complete,
                requested: false
            ))
        case ["photos", "permission", "--request"]:
            let status = await photosPermission.requestReadWriteAccess()
            emitJSONSuccess(PhotosPermissionResult(
                access: status.rawValue,
                readable: status.canRead,
                complete: status.complete,
                requested: true
            ))
            if !status.canRead { Foundation.exit(CLIExitCode.photosFailure.rawValue) }
        case let args where args.count >= 2 && args[0] == "photos" && args[1] == "albums":
            let request = try parsePhotoAlbumArguments(Array(args.dropFirst(2)))
            emitJSONSuccess(try photosStore.albums(kind: request.kind, limit: request.limit, cursor: request.cursor))
        case let args where args.count >= 2 && args[0] == "photos" && args[1] == "query":
            emitPhotosJSONSuccess(try photosStore.query(parsePhotoQueryArguments(Array(args.dropFirst(2)))))
        case let args where args.count >= 2 && args[0] == "photos" && args[1] == "get":
            let request = try parsePhotoGetArguments(Array(args.dropFirst(2)))
            emitPhotosJSONSuccess(try photosStore.get(id: request.id, includeLocation: request.includeLocation))
        case let args where args.count >= 2 && args[0] == "photos" && args[1] == "export":
            let request = try parsePhotoExportArguments(Array(args.dropFirst(2)))
            emitPhotosJSONSuccess(try await photosStore.export(
                id: request.id,
                outputURL: request.outputURL,
                variant: request.variant,
                allowNetwork: request.allowNetwork
            ))
        default: return false
        }
        return true
    }
}
