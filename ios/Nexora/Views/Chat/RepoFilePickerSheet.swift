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
        let repos = github.repos.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }
        return List {
            if let e = github.error, github.repos.isEmpty {
                Text(e).font(.footnote).foregroundStyle(Theme.red)
            }
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
        .overlay { if github.loading && github.repos.isEmpty { ProgressView() } }
        .searchable(text: $query, prompt: "Choisir un dépôt")
        .navigationTitle("Joindre un fichier")
        .navigationBarTitleDisplayMode(.inline)
        .task { if github.repos.isEmpty { await github.loadRepos() } }
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

    var body: some View {
        List {
            Section {
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.red) }
                ForEach(items ?? []) { item in
                    if item.isDir {
                        NavigationLink {
                            RepoFileBrowser(repo: repo, path: item.path, onPick: onPick)
                        } label: {
                            Label(item.name, systemImage: "folder.fill")
                        }
                    } else {
                        Button {
                            Task { await open(item) }
                        } label: {
                            HStack {
                                Label(item.name, systemImage: "doc.text").foregroundStyle(.primary)
                                Spacer()
                                if opening == item.path { ProgressView() }
                            }
                        }
                        .disabled(opening != nil)
                    }
                }
            } header: {
                Text("/\(path)").textCase(nil).font(.caption.monospaced())
            }
        }
        .overlay { if items == nil && error == nil { ProgressView() } }
        .navigationTitle(path.isEmpty ? repo.fullName : (path.components(separatedBy: "/").last ?? path))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            items = try await github.api.list(repo.owner.login, repo.name, path: path)
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
