import CryptoKit
import Foundation

enum MailOpaqueID {
    static func account(key: String) -> String {
        let digest = SHA256.hash(data: Data(("mail-account-v1:" + key).utf8))
        return "acct_" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func mailbox(rowID: Int64) -> String { encode(prefix: "mbx_", values: [rowID]) }
    static func message(rowID: Int64) -> String { encode(prefix: "msg_", values: [rowID]) }
    static func cursor(received: Int64, rowID: Int64) -> String { encode(prefix: "cur_", values: [received, rowID]) }
    static func conversation(_ value: Int64) -> String { encode(prefix: "thr_", values: [value]) }
    static func mailAppMailbox(accountKey: String, mailboxPath: String) -> String {
        encode(prefix: "ambx_", values: [token("account:\(accountKey)"), token("mailbox:\(accountKey):\(mailboxPath)")])
    }
    static func mailAppMessage(rowID: Int64, accountKey: String, mailboxPath: String) -> String {
        encode(prefix: "appmsg_", values: [rowID, token("account:\(accountKey)"), token("mailbox:\(accountKey):\(mailboxPath)")])
    }

    static func mailboxRowID(_ value: String) -> Int64? { decode(value, prefix: "mbx_", count: 1)?.first }
    static func messageRowID(_ value: String) -> Int64? { decode(value, prefix: "msg_", count: 1)?.first }
    static func cursorValues(_ value: String) -> (Int64, Int64)? {
        guard let values = decode(value, prefix: "cur_", count: 2) else { return nil }
        return (values[0], values[1])
    }
    static func mailAppMessageValues(_ value: String) -> (rowID: Int64, accountToken: Int64, mailboxToken: Int64)? {
        guard let values = decode(value, prefix: "appmsg_", count: 3), values[0] > 0 else { return nil }
        return (values[0], values[1], values[2])
    }
    static func matchesMailAppTokens(accountKey: String, mailboxPath: String, accountToken: Int64, mailboxToken: Int64) -> Bool {
        token("account:\(accountKey)") == accountToken && token("mailbox:\(accountKey):\(mailboxPath)") == mailboxToken
    }

    private static func token(_ value: String) -> Int64 {
        let digest = SHA256.hash(data: Data(("mail-app-opaque-v1:" + value).utf8))
        return digest.withUnsafeBytes { bytes in
            Int64(bitPattern: UInt64(bigEndian: bytes.loadUnaligned(as: UInt64.self)))
        }
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
