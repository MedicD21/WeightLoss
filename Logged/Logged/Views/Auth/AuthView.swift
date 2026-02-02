import SwiftUI
import AuthenticationServices

/// Authentication view with magic link and Apple Sign In
struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var isLoading = false
    @State private var showingMagicLinkSent = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Logo and title
            VStack(spacing: Theme.Spacing.md) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Theme.Colors.border, lineWidth: 1)
                    )

                Text("Logged")
                    .font(Theme.Typography.largeTitle)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Your personal fitness assistant")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            // Auth options
            VStack(spacing: Theme.Spacing.md) {
                // Apple Sign In
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.email, .fullName]
                    },
                    onCompletion: handleAppleSignIn
                )
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(Theme.Radius.medium)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Theme.Colors.border)
                        .frame(height: 1)
                    Text("or")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    Rectangle()
                        .fill(Theme.Colors.border)
                        .frame(height: 1)
                }

                // Email magic link
                VStack(spacing: Theme.Spacing.sm) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.surface)
                        .cornerRadius(Theme.Radius.medium)

                    Button {
                        requestMagicLink()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Continue with Email")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(email.isEmpty || isLoading)
                }

                // Error message
                if let error = error {
                    Text(error)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

            // Terms
            Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
        .background(Color.clear)
        .alert("Check your email", isPresented: $showingMagicLinkSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We've sent a magic link to \(email). Click the link to sign in.")
        }
    }

    private func requestMagicLink() {
        guard !email.isEmpty else { return }

        isLoading = true
        error = nil

        Task {
            do {
                let response = try await APIService.shared.requestMagicLink(email: email)
                showingMagicLinkSent = true

                // In development, auto-verify using debug link
                #if DEBUG
                if let debugLink = response.debugLink,
                   let url = URL(string: debugLink),
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                    try await verifyMagicLink(token: token)
                }
                #endif
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func verifyMagicLink(token: String) async throws {
        let response = try await APIService.shared.verifyMagicLink(token: token)
        appState.signIn(token: response.accessToken, refreshToken: response.refreshToken)
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                Task {
                    await signInWithApple(credential: appleIDCredential)
                }
            }
        case .failure(let error):
            self.error = error.localizedDescription
        }
    }

    private func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        guard let identityToken = credential.identityToken,
              String(data: identityToken, encoding: .utf8) != nil else {
            error = "Invalid Apple credential"
            return
        }

        isLoading = true
        error = nil

        do {
            // For MVP, we'll use the magic link flow to create/get user
            // In production, implement proper Apple Sign In validation on backend
            let email = credential.email ?? "\(credential.user)@privaterelay.appleid.com"

            let response = try await APIService.shared.requestMagicLink(email: email)

            #if DEBUG
            if let debugLink = response.debugLink,
               let url = URL(string: debugLink),
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                try await verifyMagicLink(token: token)
            }
            #endif
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
