import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity

/// Shares auth tokens with the watch companion app.
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        sendTokensIfAvailable()
    }

    private func sendTokensIfAvailable() {
        guard WCSession.default.activationState == .activated else { return }
        guard let accessToken = KeychainService.shared.getToken() else { return }

        var payload: [String: Any] = ["accessToken": accessToken]
        if let refreshToken = KeychainService.shared.getRefreshToken() {
            payload["refreshToken"] = refreshToken
        }

        do {
            try WCSession.default.updateApplicationContext(payload)
        } catch {
            print("WatchConnectivity update context error: \(error)")
        }
        WCSession.default.transferUserInfo(payload)

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: { error in
                print("WatchConnectivity sendMessage error: \(error)")
            })
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WatchConnectivity activation error: \(error)")
        }
        sendTokensIfAvailable()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            sendTokensIfAvailable()
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let request = message["requestTokens"] as? Bool, request {
            var payload: [String: Any] = [:]
            if let accessToken = KeychainService.shared.getToken() {
                payload["accessToken"] = accessToken
            }
            if let refreshToken = KeychainService.shared.getRefreshToken() {
                payload["refreshToken"] = refreshToken
            }
            replyHandler(payload)
        }
    }
}
#endif
