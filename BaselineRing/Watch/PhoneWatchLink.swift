import Foundation
import WatchConnectivity
import BaselineCore

/// Pushes the latest snapshot to the Watch. The two devices do not share an App Group folder.
final class PhoneWatchLink: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchLink()

    private let lock = NSLock()
    private var pending: Data?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ snapshot: BaselineSnapshot) {
        guard let data = try? BaselineJSON.encode(snapshot) else { return }
        lock.lock()
        pending = data
        lock.unlock()
        deliverIfReady()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        deliverIfReady()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message["request"] as? String == "snapshot",
              let snapshot = SnapshotStore.load(),
              let data = try? BaselineJSON.encode(snapshot) else {
            replyHandler([:])
            return
        }
        replyHandler(["snapshot": data])
    }

    private func deliverIfReady() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        lock.lock()
        let data = pending
        lock.unlock()
        guard let data else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }
}
