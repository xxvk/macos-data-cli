import Contacts
import Core
import Foundation

/// Contacts.framework access will be implemented here for version 0.1.
public final class ContactsStore: @unchecked Sendable {
    private let store: CNContactStore
    private let permission: ContactsAccessProviding

    public init(store: CNContactStore = CNContactStore(), permission: ContactsAccessProviding = ContactsPermission()) {
        self.store = store
        self.permission = permission
    }

    public func count() throws -> Int {
        switch permission.status {
        case .authorized, .limited: break
        case .notDetermined: throw ContactsError.permissionRequired
        case .denied: throw ContactsError.permissionDenied
        case .restricted: throw ContactsError.permissionRestricted
        }

        var count = 0
        do {
            let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            try store.enumerateContacts(with: request) { _, _ in count += 1 }
            return count
        } catch {
            throw ContactsError.readFailed(error.localizedDescription)
        }
    }

    public func icloudContainer() throws -> CNContainer {
        try requireAccess()
        do {
            let containers = try store.containers(matching: nil)
            guard let container = containers.first(where: { $0.name.caseInsensitiveCompare("iCloud") == .orderedSame }) else {
                throw ContactsError.icloudContainerNotFound
            }
            return container
        } catch let error as ContactsError { throw error }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func list() throws -> [ContactPayload] {
        switch permission.status {
        case .authorized, .limited: break
        case .notDetermined: throw ContactsError.permissionRequired
        case .denied: throw ContactsError.permissionDenied
        case .restricted: throw ContactsError.permissionRestricted
        }

        let mapper = ContactsMapper()
        var contacts: [ContactPayload] = []
        do {
            let request = CNContactFetchRequest(keysToFetch: [
                CNContactTypeKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactDepartmentNameKey as CNKeyDescriptor,
                CNContactJobTitleKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactUrlAddressesKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor
            ])
            try store.enumerateContacts(with: request) { contact, _ in
                contacts.append(mapper.map(contact))
            }
            return contacts
        } catch {
            throw ContactsError.readFailed(error.localizedDescription)
        }
    }

    public func get(externalID: String) throws -> ContactPayload {
        let matches = try list().filter { $0.externalID == externalID }
        switch matches.count {
        case 0: throw ContactsQueryError.notFound
        case 1: return matches[0]
        default: throw ContactsQueryError.ambiguous(matches.count)
        }
    }

    public func query(_ query: ContactQuerySet) throws -> [ContactPayload] {
        let matcher = ContactQueryMatcher()
        return try list().filter { matcher.matches($0, query: query) }
    }

    public func create(_ payload: ContactPayload) throws {
        try requireAccess()
        guard let externalID = payload.externalID, !externalID.isEmpty else {
            throw ContactsError.invalidInput("external_id is required")
        }
        if (try? get(externalID: externalID)) != nil {
            throw ContactsError.duplicateExternalID(externalID)
        }

        let request = CNSaveRequest()
        request.add(ContactsMapper().makeMutableContact(from: payload), toContainerWithIdentifier: try icloudContainer().identifier)
        do {
            try store.execute(request)
        } catch {
            throw ContactsError.readFailed(error.localizedDescription)
        }
    }

    public func update(externalID: String, with payload: ContactPayload) throws {
        try requireAccess()
        let contact = try findMutableContact(externalID: externalID)
        try ContactsMapper().update(contact, from: payload, preservingExternalID: externalID)
        let request = CNSaveRequest()
        request.update(contact)
        do { try store.execute(request) }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func update(externalID: String, with patch: ContactPatch) throws {
        try requireAccess(); let contact = try findMutableContact(externalID: externalID); try ContactsMapper().update(contact, from: patch, preservingExternalID: externalID); let request = CNSaveRequest(); request.update(contact); do { try store.execute(request) } catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func migrateExternalID(from oldID: String, to newID: String) throws {
        try requireAccess()
        guard !oldID.isEmpty, !newID.isEmpty else { throw ContactsError.invalidInput("external IDs must not be empty") }
        guard oldID != newID else { throw ContactsError.invalidInput("old and new external_id must differ") }
        if (try? get(externalID: newID)) != nil { throw ContactsError.duplicateExternalID(newID) }
        let contact = try findMutableContact(externalID: oldID)
        try ContactsMapper().migrateExternalID(on: contact, from: oldID, to: newID)
        let request = CNSaveRequest()
        request.update(contact)
        do { try store.execute(request) }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func updateImage(externalID: String, data: Data) throws {
        try requireAccess()
        let processed = try ContactImageProcessor().process(data)
        let contact = try findMutableContact(externalID: externalID)
        ContactsMapper().setImageData(processed.data, on: contact)
        let request = CNSaveRequest()
        request.update(contact)
        do { try store.execute(request) }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func delete(externalID: String) throws {
        try requireAccess()
        let contact = try findMutableContact(externalID: externalID)
        let request = CNSaveRequest()
        request.delete(contact)
        do { try store.execute(request) }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    private func requireAccess() throws {
        switch permission.status {
        case .authorized, .limited: break
        case .notDetermined: throw ContactsError.permissionRequired
        case .denied: throw ContactsError.permissionDenied
        case .restricted: throw ContactsError.permissionRestricted
        }
    }

    private func findMutableContact(externalID: String) throws -> CNMutableContact {
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey, CNContactTypeKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactUrlAddressesKey, CNContactPostalAddressesKey, CNContactImageDataKey] as [CNKeyDescriptor]
        var matches: [CNMutableContact] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                if ContactsMapper().map(contact).externalID == externalID { matches.append(contact.mutableCopy() as! CNMutableContact) }
            }
        } catch { throw ContactsError.readFailed(error.localizedDescription) }
        switch matches.count {
        case 0: throw ContactsQueryError.notFound
        case 1: return matches[0]
        default: throw ContactsQueryError.ambiguous(matches.count)
        }
    }
}
