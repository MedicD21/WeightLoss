import Foundation
import WatchConnectivity
import Combine

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isAuthenticated: Bool = WatchKeychainService.shared.getToken() != nil
    @Published var lastSyncDate: Date? = nil
    @Published var lastError: String? = nil

    private override init() {
        super.init()
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func requestTokens() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["requestTokens": true], replyHandler: { response in
            self.handleTokenPayload(response)
        }, errorHandler: { error in
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        })
    }

    private func handleTokenPayload(_ payload: [String: Any]) {
        if let access = payload["accessToken"] as? String {
            WatchKeychainService.shared.saveToken(access)
        }
        if let refresh = payload["refreshToken"] as? String {
            WatchKeychainService.shared.saveRefreshToken(refresh)
        }

        DispatchQueue.main.async {
            self.isAuthenticated = WatchKeychainService.shared.getToken() != nil
            self.lastSyncDate = Date()
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        }
        if session.isReachable {
            requestTokens()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            requestTokens()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleTokenPayload(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleTokenPayload(userInfo)
    }
}
