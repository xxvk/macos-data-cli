import Foundation

enum StrictJSON {
    static func object(_ text: String, maximumBytes: Int) throws -> [String: Any] {
        let data = Data(text.utf8)
        guard !data.isEmpty, data.count <= maximumBytes else { throw RESTCLIError.payloadTooLarge(maximumBytes) }
        var scanner = DuplicateKeyScanner(data: data)
        try scanner.validate()
        let value: Any
        do { value = try JSONSerialization.jsonObject(with: data) }
        catch { throw RESTCLIError.invalidJSON }
        guard let object = value as? [String: Any] else { throw RESTCLIError.jsonObjectRequired }
        return object
    }
}

private struct DuplicateKeyScanner {
    let bytes: [UInt8]
    var index = 0

    init(data: Data) { bytes = Array(data) }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw RESTCLIError.invalidJSON }
    }

    mutating func parseValue() throws {
        skipWhitespace()
        guard index < bytes.count else { throw RESTCLIError.invalidJSON }
        switch bytes[index] {
        case 0x7B: try parseObject()
        case 0x5B: try parseArray()
        case 0x22: _ = try parseString()
        case 0x74: try consume("true")
        case 0x66: try consume("false")
        case 0x6E: try consume("null")
        default: try parseNumber()
        }
    }

    mutating func parseObject() throws {
        index += 1
        skipWhitespace()
        var keys = Set<String>()
        if consumeIf(0x7D) { return }
        while true {
            guard index < bytes.count, bytes[index] == 0x22 else { throw RESTCLIError.invalidJSON }
            let key = try parseString()
            guard keys.insert(key).inserted else { throw RESTCLIError.duplicateJSONKey(key) }
            skipWhitespace()
            guard consumeIf(0x3A) else { throw RESTCLIError.invalidJSON }
            try parseValue()
            skipWhitespace()
            if consumeIf(0x7D) { return }
            guard consumeIf(0x2C) else { throw RESTCLIError.invalidJSON }
            skipWhitespace()
        }
    }

    mutating func parseArray() throws {
        index += 1
        skipWhitespace()
        if consumeIf(0x5D) { return }
        while true {
            try parseValue()
            skipWhitespace()
            if consumeIf(0x5D) { return }
            guard consumeIf(0x2C) else { throw RESTCLIError.invalidJSON }
        }
    }

    mutating func parseString() throws -> String {
        let start = index
        index += 1
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if escaped { escaped = false; continue }
            if byte == 0x5C { escaped = true; continue }
            if byte == 0x22 {
                let data = Data(bytes[start..<index])
                guard let value = try? JSONDecoder().decode(String.self, from: data) else { throw RESTCLIError.invalidJSON }
                return value
            }
            if byte < 0x20 { throw RESTCLIError.invalidJSON }
        }
        throw RESTCLIError.invalidJSON
    }

    mutating func parseNumber() throws {
        let start = index
        while index < bytes.count, ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D].contains(bytes[index]) { index += 1 }
        guard index > start,
              Double(String(decoding: bytes[start..<index], as: UTF8.self)) != nil else { throw RESTCLIError.invalidJSON }
    }

    mutating func consume(_ literal: String) throws {
        let expected = Array(literal.utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index..<(index + expected.count)]) == expected else { throw RESTCLIError.invalidJSON }
        index += expected.count
    }

    mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }
}
