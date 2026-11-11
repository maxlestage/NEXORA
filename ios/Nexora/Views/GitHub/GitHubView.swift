import NexoraKit
import SwiftUI
import UIKit

/// L'onglet Code : connexion à GitHub, puis les sessions de l'agent et les dépôts.
struct GitHubView: View {
    @Environment(GitHubSession.self) private var github

    var body: some View {
        NavigationStack {
            Group {
                if github.connected {
                    CodeHomeView()
                } else {
                    GitHubSignInView()
                }
            }
            .navigationTitle(github.connected ? "Code" : "GitHub")
        }
    }
}

/// Se connecter : par code (flux « device ») ou en collant un jeton.
struct GitHubSignInView: View {
    @Environment(GitHubSession.self) private var github
    @Environment(\.openURL) private var openURL
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connectez votre compte").font(.headline)
                    Text("Parcourez et modifiez vos dépôts, gérez issues, pull requests et GitHub Actions, et utilisez GitHub Models sans autre clé.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if GitHubSession.clientId != nil {
                Section("Avec un code") {
                    if let code = github.deviceCode {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Saisissez ce code sur GitHub :")
                            Text(code.userCode).font(.largeTitle.monospaced().bold()).textSelection(.enabled)
                            Button("Ouvrir github.com/login/device") {
                                UIPasteboard.general.string = code.userCode
                                if let u = URL(string: code.verificationUri) { openURL(u) }
                            }
                            .buttonStyle(.borderedProminent)
                            HStack {
                                ProgressView()
                                Text("En attente de votre validation…").foregroundStyle(.secondary)
                            }
                            Button("Annuler", role: .cancel) { github.cancelDeviceFlow() }
                        }
                    } else {
                        Button("Se connecter avec GitHub", systemImage: "person.badge.key") { github.startDeviceFlow() }
                    }
                }
            }
            Section {
                SecureField("ghp_… ou github_pat_…", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await github.signIn(token: token) }
                } label: {
                    if github.loading { ProgressView() } else { Text("Se connecter avec ce jeton") }
                }
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || github.loading)
                Link("Créer un jeton (droits repo et workflow)", destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo,workflow,read:user,gist&description=NEXORA")!)
            } header: {
                Text("Avec un jeton")
            } footer: {
                Text("Le jeton est rangé dans le trousseau de l'iPhone.")
            }
            if let e = github.error {
                Section { Text(e).foregroundStyle(Theme.red) }
            }
        }
    }
}

/// Vos dépôts, avec recherche.
struct ReposView: View {
    @Environment(GitHubSession.self) private var github
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        List {
            if let u = github.user {
                Section {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: u.avatarUrl ?? "")) { img in img.resizable() } placeholder: { Color.secondary.opacity(0.2) }
                            .frame(width: 44, height: 44)
                            .clipShape(.circle)
                        VStack(alignment: .leading) {
                            Text(u.name ?? u.login).font(.headline)
                            Text("@\(u.login)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Nouveau dépôt", systemImage: "plus") { creating = true }
                            Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { github.signOut() }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    }
                }
            }
            if let e = github.error {
                Text(e).foregroundStyle(Theme.red).font(.footnote)
            }
            Section("Dépôts") {
                ForEach(github.repos.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }) { r in
                    NavigationLink(value: r) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(r.fullName).font(.headline).lineLimit(1)
                                if r.isPrivate { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            }
                            if let d = r.description, !d.isEmpty {
                                Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            HStack(spacing: 12) {
                                if let l = r.language { Label(l, systemImage: "chevron.left.forwardslash.chevron.right") }
                                Label("\(r.stars ?? 0)", systemImage: "star")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if github.loading && github.repos.isEmpty { ProgressView() }
        }
        .searchable(text: $query, prompt: "Chercher un dépôt")
        .refreshable { await github.refresh() }
        .navigationDestination(for: Repo.self) { RepoView(repo: $0) }
        .sheet(isPresented: $creating) { CreateRepoSheet() }
    }
}

/// Créer un dépôt.
struct CreateRepoSheet: View {
    /// Le dépôt créé (choisi pour une session, par exemple).
    var onCreated: ((Repo) -> Void)? = nil

    @Environment(GitHubSession.self) private var github
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Description", text: $description)
                Toggle("Privé", isOn: $isPrivate)
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle("Nouveau dépôt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        busy = true
                        Task {
                            do {
                                let repo = try await github.api.createRepo(name: name, description: description, isPrivate: isPrivate)
                                await github.loadRepos()
                                dismiss()
                                onCreated?(repo)
                            } catch {
                                self.error = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    .disabled(name.isEmpty || busy)
                }
            }
        }
    }
}
