import Foundation
import WatchConnectivity
import WidgetKit
import BaselineCore

/// Receives the iPhone snapshot and writes it into the Watch App Group for the complication.
final class WatchSessionClient: NSObject, WCSessionDelegate {
    static let shared = WatchSessionClient()
    var onSnapshot: ((BaselineSnapshot) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func requestLatest() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.sendMessage(["request": "snapshot"], replyHandler: { [weak self] reply in
            self?.ingest(reply)
        }, errorHandler: { _ in })
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        ingest(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }

    private func ingest(_ payload: [String: Any]) {
        guard let data = payload["snapshot"] as? Data,
              let snapshot = try? BaselineJSON.decode(BaselineSnapshot.self, from: data) else { return }
        try? SnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async {
            self.onSnapshot?(snapshot)
        }
    }
}
