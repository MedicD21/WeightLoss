# Temporary Auth State Fix

## Problem
App shows Progress screen when trying to sign in because:
1. Old/expired token exists in keychain
2. App assumes token is valid without checking
3. User sees MainTabView instead of AuthView

## Immediate Fix (For Testing)

Add this to AppState init() to force clear auth on next launch:

```swift
init() {
    // TEMPORARY: Force clear auth state for testing
    #if DEBUG
    KeychainService.shared.deleteToken()
    KeychainService.shared.deleteRefreshToken()
    UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    #endif

    // Check for existing auth token
    if let _ = KeychainService.shared.getToken() {
        isAuthenticated = true
    }

    // Check if user has completed onboarding
    isOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    #if canImport(WatchConnectivity)
    WatchConnectivityService.shared.activate()
    #endif
}
```

## Proper Fix (Permanent Solution)

The real fix is to validate tokens on app launch and handle expired tokens gracefully. See PROPER_AUTH_FIX.md for implementation details.
