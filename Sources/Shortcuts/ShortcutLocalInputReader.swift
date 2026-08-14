import Core
import Darwin
import Foundation

enum ShortcutLocalInputReader {
    static func read(_ url: URL, allowedExtensions: Set<String>, maximumBytes: Int) throws -> Data {
        guard url.isFileURL,
              allowedExtensions.contains(url.pathExtension.lowercased()) else {
            throw ShortcutsError.acquisitionInputInvalid
        }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ShortcutsError.acquisitionInputInvalid }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size >= 0 else {
            throw ShortcutsError.acquisitionInputInvalid
        }
        guard metadata.st_size <= maximumBytes else { throw ShortcutsError.acquisitionInputTooLarge }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.readToEnd(), data.count <= maximumBytes else {
            throw ShortcutsError.acquisitionInputInvalid
        }
        return data
    }
}
