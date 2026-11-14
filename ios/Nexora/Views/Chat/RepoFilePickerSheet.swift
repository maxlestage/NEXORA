import NexoraKit
import SwiftUI

/// Choisit un fichier dans un de vos dépôts GitHub, pour le joindre à un message
/// (son texte part avec le message, coupé au-delà de 60 000 caractères).
struct RepoFilePickerSheet: View {
    /// Un dépôt déjà choisi (sinon : la liste de vos dépôts d'abord).
    var repo: Repo?
    let onPick: (ChatAttachment) -> Void

    @Environment(GitHubSession.self) private var github
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if let repo {
                    RepoFileBrowser(repo: repo, path: "", onPick: pick)
                } else {
                    repoList
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
    }

    private var repoList: some View {
        let repos = ReposDisplay.filter(github.repos, query: query)
        return List {
            ForEach(repos) { r in
                NavigationLink {
                    RepoFileBrowser(repo: r, path: "", onPick: pick)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.fullName)
                            if let d = r.description, !d.isEmpty {
                                Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    } icon: {
                        Image(systemName: r.isPrivate ? "lock" : "globe").foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .overlay {
            if !github.connected {
                ContentUnavailableView(
                    "GitHub n'est pas connecté",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Connectez votre compte dans l'onglet Code pour joindre un fichier d'un dépôt.")
                )
            } else if github.loading && github.repos.isEmpty {
                ProgressView()
            } else if let e = github.error, github.repos.isEmpty {
                ContentUnavailableView {
                    Label("Chargement impossible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(e)
                } actions: {
                    Button("Réessayer") { Task { await github.loadRepos() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if repos.isEmpty {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("Aucun dépôt", systemImage: "folder")
                } else {
                    ContentUnavailableView {
                        Label(AttachDisplay.emptyTitle(query: query), systemImage: "magnifyingglass")
                    } actions: {
                        Button("Effacer la recherche") { query = "" }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Chercher un dépôt")
        .navigationTitle("Joindre un fichier")
        .navigationBarTitleDisplayMode(.inline)
        .task { if github.connected && github.repos.isEmpty { await github.loadRepos() } }
    }

    private func pick(_ file: ChatAttachment) {
        onPick(file)
        dismiss()
    }
}

/// Un dossier d'un dépôt : les sous-dossiers s'ouvrent, un fichier est joint.
private struct RepoFileBrowser: View {
    let repo: Repo
    let path: String
    let onPick: (ChatAttachment) -> Void

    @Environment(GitHubSession.self) private var github
    @State private var items: [ContentItem]?
    @State private var error: String?
    @State private var opening: String?
    @State private var query = ""

    var body: some View {
        let shown = FilesDisplay.filter(items ?? [], query: query)
        List {
            Section {
                if let error, items?.isEmpty == false {
                    Text(error).font(.footnote).foregroundStyle(Theme.red)
                }
                ForEach(shown) { item in
                    if item.isDir {
                        NavigationLink {
                            RepoFileBrowser(repo: repo, path: item.path, onPick: onPick)
                        } label: {
                            Label(item.name, systemImage: "folder.fill")
                        }
                    } else {
                        fileRow(item)
                    }
                }
            } header: {
                Text("/\(path)").textCase(nil).font(.caption.monospaced())
            }
        }
        .overlay {
            if items == nil {
                ProgressView()
            } else if let error, items?.isEmpty == true {
                ContentUnavailableView {
                    Label("Chargement impossible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Réessayer") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if shown.isEmpty {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(AttachDisplay.emptyTitle(query: query), systemImage: "folder")
                } else {
                    ContentUnavailableView {
                        Label(AttachDisplay.emptyTitle(query: query), systemImage: "magnifyingglass")
                    } actions: {
                        Button("Effacer la recherche") { query = "" }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Chercher dans ce dossier")
        .navigationTitle(path.isEmpty ? repo.fullName : (path.components(separatedBy: "/").last ?? path))
        .navigationBarTitleDisplayMode(.inline)
        .task { if items == nil { await load() } }
    }

    /// Un fichier : son nom, ce qu'il coûtera (taille, tokens), et s'il sera coupé.
    private func fileRow(_ item: ContentItem) -> some View {
        let detail = AttachDisplay.detail(item)
        let ok = AttachDisplay.canAttach(item)
        return Button {
            Task { await open(item) }
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).foregroundStyle(ok ? .primary : .secondary)
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(AttachDisplay.isCut(item) && ok ? Theme.red : Color.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: ok ? "doc.text" : "doc.questionmark")
                }
                Spacer()
                if opening == item.path { ProgressView() }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(opening != nil || !ok)
        .accessibilityLabel(AttachDisplay.accessibility(item))
    }

    private func load() async {
        do {
            items = FilesDisplay.sorted(try await github.api.list(repo.owner.login, repo.name, path: path))
            error = nil
        } catch {
            items = []
            self.error = error.localizedDescription
        }
    }

    private func open(_ item: ContentItem) async {
        opening = item.path
        defer { opening = nil }
        do {
            let f = try await github.api.readFile(repo.owner.login, repo.name, path: item.path)
            if f.binary {
                error = "Fichier binaire : impossible à joindre."
                return
            }
            onPick(ChatAttachment(path: item.path, text: f.text))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
