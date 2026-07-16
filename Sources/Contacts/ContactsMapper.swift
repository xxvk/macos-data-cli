import Core
import Contacts
import Foundation

public struct ContactsMapper: Sendable {
    public init() {}

    public func map(_ contact: CNContact) -> ContactPayload {
        let urls = contact.urlAddresses.map { LabeledValue(label: $0.label, value: $0.value as String) }
        return ContactPayload(
            kind: contact.contactType == .organization ? .organization : .person,
            externalID: urls.compactMap(Self.externalID(from:)).first,
            givenName: contact.givenName.nilIfEmpty,
            familyName: contact.familyName.nilIfEmpty,
            organizationName: contact.organizationName.nilIfEmpty,
            department: contact.departmentName.nilIfEmpty,
            jobTitle: contact.jobTitle.nilIfEmpty,
            emails: contact.emailAddresses.map { LabeledValue(label: $0.label, value: $0.value as String) },
            phones: contact.phoneNumbers.map { LabeledValue(label: $0.label, value: $0.value.stringValue) },
            urls: urls,
            addresses: contact.postalAddresses.map {
                let address = $0.value
                return PostalAddress(
                    label: $0.label,
                    street: address.street.nilIfEmpty,
                    city: address.city.nilIfEmpty,
                    state: address.state.nilIfEmpty,
                    postalCode: address.postalCode.nilIfEmpty,
                    country: address.country.nilIfEmpty
                )
            }
        )
    }

    public func makeMutableContact(from payload: ContactPayload) -> CNMutableContact {
        let contact = CNMutableContact()
        contact.contactType = payload.kind == .organization ? .organization : .person
        contact.givenName = payload.givenName ?? ""
        contact.familyName = payload.familyName ?? ""
        contact.organizationName = payload.organizationName ?? ""
        contact.departmentName = payload.department ?? ""
        contact.jobTitle = payload.jobTitle ?? ""
        contact.emailAddresses = payload.emails.map { CNLabeledValue(label: $0.label, value: $0.value as NSString) }
        contact.phoneNumbers = payload.phones.map { CNLabeledValue(label: $0.label, value: CNPhoneNumber(stringValue: $0.value)) }
        var urls = payload.urls
        if let externalID = payload.externalID, !urls.contains(where: { Self.externalID(from: $0) == externalID }) {
            urls.append(LabeledValue(label: "macos-data-cli", value: "x-macos-data://external-id/\(externalID)"))
        }
        contact.urlAddresses = urls.map { CNLabeledValue(label: $0.label, value: $0.value as NSString) }
        contact.postalAddresses = payload.addresses.map {
            let address = CNMutablePostalAddress()
            address.street = $0.street ?? ""
            address.city = $0.city ?? ""
            address.state = $0.state ?? ""
            address.postalCode = $0.postalCode ?? ""
            address.country = $0.country ?? ""
            return CNLabeledValue(label: $0.label, value: address)
        }
        return contact
    }

    public func update(_ contact: CNMutableContact, from payload: ContactPayload, preservingExternalID externalID: String) throws {
        if let requestedID = payload.externalID, requestedID != externalID {
            throw ContactsError.externalIDImmutable
        }
        let replacement = makeMutableContact(from: ContactPayload(
            kind: payload.kind,
            externalID: externalID,
            givenName: payload.givenName,
            familyName: payload.familyName,
            organizationName: payload.organizationName,
            department: payload.department,
            jobTitle: payload.jobTitle,
            emails: payload.emails,
            phones: payload.phones,
            urls: payload.urls.filter { Self.externalID(from: $0) == nil },
            addresses: payload.addresses,
            metadata: payload.metadata
        ))
        contact.contactType = replacement.contactType
        contact.givenName = replacement.givenName
        contact.familyName = replacement.familyName
        contact.organizationName = replacement.organizationName
        contact.departmentName = replacement.departmentName
        contact.jobTitle = replacement.jobTitle
        contact.emailAddresses = replacement.emailAddresses
        contact.phoneNumbers = replacement.phoneNumbers
        contact.urlAddresses = replacement.urlAddresses
        contact.postalAddresses = replacement.postalAddresses
    }

    public func update(_ contact: CNMutableContact, from patch: ContactPatch, preservingExternalID externalID: String) throws {
        if patch.has("externalID"), let requestedID = patch.externalID, requestedID != externalID { throw ContactsError.externalIDImmutable }
        if patch.has("kind"), let kind = patch.kind { contact.contactType = kind == .organization ? .organization : .person }
        if patch.has("givenName") { contact.givenName = patch.givenName ?? "" }
        if patch.has("familyName") { contact.familyName = patch.familyName ?? "" }
        if patch.has("organizationName") { contact.organizationName = patch.organizationName ?? "" }
        if patch.has("department") { contact.departmentName = patch.department ?? "" }
        if patch.has("jobTitle") { contact.jobTitle = patch.jobTitle ?? "" }
        if patch.has("emails") { contact.emailAddresses = (patch.emails ?? []).map { CNLabeledValue(label: $0.label, value: $0.value as NSString) } }
        if patch.has("phones") { contact.phoneNumbers = (patch.phones ?? []).map { CNLabeledValue(label: $0.label, value: CNPhoneNumber(stringValue: $0.value)) } }
        if patch.has("urls") { contact.urlAddresses = (patch.urls ?? []).filter { ContactsMapper.externalID(from: $0) == nil }.map { CNLabeledValue(label: $0.label, value: $0.value as NSString) } + [CNLabeledValue(label: "macos-data-cli", value: "x-macos-data://external-id/\(externalID)" as NSString)] }
        if patch.has("addresses") { contact.postalAddresses = (patch.addresses ?? []).map { p in let a = CNMutablePostalAddress(); a.street = p.street ?? ""; a.city = p.city ?? ""; a.state = p.state ?? ""; a.postalCode = p.postalCode ?? ""; a.country = p.country ?? ""; return CNLabeledValue(label: p.label, value: a) } }
    }

    public func setImageData(_ data: Data, on contact: CNMutableContact) {
        contact.imageData = data
    }

    public static func externalID(from url: LabeledValue) -> String? {
        guard let parsed = URL(string: url.value),
              parsed.scheme == "x-macos-data",
              parsed.host == "external-id" else { return nil }
        let value = parsed.pathComponents.dropFirst().joined(separator: "/")
        return value.isEmpty ? nil : value
    }

    public func migrateExternalID(on contact: CNMutableContact, from oldID: String, to newID: String) throws {
        guard !newID.isEmpty else { throw ContactsError.invalidInput("new external_id must not be empty") }
        var found = false
        contact.urlAddresses = contact.urlAddresses.map { item in
            let value = item.value as String
            guard Self.externalID(from: LabeledValue(label: item.label, value: value)) == oldID else { return item }
            found = true
            return CNLabeledValue(label: item.label, value: "x-macos-data://external-id/\(newID)" as NSString)
        }
        guard found else { throw ContactsQueryError.notFound }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
