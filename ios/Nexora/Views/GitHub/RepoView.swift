import NexoraKit
import SwiftUI

/// Un dépôt : fichiers, issues, pull requests, Actions et commits.
struct RepoView: View {
    let repo: Repo

    enum Part: String, CaseIterable, Identifiable {
        case files = "Fichiers", issues = "Issues", pulls = "PR", actions = "Actions", commits = "Commits"
        var id: String { rawValue }
    }

    @State private var section: Part = .files
    @State private var branch: String?
    @State private var branches: [String] = []
    @State private var showCloud = false
    @Environment(GitHubSession.self) private var github

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(Part.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            switch section {
            case .files: FileBrowserView(repo: repo, path: "", branch: branch ?? repo.branch)
            case .issues: IssuesListView(repo: repo, pulls: false)
            case .pulls: IssuesListView(repo: repo, pulls: true)
            case .actions: ActionsView(repo: repo)
            case .commits: CommitsView(repo: repo, branch: branch ?? repo.branch)
            }
        }
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // L'action principale : l'agent autonome sur ce dépôt (une session de l'atelier).
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NewSessionView(repo: repo, branch: branch ?? repo.branch)
                } label: {
                    Image(systemName: "sparkles")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Agent autonome")
            }
            // Le reste, plus rare, dans un seul menu : branche, agents cloud, GitHub.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // Menu imbriqué : la branche choisie s'affiche sous « Branche ».
                    Picker("Branche", systemImage: "arrow.triangle.branch",
                           selection: Binding(get: { branch ?? repo.branch }, set: { branch = $0 })) {
                        ForEach(branches.isEmpty ? [repo.branch] : branches, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Button("Agents cloud", systemImage: "cloud") { showCloud = true }
                    if let url = URL(string: repo.htmlUrl) {
                        Link(destination: url) { Label("Ouvrir sur GitHub", systemImage: "safari") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Plus d'options, branche \(branch ?? repo.branch)")
            }
        }
        .navigationDestination(isPresented: $showCloud) { CloudAgentsView(repo: repo) }
        .task { branches = (try? await github.api.branches(repo.owner.login, repo.name)) ?? [] }
    }
}

/// Les fichiers d'un dossier.
struct FileBrowserView: View {
    let repo: Repo
    let path: String
    let branch: String

    @Environment(GitHubSession.self) private var github
    @State private var items: [ContentItem] = []
    @State private var error: String?
    @State private var loading = true
    @State private var newFile = false

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink {
                    if item.isDir {
                        FileBrowserView(repo: repo, path: item.path, branch: branch)
                            .navigationTitle(item.name)
                    } else {
                        FileEditorView(repo: repo, path: item.path, branch: branch)
                    }
                } label: {
                    Label {
                        HStack {
                            Text(item.name)
                            Spacer()
                            if !item.isDir, let s = item.size { Text(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: item.isDir ? "folder.fill" : "doc.text").foregroundStyle(item.isDir ? Color.accentColor : .secondary)
                    }
                }
            }
            if !items.isEmpty {
                Text(FilesDisplay.summary(items))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading && items.isEmpty {
                ProgressView()
            } else if let error, items.isEmpty {
                ContentUnavailableView {
                    Label("Chargement impossible", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Réessayer") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if !loading && items.isEmpty {
                ContentUnavailableView {
                    Label("Dossier vide", systemImage: "folder")
                } actions: {
                    Button("Nouveau fichier", systemImage: "doc.badge.plus") { newFile = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error, !items.isEmpty {
                Text(error).font(.footnote).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.vertical, 6)
            }
        }
        .refreshable { await load() }
        .task(id: branch) { await load() }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button("Nouveau fichier", systemImage: "doc.badge.plus") { newFile = true }
            }
        }
        .sheet(isPresented: $newFile) {
            NavigationStack {
                FileEditorView(repo: repo, path: path.isEmpty ? "" : path + "/", branch: branch, isNew: true)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let list = try await github.api.list(repo.owner.login, repo.name, path: path, ref: branch)
            items = FilesDisplay.sorted(list)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Lire et modifier un fichier, puis l'enregistrer par un commit.
struct FileEditorView: View {
    let repo: Repo
    @State var path: String
    let branch: String
    var isNew = false

    @Environment(GitHubSession.self) private var github
    @Environment(\.dismiss) private var dismiss
    @State private var file: FileContent?
    @State private var text = ""
    @State private var editing = false
    @State private var message = ""
    @State private var error: String?
    @State private var saving = false
    @State private var info: String?

    private var changed: Bool { isNew ? !text.isEmpty : text != file?.text }

    var body: some View {
        VStack(spacing: 0) {
            if isNew {
                TextField("chemin/du/fichier.txt", text: $path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(.fill.quaternary)
            }
            if let error { Text(error).foregroundStyle(Theme.red).padding() }
            if let info { Text(info).foregroundStyle(Theme.green).font(.footnote).padding(.top, 6) }
            if file?.binary == true {
                ContentUnavailableView("Fichier binaire", systemImage: "doc.questionmark", description: Text("Ce fichier ne peut pas être affiché."))
            } else if editing || isNew {
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 8)
            } else if file != nil {
                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
            if changed {
                HStack {
                    TextField("Message du commit", text: $message)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Commit") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || (isNew && path.hasSuffix("/")))
                }
                .padding()
                .background(.bar)
            }
        }
        .navigationTitle(isNew ? "Nouveau fichier" : (path.split(separator: "/").last.map(String.init) ?? path))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            } else if file?.binary == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "Aperçu" : "Modifier") { editing.toggle() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .task {
            guard !isNew else { return }
            do {
                let f = try await github.api.readFile(repo.owner.login, repo.name, path: path, ref: branch)
                file = f
                text = f.text
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let msg = message.trimmingCharacters(in: .whitespaces).isEmpty
            ? (isNew ? "Ajoute \(path)" : "Met à jour \(path)")
            : message
        do {
            let sha = try await github.api.writeFile(repo.owner.login, repo.name, path: path, content: text, message: msg, sha: file?.sha, branch: branch)
            file = FileContent(path: path, text: text, sha: sha, binary: false)
            message = ""
            editing = false
            error = nil
            info = "Enregistré sur \(branch)."
            if isNew { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
