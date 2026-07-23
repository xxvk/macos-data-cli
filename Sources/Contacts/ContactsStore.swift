import Contacts
import Core
import Foundation

/// Contacts.framework access will be implemented here for version 0.1.
public final class ContactsStore: @unchecked Sendable {
    private let store: CNContactStore?
    private let permission: ContactsAccessProviding
    private let containerSelector: String?

    public init(store: CNContactStore? = nil, permission: ContactsAccessProviding = ContactsPermission(), containerSelector: String? = nil) {
        self.store = store
        self.permission = permission
        self.containerSelector = containerSelector
    }

    public func containerDescriptions() throws -> [ContactContainer] {
        try requireAccess()
        do {
            return try contactStore.containers(matching: nil).map(Self.describe)
        } catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func selectedContainerDescription() throws -> ContactContainer {
        try requireAccess()
        return Self.describe(try selectedContainer())
    }

    public func count() throws -> Int {
        switch permission.status {
        case .authorized, .limited: break
        case .notDetermined: throw ContactsError.permissionRequired
        case .denied: throw ContactsError.permissionDenied
        case .restricted: throw ContactsError.permissionRestricted
        }

        let container = try selectedContainer()
        var count = 0
        do {
            let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
            try contactStore.enumerateContacts(with: request) { _, _ in count += 1 }
            return count
        } catch {
            throw ContactsError.readFailed(error.localizedDescription)
        }
    }

    public func icloudContainer() throws -> CNContainer {
        try requireAccess()
        let container = try selectedContainer()
        guard container.type == .cardDAV,
              container.name.caseInsensitiveCompare("iCloud") == .orderedSame else {
            throw ContactsError.icloudContainerNotFound
        }
        return container
    }

    public func list() throws -> [ContactPayload] {
        switch permission.status {
        case .authorized, .limited: break
        case .notDetermined: throw ContactsError.permissionRequired
        case .denied: throw ContactsError.permissionDenied
        case .restricted: throw ContactsError.permissionRestricted
        }

        let mapper = ContactsMapper()
        let container = try selectedContainer()
        var contacts: [ContactPayload] = []
        do {
            let request = CNContactFetchRequest(keysToFetch: [
                CNContactTypeKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneticGivenNameKey as CNKeyDescriptor,
                CNContactPhoneticFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactDepartmentNameKey as CNKeyDescriptor,
                CNContactJobTitleKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactUrlAddressesKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactImageDataAvailableKey as CNKeyDescriptor
            ])
            request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)
            try contactStore.enumerateContacts(with: request) { contact, _ in
                contacts.append(mapper.map(contact))
            }
            return contacts
        } catch {
            throw ContactsError.readFailed(error.localizedDescription)
        }
    }

    public func listPage(limit: Int = Pagination.defaultLimit, cursor: String? = nil) throws -> PagedResult<ContactPayload> {
        do {
            return try Pagination.page(items: list(), limit: limit, cursor: cursor, prefix: "ctcur_")
        } catch PaginationError.invalidLimit {
            throw ContactsQueryError.invalidLimit
        } catch PaginationError.invalidCursor {
            throw ContactsQueryError.invalidCursor
        }
    }

    public func get(externalID: String) throws -> ContactPayload {
        let matches = try list().filter { $0.externalID == externalID }
        return try ContactMatchResolver.requireExactlyOne(matches)
    }

    public func query(_ query: ContactQuerySet) throws -> [ContactPayload] {
        let matcher = ContactQueryMatcher()
        return try list().filter { matcher.matches($0, query: query) }
    }

