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
    static func parsePhotoAlbumArguments(_ arguments: [String]) throws -> PhotoAlbumArguments {
        var result = PhotoAlbumArguments()
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else {
                throw PhotoError.invalidArgument("duplicate albums option")
            }
            guard index + 1 < arguments.count else {
                throw PhotoError.invalidArgument("\(option) requires a value")
            }
            let value = arguments[index + 1]
            switch option {
            case "--kind":
                guard let kind = PhotoAlbumQueryKind(rawValue: value) else {
                    throw PhotoError.invalidArgument("--kind must be user, smart, or all")
                }
                result.kind = kind
            case "--limit":
                guard let limit = Int(value), (1...Pagination.maximumLimit).contains(limit) else {
                    throw PhotoError.invalidLimit
                }
                result.limit = limit
            case "--cursor":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                result.cursor = value
            default:
                throw PhotoError.invalidArgument("unsupported albums option")
            }
            index += 2
        }
        return result
    }

    static func parsePhotoQueryArguments(_ arguments: [String]) throws -> PhotoAssetQuery {
        var start: Date?
        var end: Date?
        var albumID: String?
        var mediaType: PhotoMediaType?
        var favorite: Bool?
        var includeHidden = false
        var includeLocation = false
        var limit = Pagination.defaultLimit
        var cursor: String?
        var seen = Set<String>()
        var index = 0

        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw PhotoError.invalidArgument("duplicate query option") }
            if option == "--include-hidden" || option == "--include-location" {
                if option == "--include-hidden" { includeHidden = true } else { includeLocation = true }
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw PhotoError.invalidArgument("\(option) requires a value") }
            let value = arguments[index + 1]
            switch option {
            case "--start":
                guard let date = ISO8601DateFormatter().date(from: value) else { throw PhotoError.invalidArgument("--start must be ISO 8601") }
                start = date
            case "--end":
                guard let date = ISO8601DateFormatter().date(from: value) else { throw PhotoError.invalidArgument("--end must be ISO 8601") }
                end = date
            case "--album-id":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                albumID = value
            case "--media":
                guard let parsed = PhotoMediaType(rawValue: value) else { throw PhotoError.invalidArgument("--media must be image, video, audio, or unknown") }
                mediaType = parsed
            case "--favorite":
                guard value == "true" || value == "false" else { throw PhotoError.invalidArgument("--favorite must be true or false") }
                favorite = value == "true"
            case "--limit":
                guard let parsed = Int(value), (1...Pagination.maximumLimit).contains(parsed) else { throw PhotoError.invalidLimit }
                limit = parsed
            case "--cursor":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                cursor = value
            default:
                throw PhotoError.invalidArgument("unsupported query option")
            }
            index += 2
        }
        guard let start, let end else { throw PhotoError.invalidArgument("query requires --start and --end") }
        return PhotoAssetQuery(
            start: start,
            end: end,
            albumID: albumID,
            mediaType: mediaType,
            favorite: favorite,
            includeHidden: includeHidden,
            includeLocation: includeLocation,
            limit: limit,
            cursor: cursor
        )
    }

    static func parsePhotoGetArguments(_ arguments: [String]) throws -> PhotoGetArguments {
        var id: String?
        var includeLocation = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw PhotoError.invalidArgument("duplicate get option") }
            if option == "--include-location" {
                includeLocation = true
                index += 1
                continue
            }
            guard option == "--id", index + 1 < arguments.count else { throw PhotoError.invalidArgument("get accepts --id and --include-location") }
            guard !arguments[index + 1].isEmpty else { throw PhotoError.invalidIdentifier }
            id = arguments[index + 1]
            index += 2
        }
        guard let id else { throw PhotoError.invalidArgument("get requires --id") }
        return PhotoGetArguments(id: id, includeLocation: includeLocation)
    }

    static func parsePhotoExportArguments(_ arguments: [String]) throws -> PhotoExportArguments {
        var id: String?
        var output: String?
        var variant = PhotoExportVariant.original
        var allowNetwork = false
        var seen = Set<String>()
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard seen.insert(option).inserted else { throw PhotoError.invalidArgument("duplicate export option") }
            if option == "--allow-network" {
                allowNetwork = true
                index += 1
                continue
            }
            guard index + 1 < arguments.count else { throw PhotoError.invalidArgument("\(option) requires a value") }
            let value = arguments[index + 1]
            switch option {
            case "--id":
                guard !value.isEmpty else { throw PhotoError.invalidIdentifier }
                id = value
            case "--output":
                guard !value.isEmpty, value != "-" else { throw PhotoError.invalidOutput }
                output = value
            case "--variant":
                guard let parsed = PhotoExportVariant(rawValue: value) else {
                    throw PhotoError.invalidArgument("--variant must be original, current, paired-video, or adjustment-data")
                }
                variant = parsed
            default:
                throw PhotoError.invalidArgument("unsupported export option")
            }
            index += 2
        }
        guard let id, let output else { throw PhotoError.invalidArgument("export requires --id and --output") }
        return PhotoExportArguments(
            id: id,
            outputURL: URL(fileURLWithPath: output).standardizedFileURL,
            variant: variant,
            allowNetwork: allowNetwork
        )
    }

    static func emitCalendarJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) { print(text) }
    }

    static func emitRemindersJSONSuccess<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(JSONSuccess(data: value)), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

}
