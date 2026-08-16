extension CommandRegistry {
    static let communicationSchemas: [String: JSONSchema] = [
        "MessagesRecentItem": .object(description: "One recent message (metadata + bounded, redacted text projection).", properties: [
            "id": .string("Opaque local message ID.", example: .string("msg_8f2c4e")), "service": .string("Message service.", example: .string("iMessage")),
            "isFromMe": .boolean("Whether the message was sent by the local account.", example: .bool(false)), "sentAt": .string("ISO 8601 send timestamp.", example: .string("2026-08-14T09:12:00Z")),
            "conversationId": .string("Opaque conversation ID.", example: .string("chat_5d8e2a")), "text": .string("Bounded, redacted plain-text projection.", example: .string("Projected body text, truncated to 500 chars")),
        ]),
        "MessagesRecentResult": .object(description: "Paginated recent messages.", properties: [
            "items": .array(of: .ref("MessagesRecentItem")), "nextCursor": .string("Opaque cursor for the next page.", example: .string("cur_8f2c4e")),
            "complete": .boolean("Whether the page is complete.", example: .bool(true)), "truncated": .boolean("Whether any projected text was truncated.", example: .bool(false)), "limitations": .array(of: .string("Limitation description.")),
        ]),
        "MessagesPermissionStatus": .object(description: "Messages read permission status.", properties: [
            "readable": .boolean("Whether the Messages store is readable.", example: .bool(true)), "fullDiskAccess": .boolean("Whether Full Disk Access is granted.", example: .bool(true)),
            "schemaFingerprint": .string("Runtime schema fingerprint.", example: .string("8f2c4e")), "limitations": .array(of: .string("Limitation description.")),
        ]),
        "PhoneCallItem": .object(description: "One recent call (metadata only; no counterparty identifier).", properties: [
            "id": .string("Opaque local call ID.", example: .string("call_8f2c4e")), "direction": .string("Call direction.", example: .string("incoming")),
            "kind": .string("Call kind (audio/video).", example: .string("audio")), "answered": .boolean("Whether the call was answered (or connected for outgoing).", example: .bool(false)),
            "missed": .boolean("Whether the call was missed (incoming and unanswered).", example: .bool(true)), "durationSeconds": .number("Call duration in seconds.", example: .number(104.5)),
            "at": .string("ISO 8601 call timestamp.", example: .string("2026-08-14T09:12:00Z")),
        ]),
        "PhoneCallsRecentResult": .object(description: "Paginated recent calls.", properties: [
            "items": .array(of: .ref("PhoneCallItem")), "nextCursor": .string("Opaque cursor for the next page.", example: .string("cur_8f2c4e")),
            "complete": .boolean("Whether the page is complete.", example: .bool(true)), "truncated": .boolean("Whether more results remain.", example: .bool(false)), "limitations": .array(of: .string("Limitation description.")),
        ]),
        "PhoneCallsPermissionStatus": .object(description: "Call History read permission status.", properties: [
            "readable": .boolean("Whether the Call History store is readable.", example: .bool(true)), "fullDiskAccess": .boolean("Whether Full Disk Access is granted.", example: .bool(true)),
            "schemaFingerprint": .string("Runtime schema fingerprint.", example: .string("8f2c4e")), "limitations": .array(of: .string("Limitation description.")),
        ]),
    ]
}
