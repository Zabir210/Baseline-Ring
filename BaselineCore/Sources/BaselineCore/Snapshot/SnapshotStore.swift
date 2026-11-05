import Foundation

public enum SnapshotStore {
    public static func load(from directory: URL? = nil) -> BaselineSnapshot? {
        let url = AppGroup.snapshotURL(in: directory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? BaselineJSON.decode(BaselineSnapshot.self, from: data)
    }

    public static func save(_ snapshot: BaselineSnapshot, to directory: URL? = nil) throws {
        let folder = directory ?? AppGroup.storageDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = AppGroup.snapshotURL(in: folder)
        let data = try BaselineJSON.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
