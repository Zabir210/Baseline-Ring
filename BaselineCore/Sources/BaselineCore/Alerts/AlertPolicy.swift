import Foundation

public enum AlertPolicy {
    /// Local notification only for a new warn/high, or when severity steps up.
    public static func shouldNotify(previous: BaselineStatus?, new: BaselineStatus) -> Bool {
        guard new == .warn || new == .high else { return false }
        guard let previous else { return true }
        return new.rank > previous.rank
    }
}
