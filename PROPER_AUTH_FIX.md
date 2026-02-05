# Proper Auth Token Validation Fix

## Problem
The app doesn't validate auth tokens on launch. It assumes if a token exists, it's valid. This causes users to see the main app UI when their token is expired.

## Current Flow (BROKEN)
```
App Launch
 → Check if token exists in keychain
 → IF token exists: isAuthenticated = true
 → Show MainTabView (even if token is expired!)
```

## Proper Flow (FIXED)
```
App Launch
 → Check if token exists
 → IF token exists:
    → Validate token with backend
    → IF valid: isAuthenticated = true
    → IF invalid: Clear token, show AuthView
 → ELSE:
    → Show AuthView
```

## Implementation

### Step 1: Add Token Validation to APIService

Add this method to `Logged/Logged/Services/APIService.swift`:

```swift
/// Validate the current auth token
func validateToken() async throws -> Bool {
    struct ValidationResponse: Decodable {
        let valid: Bool
        let userId: UUID?
    }

    do {
        let response: ValidationResponse = try await request(
            endpoint: "auth/validate",
            method: .GET,
            requiresAuth: true
        )
        return response.valid
    } catch APIError.unauthorized {
        // Token is invalid/expired
        return false
    } catch {
        // Network error, assume token might be valid (offline mode)
        return true
    }
}
```

### Step 2: Update AppState to Validate on Launch

Modify `Logged/Logged/LoggedApp.swift`:

```swift
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isOnboarded = false
    @Published var selectedTab: Tab = .dashboard
    @Published var showingChat = false
    @Published var isValidatingAuth = true  // NEW: Show loading while validating

    enum Tab: String, CaseIterable {
        // ... existing code
    }

    init() {
        // Check for existing auth token
        if let _ = KeychainService.shared.getToken() {
            // Don't set isAuthenticated yet - validate first
            Task { @MainActor in
                await validateAuthToken()
            }
        } else {
            isValidatingAuth = false
        }

        // Check if user has completed onboarding
        isOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        #if canImport(WatchConnectivity)
        WatchConnectivityService.shared.activate()
        #endif
    }

    @MainActor
    private func validateAuthToken() async {
        do {
            let isValid = try await APIService.shared.validateToken()
            if isValid {
                isAuthenticated = true
            } else {
                // Token is invalid, clear it
                signOut()
            }
        } catch {
            // Network error, assume offline - allow cached auth
            isAuthenticated = true
        }
        isValidatingAuth = false
    }

    func signIn(token: String, refreshToken: String) {
        KeychainService.shared.saveToken(token)
        KeychainService.shared.saveRefreshToken(refreshToken)
        isAuthenticated = true
    }

    func signOut() {
        KeychainService.shared.deleteToken()
        KeychainService.shared.deleteRefreshToken()
        isAuthenticated = false
        isOnboarded = false  // Reset onboarding too
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isOnboarded = true
    }
}
```

### Step 3: Update ContentView to Show Loading State

Modify `Logged/Logged/ContentView.swift`:

```swift
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    private var shouldShowChatButton: Bool {
        appState.isAuthenticated && appState.isOnboarded && !appState.showingChat
    }

    var body: some View {
        ZStack {
            AnimatedBackground()
                .ignoresSafeArea()

            // Show loading while validating token
            if appState.isValidatingAuth {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.top, Theme.Spacing.md)
                }
            } else if appState.isAuthenticated {
                if appState.isOnboarded {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            } else {
                AuthView()
            }

            // Floating chat handle
            if shouldShowChatButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingChatHandle()
                    }
                    .padding(.trailing, -Theme.Spacing.xs)
                    .padding(.bottom, 90)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
```

### Step 4: Backend - Add Token Validation Endpoint

Add this to `backend/app/routes/auth.py`:

```python
@router.get("/validate", response_model=dict)
async def validate_token(
    current_user: UserProfile = Depends(get_current_user),
):
    """Validate the current auth token."""
    return {
        "valid": True,
        "user_id": str(current_user.id),
        "email": current_user.email
    }
```

## Benefits

1. ✅ **No more invalid token states** - App validates tokens on launch
2. ✅ **Graceful offline handling** - Assumes cached auth is valid if network fails
3. ✅ **Better UX** - Shows loading indicator while validating
4. ✅ **Proper logout** - Clears both auth AND onboarding state
5. ✅ **Secure** - Backend validates every token

## Testing

1. **Fresh install** - Should show AuthView immediately
2. **Valid token** - Should show MainTabView after brief loading
3. **Expired token** - Should clear state and show AuthView
4. **Offline** - Should allow cached auth to work

## Files to Modify

1. [ ] `Logged/Logged/Services/APIService.swift` - Add validateToken()
2. [ ] `Logged/Logged/LoggedApp.swift` - Update AppState
3. [ ] `Logged/Logged/ContentView.swift` - Add loading state
4. [ ] `backend/app/routes/auth.py` - Add /validate endpoint

## Priority: HIGH
This fixes a critical auth state bug that prevents users from properly signing in.
