import Foundation

public struct MailExtractedText: Equatable, Sendable {
    public let text: String?
    public let truncated: Bool
}

public struct MailTextExtractor: Sendable {
    public static let maximumTextBytes = 2 * 1_024 * 1_024
    private static let maximumMultipartDepth = 8

    public init() {}

    public func extract(from rfc822: Data) throws -> MailExtractedText {
        guard let top = splitHeadersAndBody(rfc822) else {
            return MailExtractedText(text: nil, truncated: false)
        }
        var plain: String?
        var html: String?
        try collectText(body: top.body, headers: top.headers, depth: 0, plain: &plain, html: &html)
        let selected = plain ?? html.map(sanitizeHTML)
        guard let selected else { return MailExtractedText(text: nil, truncated: false) }
        let bytes = Data(selected.utf8)
        guard bytes.count > Self.maximumTextBytes else {
            return MailExtractedText(text: selected, truncated: false)
        }
        return MailExtractedText(
            text: String(decoding: bytes.prefix(Self.maximumTextBytes), as: UTF8.self),
            truncated: true
        )
    }

    private func collectText(
        body: Data,
        headers: [String: String],
        depth: Int,
        plain: inout String?,
        html: inout String?
    ) throws {
        guard depth < Self.maximumMultipartDepth else { throw MailStoreError.emlxMalformed }
        let contentType = parseStructuredHeader(headers["content-type"] ?? "text/plain")
        if contentType.value.hasPrefix("multipart/") {
            guard let boundary = contentType.parameters["boundary"], !boundary.isEmpty else {
                throw MailStoreError.emlxMalformed
            }
            let children = splitMultipart(body, boundary: boundary)
            guard !children.isEmpty else { throw MailStoreError.emlxMalformed }
            for child in children {
                guard let parsed = splitHeadersAndBody(child) else { continue }
                try collectText(
                    body: parsed.body,
                    headers: parsed.headers,
                    depth: depth + 1,
                    plain: &plain,
                    html: &html
                )
                if plain != nil && html != nil { break }
            }
            return
        }

        let disposition = parseStructuredHeader(headers["content-disposition"] ?? "")
        guard disposition.value != "attachment" else { return }
        guard contentType.value == "text/plain" || contentType.value == "text/html" else { return }
        let decoded = decodeTransferEncoding(body, encoding: headers["content-transfer-encoding"] ?? "7bit")
        guard let text = decodeText(decoded, charset: contentType.parameters["charset"]) else { return }
        if contentType.value == "text/plain", plain == nil {
            plain = text
        } else if contentType.value == "text/html", html == nil {
            html = text
        }
    }

    private func splitHeadersAndBody(_ data: Data) -> (headers: [String: String], body: Data)? {
        guard let split = headerBodySplit(in: data) else { return nil }
        let headerData = Data(data[..<split.headerEnd])
        return (parseHeaders(headerData), Data(data[split.bodyStart...]))
    }

    private func headerBodySplit(in data: Data) -> (headerEnd: Data.Index, bodyStart: Data.Index)? {
        if data.count >= 4 {
            var index = data.startIndex
            while index <= data.endIndex - 4 {
                if data[index] == 0x0D, data[index + 1] == 0x0A,
                   data[index + 2] == 0x0D, data[index + 3] == 0x0A {
                    return (index, index + 4)
                }
                index += 1
            }
        }
        if data.count >= 2 {
            var index = data.startIndex
            while index <= data.endIndex - 2 {
                if data[index] == 0x0A, data[index + 1] == 0x0A {
                    return (index, index + 2)
                }
                index += 1
            }
        }
        return nil
    }

