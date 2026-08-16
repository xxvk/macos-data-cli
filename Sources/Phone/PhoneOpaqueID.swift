import Foundation

/// Opaque identifiers for Phone call history. Raw `Z_PK` and participant
/// handles never leave the adapter; they are encoded behind these opaque tokens
/// (same base64url scheme as `MessagesOpaqueID`).
enum PhoneOpaqueID {
    static func call(primaryKey: Int64) -> String { encode(prefix: "call_", values: [primaryKey]) }
    static func cursor(dateMicros: Int64, primaryKey: Int64) -> String { encode(prefix: "cur_", values: [dateMicros, primaryKey]) }

    static func cursorValues(_ value: String) -> (dateMicros: Int64, primaryKey: Int64)? {
        guard let values = decode(value, prefix: "cur_", count: 2) else { return nil }
        return (values[0], values[1])
    }

    private static func encode(prefix: String, values: [Int64]) -> String {
        var data = Data()
        for value in values {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
        }
        return prefix + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ value: String, prefix: String, count: Int) -> [Int64]? {
        guard value.hasPrefix(prefix) else { return nil }
        var encoded = String(value.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), data.count == count * MemoryLayout<Int64>.size else { return nil }
        return (0..<count).map { index in
            data.withUnsafeBytes { bytes in
                let start = index * MemoryLayout<Int64>.size
                return Int64(bigEndian: bytes.loadUnaligned(fromByteOffset: start, as: Int64.self))
            }
        }
    }
}