    public func queryPage(_ querySet: ContactQuerySet, limit: Int = Pagination.defaultLimit, cursor: String? = nil) throws -> PagedResult<ContactPayload> {
        do {
            return try Pagination.page(items: query(querySet), limit: limit, cursor: cursor, prefix: "ctqcur_")
        } catch PaginationError.invalidLimit {
            throw ContactsQueryError.invalidLimit
        } catch PaginationError.invalidCursor {
            throw ContactsQueryError.invalidCursor
        }
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
        request.add(ContactsMapper().makeMutableContact(from: payload), toContainerWithIdentifier: try selectedContainer().identifier)
        do {
            try contactStore.execute(request)
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
        do { try contactStore.execute(request) }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func update(externalID: String, with patch: ContactPatch) throws {
        try requireAccess(); let contact = try findMutableContact(externalID: externalID); try ContactsMapper().update(contact, from: patch, preservingExternalID: externalID); let request = CNSaveRequest(); request.update(contact); do { try contactStore.execute(request) } catch { throw ContactsError.readFailed(error.localizedDescription) }
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
        do { try contactStore.execute(request) }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    public func updateImage(externalID: String, data: Data) throws -> AvatarWriteVerification {
        DiagnosticLogger.record(code: "CONTACT_IMAGE_START", message: "external_id=\(externalID) inputBytes=\(data.count)")
        try requireAccess()
        DiagnosticLogger.record(code: "CONTACT_IMAGE_PERMISSION_OK", message: "external_id=\(externalID)")
        let processed = try ContactImageProcessor().process(data)
        DiagnosticLogger.record(code: "CONTACT_IMAGE_PROCESSED", message: "external_id=\(externalID) outputBytes=\(processed.data.count) width=\(processed.width) height=\(processed.height)")
        let identifier = try findContactIdentifier(externalID: externalID)
        DiagnosticLogger.record(code: "CONTACT_IMAGE_IDENTIFIER_FOUND", message: "external_id=\(externalID) identifierLength=\(identifier.count)")
        // Fetch every writable contact field needed by CNSaveRequest.update,
        // but omit thumbnail/availability fields which can fault on iCloud records.
        let imageKeys: [CNKeyDescriptor] = [
            CNContactIdentifierKey,
            CNContactTypeKey,
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactPhoneticGivenNameKey,
            CNContactPhoneticFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactDepartmentNameKey,
            CNContactJobTitleKey,
            CNContactEmailAddressesKey,
            CNContactPhoneNumbersKey,
            CNContactUrlAddressesKey,
            CNContactPostalAddressesKey,
            CNContactImageDataKey
        ] as [CNKeyDescriptor]
        let contact: CNMutableContact
        do {
            DiagnosticLogger.record(code: "CONTACT_IMAGE_FETCH_START", message: "external_id=\(externalID) keyCount=\(imageKeys.count) includesImageData=true includesThumbnail=false includesAvailability=false")
            // Fetch the specific record through a predicate rather than using a
            // unified aggregate as the mutable object for the write.
            let request = CNContactFetchRequest(keysToFetch: imageKeys)
            request.unifyResults = false
            request.predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
            var fetched: CNMutableContact?
            try contactStore.enumerateContacts(with: request) { candidate, _ in
                fetched = candidate.mutableCopy() as? CNMutableContact
            }
            guard let fetched else { throw ContactsQueryError.notFound }
            contact = fetched
            DiagnosticLogger.record(code: "CONTACT_IMAGE_FETCH_OK", message: "external_id=\(externalID) contactType=\(contact.contactType.rawValue) emailCount=\(contact.emailAddresses.count) phoneCount=\(contact.phoneNumbers.count) urlCount=\(contact.urlAddresses.count) postalCount=\(contact.postalAddresses.count) hasImage=\(contact.imageData != nil)")
        } catch {
            DiagnosticLogger.record(code: "CONTACT_IMAGE_FETCH_FAILED", message: "external_id=\(externalID) stage=fetch-image-fields error=\(error.localizedDescription) \(DiagnosticLogger.errorDetails(error)) stack=\(DiagnosticLogger.stackTrace())")
            throw ContactsError.readFailed("Unable to fetch image-capable contact: \(error.localizedDescription)")
        }
        DiagnosticLogger.record(code: "CONTACT_IMAGE_SET_START", message: "external_id=\(externalID)")
        ContactsMapper().setImageData(processed.data, on: contact)
        DiagnosticLogger.record(code: "CONTACT_IMAGE_SET_OK", message: "external_id=\(externalID) imageBytes=\(contact.imageData?.count ?? 0)")
        let request = CNSaveRequest()
        DiagnosticLogger.record(code: "CONTACT_IMAGE_SAVE_REQUEST_CREATED", message: "external_id=\(externalID)")
        request.update(contact)
        DiagnosticLogger.record(code: "CONTACT_IMAGE_SAVE_START", message: "external_id=\(externalID)")
        do { try contactStore.execute(request) }
        catch {
            DiagnosticLogger.record(code: "CONTACT_IMAGE_SAVE_FAILED", message: "external_id=\(externalID) stage=save error=\(error.localizedDescription) \(DiagnosticLogger.errorDetails(error)) stack=\(DiagnosticLogger.stackTrace())")
            if Self.isCoreDataFault134092(error) {
                throw ContactsError.recordNeedsRecreation(externalID)
            }
            throw ContactsError.readFailed(error.localizedDescription)
        }
        DiagnosticLogger.record(code: "CONTACT_IMAGE_SAVE_OK", message: "external_id=\(externalID)")
        do {
            let readBack = try readBackImageData(identifier: identifier)
            if let readBack, !readBack.isEmpty {
                DiagnosticLogger.record(code: "CONTACT_IMAGE_READBACK_CONFIRMED", message: "external_id=\(externalID) readBackBytes=\(readBack.count)")
                return AvatarWriteVerification(status: .readbackConfirmed, saveAccepted: true, requestedBytes: processed.data.count, readBackBytes: readBack.count)
            }
            DiagnosticLogger.record(code: "CONTACT_IMAGE_READBACK_UNKNOWN", message: "external_id=\(externalID) reason=empty-image-data")
            return AvatarWriteVerification(status: .verificationUnknown, saveAccepted: true, requestedBytes: processed.data.count, nextAction: "retry_verification_after_iCloud_sync_or_recreate_after_confirmation")
        } catch {
            DiagnosticLogger.record(code: "CONTACT_IMAGE_READBACK_UNKNOWN", message: "external_id=\(externalID) reason=readback-failed \(DiagnosticLogger.errorDetails(error)) stack=\(DiagnosticLogger.stackTrace())")
            return AvatarWriteVerification(status: .verificationUnknown, saveAccepted: true, requestedBytes: processed.data.count, nextAction: "retry_verification_after_iCloud_sync_or_recreate_after_confirmation")
        }
    }

    public func verifyImage(externalID: String) throws -> AvatarWriteVerification {
        try requireAccess()
        let identifier = try findContactIdentifier(externalID: externalID)
        do {
            // Avoid requesting imageData for records whose lightweight
            // availability flag is false. On some iCloud/CardDAV records,
            // faulting imageData can produce CoreData 134092 even though the
            // Contacts GUI can display a remote avatar.
            guard try readImageDataAvailability(identifier: identifier) else {
                return AvatarWriteVerification(
                    status: .verificationUnknown,
                    saveAccepted: false,
                    requestedBytes: 0,
                    nextAction: "verify_in_contacts_app_or_retry_after_iCloud_sync"
                )
            }
            let imageData = try readBackImageData(identifier: identifier)
            if let imageData, !imageData.isEmpty {
                return AvatarWriteVerification(status: .readbackConfirmed, saveAccepted: false, requestedBytes: 0, readBackBytes: imageData.count)
            }
            return AvatarWriteVerification(status: .notAvailable, saveAccepted: false, requestedBytes: 0)
        } catch {
            DiagnosticLogger.record(code: "CONTACT_IMAGE_VERIFY_UNKNOWN", message: "external_id=\(externalID) reason=readback-failed \(DiagnosticLogger.errorDetails(error)) stack=\(DiagnosticLogger.stackTrace())")
            return AvatarWriteVerification(status: .verificationUnknown, saveAccepted: false, requestedBytes: 0, nextAction: "retry_verification_after_iCloud_sync_or_recreate_after_confirmation")
        }
    }

    public func replaceImage(externalID: String, data: Data) throws -> AvatarWriteVerification {
        try requireAccess()
        let processed = try ContactImageProcessor().process(data)
        let oldContact = try findMutableContact(externalID: externalID)
        let payload = ContactsMapper().map(oldContact)
        let replacement = ContactsMapper().makeMutableContact(from: payload)
        ContactsMapper().setImageData(processed.data, on: replacement)

        let request = CNSaveRequest()
        request.delete(oldContact)
        request.add(replacement, toContainerWithIdentifier: try selectedContainer().identifier)
        do {
            try contactStore.execute(request)
        } catch {
            DiagnosticLogger.record(code: "CONTACT_IMAGE_REPLACE_FAILED", message: "external_id=\(externalID) error=\(error.localizedDescription) \(DiagnosticLogger.errorDetails(error)) stack=\(DiagnosticLogger.stackTrace())")
            throw ContactsError.readFailed(error.localizedDescription)
        }
        DiagnosticLogger.record(code: "CONTACT_IMAGE_REPLACE_SAVED", message: "external_id=\(externalID) bytes=\(processed.data.count)")
        do {
            let verification = try verifyImage(externalID: externalID)
            return verification
        } catch {
            return AvatarWriteVerification(status: .verificationUnknown, saveAccepted: true, requestedBytes: processed.data.count, nextAction: "verify_in_contacts_app_or_retry_after_iCloud_sync")
        }
    }

    private func readImageDataAvailability(identifier: String) throws -> Bool {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = false
        request.predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
        var available = false
        try contactStore.enumerateContacts(with: request) { contact, _ in
            available = contact.imageDataAvailable
        }
        return available
    }

    private func readBackImageData(identifier: String) throws -> Data? {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = false
        request.predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
        var imageData: Data?
        try contactStore.enumerateContacts(with: request) { contact, _ in
            imageData = contact.imageData
        }
        return imageData
    }

    public func delete(externalID: String) throws {
        try requireAccess()
        let contact = try findMutableContact(externalID: externalID)
        let request = CNSaveRequest()
        request.delete(contact)
        do { try contactStore.execute(request) }
        catch { throw ContactsError.readFailed(error.localizedDescription) }
    }

    private var contactStore: CNContactStore {
        store ?? CNContactStore()
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
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey, CNContactTypeKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneticGivenNameKey, CNContactPhoneticFamilyNameKey, CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactUrlAddressesKey, CNContactPostalAddressesKey, CNContactImageDataAvailableKey] as [CNKeyDescriptor]
        var matches: [CNMutableContact] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: try selectedContainer().identifier)
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                if ContactsMapper().map(contact).externalID == externalID { matches.append(contact.mutableCopy() as! CNMutableContact) }
            }
        } catch { throw ContactsError.readFailed(error.localizedDescription) }
        return try ContactMatchResolver.requireExactlyOne(matches)
    }

    private func findContactIdentifier(externalID: String) throws -> String {
        DiagnosticLogger.record(code: "CONTACT_IMAGE_IDENTIFIER_SEARCH_START", message: "external_id=\(externalID) keys=identifier,urlAddresses")
        let keys: [CNKeyDescriptor] = [CNContactIdentifierKey as CNKeyDescriptor, CNContactUrlAddressesKey as CNKeyDescriptor]
        var matches: [String] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: try selectedContainer().identifier)
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                let urls = contact.urlAddresses.map { LabeledValue(label: $0.label, value: $0.value as String) }
                if urls.compactMap(ContactsMapper.externalID(from:)).contains(externalID) { matches.append(contact.identifier) }
            }
        } catch {
            DiagnosticLogger.record(code: "CONTACT_IMAGE_IDENTIFIER_SEARCH_FAILED", message: "external_id=\(externalID) error=\(error.localizedDescription) \(DiagnosticLogger.errorDetails(error))")
            throw ContactsError.readFailed(error.localizedDescription)
        }
        DiagnosticLogger.record(code: "CONTACT_IMAGE_IDENTIFIER_SEARCH_OK", message: "external_id=\(externalID) matches=\(matches.count)")
        return try ContactMatchResolver.requireExactlyOne(matches)
    }

    private func selectedContainer() throws -> CNContainer {
        let containers = try contactStore.containers(matching: nil)
        if let selector = containerSelector, selector.caseInsensitiveCompare("iCloud") != .orderedSame {
            guard let exact = containers.first(where: { $0.identifier == selector }) else {
                throw ContactsError.invalidInput("container not found: \(selector)")
            }
            guard exact.type == .cardDAV && exact.name.caseInsensitiveCompare("iCloud") == .orderedSame else {
                throw ContactsError.invalidInput("only the iCloud Contacts container is supported in 0.1")
            }
            return exact
        }
        let candidates = containers.filter {
            $0.type == .cardDAV && $0.name.caseInsensitiveCompare("iCloud") == .orderedSame
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            if candidates.isEmpty { throw ContactsError.icloudContainerNotFound }
            throw ContactsError.invalidInput("multiple iCloud containers found; specify --container <identifier>")
        }
        return candidate
    }

    private static func describe(_ container: CNContainer) -> ContactContainer {
        ContactContainer(
            name: container.name,
            identifier: container.identifier,
            type: containerTypeName(container.type),
            isICloud: container.type == .cardDAV && container.name.caseInsensitiveCompare("iCloud") == .orderedSame
        )
    }

    private static func containerTypeName(_ type: CNContainerType) -> String {
        switch type {
        case .local: return "local"
        case .exchange: return "exchange"
        case .cardDAV: return "cardDAV"
        case .unassigned: return "unassigned"
        @unknown default: return "unknown"
        }
    }

    private static func isCoreDataFault134092(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 134092 { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSCocoaErrorDomain && underlying.code == 134092
        }
        return false
    }
}
