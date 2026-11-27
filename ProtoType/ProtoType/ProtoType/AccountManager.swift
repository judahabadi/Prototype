import AuthenticationServices
import Foundation
import Observation

/// Sign in with Apple with no server: the Apple user ID stays on this device,
/// and the language pair syncs through the user's own iCloud key-value store.
@MainActor
@Observable
final class AccountManager {
    static let shared = AccountManager()

    private static let userIDKey = "appleUserID"
    private static let syncedKeys = [AppGroup.nativeKey, AppGroup.targetKey]

    private(set) var userID: String? = UserDefaults.standard.string(forKey: userIDKey)
    var isSignedIn: Bool { userID != nil }

    private let cloud = NSUbiquitousKeyValueStore.default

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { _ in
            Task { @MainActor in AccountManager.shared.pullSettings() }
        }
        cloud.synchronize()
        Task { await checkCredentialState() }
    }

    // MARK: - Sign in

    func handle(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        userID = credential.user
        UserDefaults.standard.set(credential.user, forKey: Self.userIDKey)
        // Restore settings from another device if iCloud has them, else upload ours.
        if cloud.string(forKey: AppGroup.nativeKey) != nil {
            pullSettings()
        } else {
            pushSettings()
        }
    }

    /// Signs out locally if the user revoked ProtoType in their Apple ID settings.
    func checkCredentialState() async {
        guard let userID else { return }
        let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
        if state == .revoked || state == .notFound { signOut() }
    }

    func signOut() {
        userID = nil
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
    }

    /// Removes the account from this device and the synced settings from iCloud.
    func deleteAccount() {
        for key in Self.syncedKeys { cloud.removeObject(forKey: key) }
        cloud.synchronize()
        signOut()
    }

    // MARK: - iCloud sync

    func pushSettings() {
        guard isSignedIn else { return }
        for key in Self.syncedKeys {
            if let value = AppGroup.defaults.string(forKey: key) { cloud.set(value, forKey: key) }
        }
        cloud.synchronize()
    }

    private func pullSettings() {
        guard isSignedIn else { return }
        for key in Self.syncedKeys {
            if let value = cloud.string(forKey: key) { AppGroup.defaults.set(value, forKey: key) }
        }
    }
}
