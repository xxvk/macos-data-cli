import Foundation

/// Minimal local diagnostics for failures that are otherwise only visible on stderr.
/// The log intentionally excludes command arguments because they may contain private data.
public enum DiagnosticLogger {
    public static let directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/macos-data-cli", isDirectory: true)
    public static let fileURL: URL = directoryURL.appendingPathComponent("diagnostics.log")

    public static func record(code: String, message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) [\(code)] \(message)\n"
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            }
        } catch {
            // Diagnostics must never replace the original CLI error.
        }
    }

    public static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        var details = "domain=\(nsError.domain) code=\(nsError.code)"
        if !nsError.userInfo.isEmpty {
            details += " userInfoKeys=\(nsError.userInfo.keys.map { String(describing: $0) }.sorted().joined(separator: ","))"
        }
        if let exception = nsError.userInfo["NSUnderlyingException"] {
            details += " underlyingException=\(String(describing: exception))"
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            details += " underlyingDomain=\(underlying.domain) underlyingCode=\(underlying.code)"
        }
        return details
    }

    public static func stackTrace() -> String {
        Thread.callStackSymbols.joined(separator: " || ")
    }
}
