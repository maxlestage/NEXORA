import Foundation
import NexoraKit
import Observation

/// La connexion à GitHub : jeton (saisi ou obtenu par le flux « device »), compte
/// et dépôts.
@MainActor
@Observable
final class GitHubSession {
    private(set) var token: String?
    private(set) var user: GHUser?
    private(set) var repos: [Repo] = []
    var loading = false
    var error: String?
    /// Le code à saisir sur github.com/login/device pendant la connexion.
    var deviceCode: DeviceCode?
    @ObservationIgnored private var deviceTask: Task<Void, Never>?

    /// L'identifiant de l'application OAuth GitHub (flux « device ») : celui saisi
    /// dans Réglages, sinon celui d'Info.plist.
    static var clientId: String? {
        let own = UserDefaults.standard.string(forKey: "github_client_id")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !own.isEmpty { return own }
        let id = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String
        return (id?.isEmpty ?? true) ? nil : id
    }

    init() {
        token = Keychain.get("github_token")
        if token != nil { Task { await refresh() } }
    }

    var api: GitHubAPI { GitHubAPI(token: token) }
    var connected: Bool { !(token ?? "").isEmpty }

    func signIn(token raw: String) async {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let u = try await GitHubAPI(token: t).me()
            Keychain.set(t, for: "github_token")
            token = t
            user = u
            await loadRepos()
        } catch {
            self.error = "Jeton refusé : \(error.localizedDescription)"
        }
    }

    /// Connexion par le flux « device » : un code à saisir sur github.com.
    func startDeviceFlow() {
        guard let clientId = Self.clientId else {
            error = "Connexion par code indisponible dans cette version : collez un jeton GitHub."
            return
        }
        error = nil
        deviceTask?.cancel()
        deviceTask = Task {
            do {
                let code = try await GitHubAPI.startDeviceFlow(clientId: clientId)
                deviceCode = code
                let t = try await GitHubAPI.pollDeviceFlow(clientId: clientId, code: code)
                deviceCode = nil
                await signIn(token: t)
            } catch is CancellationError {
                deviceCode = nil
            } catch {
                deviceCode = nil
                self.error = error.localizedDescription
            }
        }
    }

    func cancelDeviceFlow() {
        deviceTask?.cancel()
        deviceCode = nil
    }

    func signOut() {
        Keychain.set(nil, for: "github_token")
        token = nil
        user = nil
        repos = []
    }

    func refresh() async {
        guard connected else { return }
        do {
            user = try await api.me()
            await loadRepos()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadRepos() async {
        guard connected else { return }
        loading = true
        defer { loading = false }
        do {
            repos = try await api.myRepos()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