    private func parseHeaders(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return [:]
        }
        var lines: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                lines.append(line)
            }
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if headers[name] == nil { headers[name] = value }
        }
        return headers
    }

    private func parseStructuredHeader(_ value: String) -> (value: String, parameters: [String: String]) {
        var pieces: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for character in value {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quoted {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character == ";", !quoted {
                pieces.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        pieces.append(current)
        let primary = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        var parameters: [String: String] = [:]
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let name = piece[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var parameter = piece[piece.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if parameter.count >= 2, parameter.first == "\"", parameter.last == "\"" {
                parameter.removeFirst()
                parameter.removeLast()
            }
            parameters[name] = parameter
        }
        return (primary, parameters)
    }

    private func splitMultipart(_ data: Data, boundary: String) -> [Data] {
        let marker = Data(("--" + boundary).utf8)
        guard !marker.isEmpty else { return [] }
        var boundaries: [(start: Data.Index, contentStart: Data.Index, closing: Bool)] = []
        var searchStart = data.startIndex
        while searchStart < data.endIndex,
              let range = data.range(of: marker, in: searchStart..<data.endIndex) {
            let startsLine = range.lowerBound == data.startIndex || data[data.index(before: range.lowerBound)] == 0x0A
            if startsLine {
                var after = range.upperBound
                let closing = after + 1 < data.endIndex && data[after] == 0x2D && data[after + 1] == 0x2D
                let validSuffix = closing || after == data.endIndex ||
                    data[after] == 0x0D || data[after] == 0x0A || data[after] == 0x20 || data[after] == 0x09
                guard validSuffix else {
                    searchStart = range.upperBound
                    continue
                }
                while after < data.endIndex, data[after] != 0x0A { after += 1 }
                if after < data.endIndex { after += 1 }
                boundaries.append((range.lowerBound, after, closing))
                if closing { break }
            }
            searchStart = range.upperBound
        }
        var children: [Data] = []
        for index in boundaries.indices {
            guard !boundaries[index].closing, index + 1 < boundaries.count else { continue }
            let start = boundaries[index].contentStart
            var end = boundaries[index + 1].start
            while end > start {
                let byte = data[data.index(before: end)]
                guard byte == 0x0A || byte == 0x0D else { break }
                end = data.index(before: end)
            }
            if end > start { children.append(Data(data[start..<end])) }
        }
        return children
    }

    private func decodeTransferEncoding(_ data: Data, encoding: String) -> Data {
        switch encoding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "base64":
            return Data(base64Encoded: data, options: [.ignoreUnknownCharacters]) ?? data
        case "quoted-printable":
            return decodeQuotedPrintable(data)
        default:
            return data
        }
    }

    private func decodeQuotedPrintable(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var decoded = Data()
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x3D {
                if index + 2 < bytes.count, bytes[index + 1] == 0x0D, bytes[index + 2] == 0x0A {
                    index += 3
                    continue
                }
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count,
                   let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                    decoded.append(high << 4 | low)
                    index += 3
                    continue
                }
            }
            decoded.append(bytes[index])
            index += 1
        }
        return decoded
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    private func decodeText(_ data: Data, charset: String?) -> String? {
        let encoding: String.Encoding
        switch charset?.lowercased() {
        case "iso-8859-1", "latin1": encoding = .isoLatin1
        case "iso-2022-jp": encoding = .iso2022JP
        case "shift_jis", "shift-jis": encoding = .shiftJIS
        case "euc-jp": encoding = .japaneseEUC
        case "utf-16": encoding = .utf16
        case "utf-16le": encoding = .utf16LittleEndian
        case "utf-16be": encoding = .utf16BigEndian
        default: encoding = .utf8
        }
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    private func sanitizeHTML(_ html: String) -> String {
        var text = html
        text = replacingRegex("(?is)<!--.*?-->", in: text, with: " ")
        text = replacingRegex("(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", in: text, with: " ")
        text = replacingRegex("(?i)<(br|/p|/div|/li|/tr|/h[1-6])\\b[^>]*>", in: text, with: "\n")
        text = replacingRegex("(?is)<[^>]+>", in: text, with: " ")
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        entities.forEach { text = text.replacingOccurrences(of: $0.key, with: $0.value) }
        text = replacingRegex("[ \\t]+", in: text, with: " ")
        text = replacingRegex("\\n[ \\t]+", in: text, with: "\n")
        text = replacingRegex("\\n{3,}", in: text, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacingRegex(_ pattern: String, in value: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: replacement)
    }
}
