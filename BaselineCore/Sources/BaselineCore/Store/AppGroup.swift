import Foundation

/// Shared container id. Create this group on the Apple Developer portal and add it
/// to every target's App Groups capability before a device build.
///
/// iPhone and Watch do not share one folder. The iPhone writes its copy, then
/// WatchConnectivity delivers the snapshot so the Watch can write its own container.
public enum AppGroup {
    public static let identifier = "group.com.zabir.baselinering"
    public static let snapshotFilename = "BaselineSnapshot.json"
    public static let storeFilename = "BaselineRing.store"

    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// App Group container when the entitlement is present; otherwise Application Support.
    public static func storageDirectory() -> URL {
        if let container = containerURL() {
            return container
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BaselineRing", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static func storeURL() -> URL {
        storageDirectory().appendingPathComponent(storeFilename)
    }

    public static func snapshotURL(in directory: URL? = nil) -> URL {
        let folder = directory ?? storageDirectory()
        return folder.appendingPathComponent(snapshotFilename)
    }
}
