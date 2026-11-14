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

/// Se connecter : par code (flux « device », action principale) ou en collant un jeton
/// (replié quand le code est possible).
struct GitHubSignInView: View {
    @Environment(GitHubSession.self) private var github
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    @State private var tokenOpen = GitHubSession.clientId == nil
    @State private var toast: Toast?
    @State private var copied = 0

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connectez votre compte")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(GitHubSignInDisplay.intro)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if GitHubSession.clientId != nil {
                Section {
                    if let code = github.deviceCode {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Saisissez ce code sur GitHub :")
                            Text(code.userCode)
                                .font(.largeTitle.monospaced().bold())
                                .textSelection(.enabled)
                                .accessibilityLabel(GitHubSignInDisplay.spokenCode(code.userCode))
                            Button {
                                UIPasteboard.general.string = code.userCode
                                copied += 1
                                toast = Toast(text: "Code copié : collez-le sur GitHub")
                                if let u = URL(string: code.verificationUri) { openURL(u) }
                            } label: {
                                Text("Copier le code et ouvrir GitHub")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            HStack {
                                ProgressView()
                                Text("En attente de votre validation…").foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            Button("Annuler", role: .cancel) { github.cancelDeviceFlow() }
                                .frame(minHeight: 44)
                        }
                    } else {
                        Button {
                            github.startDeviceFlow()
                        } label: {
                            Label("Se connecter avec GitHub", systemImage: "person.badge.key")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section {
                DisclosureGroup("Avec un jeton", isExpanded: $tokenOpen) {
                    SecureField("ghp_… ou github_pat_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                    if let hint = GitHubSignInDisplay.tokenHint(token) {
                        Text(hint).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(action: signIn) {
                        if github.loading { ProgressView() } else { Text("Se connecter avec ce jeton") }
                    }
                    .frame(minHeight: 44)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || github.loading)
                    Link("Créer un jeton (droits repo et workflow)", destination: URL(string: "https://github.com/settings/tokens/new?scopes=repo,workflow,read:user,gist&description=NEXORA")!)
                        .frame(minHeight: 44)
                }
            } footer: {
                if tokenOpen { Text("Le jeton est rangé dans le trousseau de l'iPhone.") }
            }
            if let e = github.error {
                Section { Text(e).foregroundStyle(Theme.red) }
            }
        }
        .toast($toast)
        .sensoryFeedback(.success, trigger: copied) { _, _ in settings.haptics }
    }

    private func signIn() {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !github.loading else { return }
        Task { await github.signIn(token: token) }
    }
}

/// Vos dépôts, avec recherche.
struct ReposView: View {
    @Environment(GitHubSession.self) private var github
    @State private var query = ""
    @State private var creating = false

    /// Les dépôts affichés (recherche sans accents ni casse, description et langage compris).
    private var shown: [Repo] { ReposDisplay.filter(github.repos, query: query) }

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
                            Button("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { github.signOut() }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3)
                                .frame(width: 44, height: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel("Options du compte GitHub")
                    }
                }
            }
            if let e = github.error {
                Text(e).foregroundStyle(Theme.red).font(.footnote)
            }
            Section("Dépôts") {
                ForEach(shown) { r in
                    NavigationLink(value: r) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(r.fullName).font(.headline).lineLimit(1)
                                if r.isPrivate { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            }
                            if let d = r.description, !d.isEmpty {
                                Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            let meta = ReposDisplay.meta(r)
                            if !meta.isEmpty {
                                Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .overlay {
            if github.loading && github.repos.isEmpty {
                ProgressView()
            } else if github.repos.isEmpty && github.user != nil && github.error == nil {
                ContentUnavailableView {
                    Label("Aucun dépôt", systemImage: "folder")
                } description: {
                    Text("Créez votre premier dépôt pour y faire travailler l'agent.")
                } actions: {
                    Button("Nouveau dépôt", systemImage: "plus") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if !github.repos.isEmpty && shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nouveau dépôt", systemImage: "plus") { creating = true }
            }
        }
        .searchable(text: $query, prompt: "Nom, description ou langage")
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
                Section {
                    TextField("Nom", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    if let note = ReposDisplay.repoNameNote(name) {
                        Text(note)
                    } else if !name.isEmpty, let problem = ReposDisplay.repoNameProblem(name) {
                        Text(problem).foregroundStyle(Theme.red)
                    }
                }
                Section {
                    TextField("Description (facultative)", text: $description)
                    Toggle("Privé", isOn: $isPrivate)
                }
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
                                let repo = try await github.api.createRepo(name: ReposDisplay.repoName(name), description: description, isPrivate: isPrivate)
                                await github.loadRepos()
                                dismiss()
                                onCreated?(repo)
                            } catch {
                                self.error = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                    .disabled(ReposDisplay.repoNameProblem(name) != nil || busy)
                }
            }
        }
    }
}
