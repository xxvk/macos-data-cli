import Foundation

public struct MailAttachmentInspection: Equatable, Sendable {
    public let attachmentCount: Int
}

public struct MailAttachmentInspector: Sendable {
    public static let maximumMultipartDepth = 8
    public static let maximumParts = 1_024

    public init() {}

    public func inspect(_ rfc822: Data) throws -> MailAttachmentInspection {
        guard let root = splitHeadersAndBody(rfc822) else {
            throw MailStoreError.emlxMalformed
        }
        var visitedParts = 0
        let count = try countAttachments(
            headers: root.headers,
            body: root.body,
            depth: 0,
            visitedParts: &visitedParts
        )
        return MailAttachmentInspection(attachmentCount: count)
    }

    private func countAttachments(
        headers: [String: String],
        body: Data,
        depth: Int,
        visitedParts: inout Int
    ) throws -> Int {
        guard depth < Self.maximumMultipartDepth else { throw MailStoreError.emlxMalformed }
        visitedParts += 1
        guard visitedParts <= Self.maximumParts else { throw MailStoreError.emlxMalformed }

        let contentType = parseStructuredHeader(headers["content-type"] ?? "text/plain")
        let disposition = parseStructuredHeader(headers["content-disposition"] ?? "")
        if isAttachment(headers: headers, contentType: contentType, disposition: disposition) {
            return 1
        }

        guard contentType.value.hasPrefix("multipart/") else { return 0 }
        guard let boundary = contentType.parameters["boundary"], !boundary.isEmpty else {
            throw MailStoreError.emlxMalformed
        }
        let children = splitMultipart(body, boundary: boundary)
        guard !children.isEmpty else { throw MailStoreError.emlxMalformed }
        var count = 0
        for child in children {
            guard let parsed = splitHeadersAndBody(child) else { continue }
            count += try countAttachments(
                headers: parsed.headers,
                body: parsed.body,
                depth: depth + 1,
                visitedParts: &visitedParts
            )
        }
        return count
    }

    private func isAttachment(
        headers: [String: String],
        contentType: StructuredHeader,
        disposition: StructuredHeader
    ) -> Bool {
        if disposition.value == "attachment" { return true }
        if disposition.parameters.keys.contains(where: { $0 == "filename" || $0.hasPrefix("filename*") }) {
            return true
        }
        if contentType.parameters.keys.contains(where: { $0 == "name" || $0.hasPrefix("name*") }) {
            return true
        }
        let inlineResource = disposition.value == "inline" &&
            contentType.value != "text/plain" &&
            contentType.value != "text/html" &&
            headers["content-id"]?.isEmpty == false
        return inlineResource
    }

    private typealias StructuredHeader = (value: String, parameters: [String: String])

    private func splitHeadersAndBody(_ data: Data) -> (headers: [String: String], body: Data)? {
        guard let split = headerBodySplit(in: data) else { return nil }
        return (
            parseHeaders(Data(data[..<split.headerEnd])),
            Data(data[split.bodyStart...])
        )
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
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false) {
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

    private func parseStructuredHeader(_ value: String) -> StructuredHeader {
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
}
