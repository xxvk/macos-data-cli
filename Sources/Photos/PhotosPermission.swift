import AppKit
import Core
import Photos

public final class PhotosPermission: PhotoAccessProviding, @unchecked Sendable {
    private final class AuthorizationResult: @unchecked Sendable {
        private let lock = NSLock()
        private var value: PhotoAccessStatus?

        func set(_ value: PhotoAccessStatus) { lock.withLock { self.value = value } }
        func get() -> PhotoAccessStatus? { lock.withLock { value } }
    }

    public init() {}

    public var status: PhotoAccessStatus {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    public func requestReadWriteAccess() async -> PhotoAccessStatus {
        await MainActor.run { () -> PhotoAccessStatus in
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "macos-data Photos Authorization"
            window.center()
            window.makeKeyAndOrderFront(nil)
            let result = AuthorizationResult()
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                result.set(Self.map(status))
            }
            while result.get() == nil {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            }
            window.orderOut(nil)
            return result.get() ?? .denied
        }
    }

    public static func map(_ status: PHAuthorizationStatus) -> PhotoAccessStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .limited: .limited
        case .authorized: .authorized
        @unknown default: .denied
        }
    }
}
