import NexoraKit
import SwiftUI

/// Les issues ou les pull requests d'un dépôt.
struct IssuesListView: View {
    let repo: Repo
    let pulls: Bool

    @Environment(GitHubSession.self) private var github
    @State private var state = "open"
    @State private var items: [Issue] = []
    @State private var error: String?
    @State private var loading = true
    @State private var creating = false

    var body: some View {
        List {
            Picker("État", selection: $state) {
                Text("Ouvertes").tag("open")
                Text("Fermées").tag("closed")
            }
            .pickerStyle(.segmented)
            if let error { Text(error).foregroundStyle(Theme.red) }
            ForEach(items) { i in
                NavigationLink { IssueDetailView(repo: repo, issue: i) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(i.title).font(.headline).lineLimit(2)
                        HStack(spacing: 8) {
                            Text("#\(i.number)")
                            if let u = i.user { Text("@\(u.login)") }
                            if let c = i.comments, c > 0 { Label("\(c)", systemImage: "bubble.left") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !loading && items.isEmpty && error == nil {
                Text(pulls ? "Aucune pull request." : "Aucune issue.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .overlay { if loading { ProgressView() } }
        .refreshable { await load() }
        .task(id: state) { await load() }
        .toolbar {
            if !pulls {
                ToolbarItem(placement: .bottomBar) {
                    Button("Nouvelle issue", systemImage: "plus.bubble") { creating = true }
                }
            }
        }
        .sheet(isPresented: $creating) {
            NewIssueSheet(repo: repo) { Task { await load() } }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            items = pulls
                ? try await github.api.pulls(repo.owner.login, repo.name, state: state)
                : try await github.api.issues(repo.owner.login, repo.name, state: state)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Une issue ou une pull request : description, commentaires, réponse, fermeture,
/// fusion.
struct IssueDetailView: View {
    let repo: Repo
    let issue: Issue

    @Environment(GitHubSession.self) private var github
    @State private var comments: [Comment] = []
    @State private var reply = ""
    @State private var state: String
    @State private var error: String?
    @State private var info: String?

    init(repo: Repo, issue: Issue) {
        self.repo = repo
        self.issue = issue
        _state = State(initialValue: issue.state)
    }

    var body: some View {
        List {
            Section {
                Text(issue.title).font(.title3.bold())
                HStack {
                    Pill(text: state == "open" ? "Ouverte" : "Fermée", color: state == "open" ? Theme.green : .secondary)
                    Text("#\(issue.number) · @\(issue.user?.login ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                if let body = issue.body, !body.isEmpty { MarkdownView(text: body) }
            }
            if !comments.isEmpty {
                Section("Commentaires") {
                    ForEach(comments) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("@\(c.user?.login ?? "")").font(.caption.bold())
                            MarkdownView(text: c.body ?? "")
                        }
                    }
                }
            }
            Section("Répondre") {
                TextField("Votre commentaire", text: $reply, axis: .vertical).lineLimit(2...8)
                Button("Commenter") {
                    Task {
                        do {
                            try await github.api.comment(repo.owner.login, repo.name, number: issue.number, body: reply)
                            reply = ""
                            await load()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section {
                if issue.isPull && state == "open" {
                    Button("Fusionner (squash)", systemImage: "arrow.triangle.merge") {
                        Task {
                            do {
                                try await github.api.mergePull(repo.owner.login, repo.name, number: issue.number)
                                state = "closed"
                                info = "Pull request fusionnée."
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                Button(state == "open" ? "Fermer" : "Rouvrir", systemImage: state == "open" ? "xmark.circle" : "arrow.uturn.left.circle") {
                    let target = state == "open" ? "closed" : "open"
                    Task {
                        do {
                            try await github.api.setIssueState(repo.owner.login, repo.name, number: issue.number, state: target)
                            state = target
                        } catch { self.error = error.localizedDescription }
                    }
                }
                if let url = issue.htmlUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label("Ouvrir sur GitHub", systemImage: "safari") }
                }
            }
            if let info { Text(info).foregroundStyle(Theme.green) }
            if let error { Text(error).foregroundStyle(Theme.red) }
        }
        .navigationTitle("#\(issue.number)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        comments = (try? await github.api.comments(repo.owner.login, repo.name, number: issue.number)) ?? comments
    }
}

struct NewIssueSheet: View {
    let repo: Repo
    let onCreated: () -> Void
    @Environment(GitHubSession.self) private var github
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre", text: $title)
                TextField("Description (Markdown)", text: $body_, axis: .vertical).lineLimit(5...20)
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            .navigationTitle("Nouvelle issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        Task {
                            do {
                                _ = try await github.api.createIssue(repo.owner.login, repo.name, title: title, body: body_)
                                onCreated()
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// GitHub Actions : les exécutions récentes (relancer) et les workflows (lancer).
struct ActionsView: View {
    let repo: Repo
    @Environment(GitHubSession.self) private var github
    @State private var runs: [WorkflowRun] = []
    @State private var workflows: [Workflow] = []
    @State private var error: String?
    @State private var info: String?
    @State private var loading = true

    var body: some View {
        List {
            if let info { Text(info).foregroundStyle(Theme.green) }
            if let error { Text(error).foregroundStyle(Theme.red) }
            Section("Exécutions") {
                ForEach(runs) { r in
                    HStack(spacing: 10) {
                        statusIcon(r)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).lineLimit(2)
                            Text("\(r.name ?? "") · \(r.headBranch ?? "") · \(r.event ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button("Relancer", systemImage: "arrow.clockwise") {
                            Task {
                                do {
                                    try await github.api.rerun(repo.owner.login, repo.name, runId: r.id)
                                    info = "Exécution relancée."
                                    await load()
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .tint(.accentColor)
                        if let url = r.htmlUrl.flatMap(URL.init(string:)) {
                            Link(destination: url) { Label("GitHub", systemImage: "safari") }
                        }
                    }
                }
            }
            Section("Workflows") {
                ForEach(workflows) { w in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(w.name)
                            Text(w.file).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Lancer") {
                            Task {
                                do {
                                    try await github.api.dispatch(repo.owner.login, repo.name, workflowId: w.id, ref: repo.branch)
                                    info = "« \(w.name) » lancé sur \(repo.branch)."
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func statusIcon(_ r: WorkflowRun) -> some View {
        switch (r.status ?? "", r.conclusion ?? "") {
        case ("completed", "success"): Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case ("completed", "skipped"), ("completed", "neutral"): Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case ("completed", "cancelled"): Image(systemName: "slash.circle").foregroundStyle(.secondary)
        case ("completed", _): Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.red)
        default: ProgressView().controlSize(.small)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let api = github.api
            let owner = repo.owner.login
            let name = repo.name
            async let r = api.runs(owner, name)
            async let w = api.workflows(owner, name)
            (runs, workflows) = try await (r, w)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Les derniers commits d'une branche.
struct CommitsView: View {
    let repo: Repo
    let branch: String
    @Environment(GitHubSession.self) private var github
    @State private var commits: [Commit] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(Theme.red) }
            ForEach(commits) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).lineLimit(2)
                    Text("\(String(c.sha.prefix(7))) · \(c.commit.author?.name ?? "")").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await load() }
        .task(id: branch) { await load() }
    }

    private func load() async {
        do {
            commits = try await github.api.commits(repo.owner.login, repo.name, branch: branch)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
