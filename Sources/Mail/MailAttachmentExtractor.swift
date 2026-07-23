import Foundation

public struct MailAttachment: Equatable, Sendable {
    public let filename: String
    public let contentType: String
    public let data: Data
}

public struct MailAttachmentExtractor: Sendable {
    public static let maximumAttachments = 64
    public static let maximumAttachmentBytes = 20 * 1_024 * 1_024

    public init() {}

    public func extract(_ rfc822: Data) throws -> [MailAttachment] {
        guard let root = splitHeadersAndBody(rfc822) else { throw MailStoreError.emlxMalformed }
        var visited = 0
        return try collect(headers: root.headers, body: root.body, depth: 0, visited: &visited)
    }

    private func collect(headers: [String: String], body: Data, depth: Int, visited: inout Int) throws -> [MailAttachment] {
        guard depth < 8 else { throw MailStoreError.emlxMalformed }
        visited += 1
        guard visited <= 1_024 else { throw MailStoreError.emlxMalformed }
        let contentType = parseStructuredHeader(headers["content-type"] ?? "text/plain")
        let disposition = parseStructuredHeader(headers["content-disposition"] ?? "")
        if isAttachment(contentType: contentType, disposition: disposition, headers: headers) {
            guard let filename = filename(contentType: contentType, disposition: disposition) else {
                throw MailStoreError.emlxMalformed
            }
            let data = decode(body, encoding: headers["content-transfer-encoding"] ?? "7bit")
            guard data.count <= Self.maximumAttachmentBytes else { throw MailStoreError.contentTooLarge }
            return [MailAttachment(filename: filename, contentType: contentType.value, data: data)]
        }
        guard contentType.value.hasPrefix("multipart/") else { return [] }
        guard let boundary = contentType.parameters["boundary"], !boundary.isEmpty else { throw MailStoreError.emlxMalformed }
        var result: [MailAttachment] = []
        for child in splitMultipart(body, boundary: boundary) {
            guard let parsed = splitHeadersAndBody(child) else { continue }
            result.append(contentsOf: try collect(headers: parsed.headers, body: parsed.body, depth: depth + 1, visited: &visited))
            guard result.count <= Self.maximumAttachments else { throw MailStoreError.emlxMalformed }
        }
        return result
    }

    private func isAttachment(contentType: StructuredHeader, disposition: StructuredHeader, headers: [String: String]) -> Bool {
        if disposition.value == "attachment" { return true }
        if disposition.parameters.keys.contains(where: { $0 == "filename" || $0.hasPrefix("filename*") }) { return true }
        if contentType.parameters.keys.contains(where: { $0 == "name" || $0.hasPrefix("name*") }) { return true }
        return disposition.value == "inline" && contentType.value != "text/plain" && contentType.value != "text/html" && headers["content-id"]?.isEmpty == false
    }

    private func filename(contentType: StructuredHeader, disposition: StructuredHeader) -> String? {
        let raw = disposition.parameters["filename"] ?? disposition.parameters["filename*"] ?? contentType.parameters["name"] ?? contentType.parameters["name*"]
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let marker = value.range(of: "''") { value = String(value[marker.upperBound...]) }
        return value.removingPercentEncoding ?? value
    }

    private func decode(_ body: Data, encoding: String) -> Data {
        switch encoding.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "base64": return Data(base64Encoded: Data(body.filter { !$0.isSpaceOrNewline }), options: [.ignoreUnknownCharacters]) ?? Data()
        case "quoted-printable": return decodeQuotedPrintable(body)
        default: return body
        }
    }

    private func decodeQuotedPrintable(_ body: Data) -> Data {
        var result = Data(); var index = body.startIndex
        while index < body.endIndex {
            if body[index] == 0x3D, body.index(index, offsetBy: 2, limitedBy: body.endIndex) != nil {
                let next = body.index(after: index); let end = body.index(next, offsetBy: 2)
                if body[next] == 0x0D || body[next] == 0x0A { index = end; continue }
                if let value = UInt8(String(decoding: body[next..<end], as: UTF8.self), radix: 16) { result.append(value); index = end; continue }
            }
            result.append(body[index]); index = body.index(after: index)
        }
        return result
    }

    private typealias StructuredHeader = (value: String, parameters: [String: String])

    private func parseStructuredHeader(_ value: String) -> StructuredHeader {
        var pieces: [String] = []; var current = ""; var quoted = false
        for character in value {
            if character == "\"" { quoted.toggle() }
            else if character == ";" && !quoted { pieces.append(current); current = "" }
            else { current.append(character) }
        }
        pieces.append(current)
        let primary = pieces.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        var parameters: [String: String] = [:]
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let name = piece[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var parameter = piece[piece.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if parameter.count >= 2, parameter.first == "\"", parameter.last == "\"" { parameter.removeFirst(); parameter.removeLast() }
            parameters[name] = parameter
        }
        return (primary, parameters)
    }

    private func splitHeadersAndBody(_ data: Data) -> (headers: [String: String], body: Data)? {
        let marker = Data([13, 10, 13, 10]); let fallback = Data([10, 10])
        let range = data.range(of: marker) ?? data.range(of: fallback)
        guard let range else { return nil }
        let headerData = Data(data[..<range.lowerBound]); let bodyStart = range.upperBound
        let text = String(data: headerData, encoding: .utf8) ?? String(data: headerData, encoding: .isoLatin1) ?? ""
        var headers: [String: String] = [:]; var last: String?
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), let last { headers[last]? += " " + line.trimmingCharacters(in: .whitespaces); continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased(); headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines); last = key
        }
        return (headers, Data(data[bodyStart...]))
    }

    private func splitMultipart(_ data: Data, boundary: String) -> [Data] {
        let marker = Data(("--" + boundary).utf8); guard !marker.isEmpty else { return [] }
        var ranges: [(start: Data.Index, contentStart: Data.Index, closing: Bool)] = []; var search = data.startIndex
        while search < data.endIndex, let range = data.range(of: marker, in: search..<data.endIndex) {
            let startsLine = range.lowerBound == data.startIndex || data[data.index(before: range.lowerBound)] == 10
            if startsLine { var after = range.upperBound; let closing = after + 1 < data.endIndex && data[after] == 45 && data[after + 1] == 45; while after < data.endIndex && data[after] != 10 { after = data.index(after: after) }; if after < data.endIndex { after = data.index(after: after) }; ranges.append((range.lowerBound, after, closing)); if closing { break } }
            search = range.upperBound
        }
        return ranges.indices.compactMap { index in guard !ranges[index].closing, index + 1 < ranges.count else { return nil }; let start = ranges[index].contentStart; var end = ranges[index + 1].start; while end > start && (data[data.index(before: end)] == 10 || data[data.index(before: end)] == 13) { end = data.index(before: end) }; return end > start ? Data(data[start..<end]) : nil }
    }
}

private extension UInt8 {
    var isSpaceOrNewline: Bool { self == 9 || self == 10 || self == 13 || self == 32 }
}
