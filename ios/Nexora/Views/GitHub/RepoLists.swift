import NexoraKit
import SwiftUI

/// Les issues ou les pull requests d'un dépôt : ouvertes ou fermées, recherche dès
/// `IssuesDisplay.searchFrom` éléments, état vide clair.
struct IssuesListView: View {
    let repo: Repo
    let pulls: Bool

    @Environment(GitHubSession.self) private var github
    @State private var state = "open"
    @State private var items: [Issue] = []
    @State private var error: String?
    @State private var loading = true
    @State private var creating = false
    @State private var query = ""

    private var open: Bool { state == "open" }
    private var shown: [Issue] { IssuesDisplay.filter(items, query: query) }

    var body: some View {
        let content = List {
            Picker("État", selection: $state) {
                Text("Ouvertes").tag("open")
                Text("Fermées").tag("closed")
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).foregroundStyle(Theme.red)
                    Button("Réessayer", systemImage: "arrow.clockwise") { Task { await load() } }
                        .frame(minHeight: 44)
                }
            }
            if !shown.isEmpty {
                Section {
                    ForEach(shown) { i in
                        NavigationLink { IssueDetailView(repo: repo, issue: i) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(i.title).font(.headline).lineLimit(2)
                                Text(IssuesDisplay.detail(i)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(IssuesDisplay.accessibility(i))
                        }
                    }
                } header: {
                    Text(IssuesDisplay.count(shown.count, open: open))
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading && items.isEmpty {
                ProgressView()
            } else if !loading && error == nil && items.isEmpty {
                ContentUnavailableView {
                    Label(IssuesDisplay.emptyTitle(pulls: pulls, open: open),
                          systemImage: pulls ? "arrow.triangle.pull" : "checkmark.bubble")
                } description: {
                    Text(IssuesDisplay.emptyHint(pulls: pulls, open: open))
                }
            } else if shown.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .refreshable { await load() }
        .task(id: state) { await load() }
        // Pas d'anciens éléments (ouverts) sous l'onglet Fermées pendant le chargement.
        .onChange(of: state) { items = [] }
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
        Group {
            if items.count >= IssuesDisplay.searchFrom {
                content.searchable(text: $query, prompt: pulls ? "Rechercher une pull request" : "Rechercher une issue")
            } else {
                content
            }
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

/// Une issue ou une pull request : description, actions (la principale en haut),
/// commentaires, réponse.
struct IssueDetailView: View {
    let repo: Repo
    let issue: Issue

    @Environment(GitHubSession.self) private var github
    @Environment(SettingsStore.self) private var settings
    @State private var comments: [Comment] = []
    @State private var reply = ""
    @State private var state: String
    @State private var merged = false
    @State private var error: String?
    @State private var info: String?
    @State private var sending = false
    /// Une action (fusion, fermeture) est en cours : boutons désactivés, pas de double envoi.
    @State private var busy = false
    @State private var confirmMerge = false
    @State private var confirmClose = false
    /// Change à chaque action réussie (vibration).
    @State private var done = 0

    init(repo: Repo, issue: Issue) {
        self.repo = repo
        self.issue = issue
        _state = State(initialValue: issue.state)
    }

    private var open: Bool { state == "open" }

    var body: some View {
        List {
            Section {
                Text(issue.title).font(.title3.bold())
                HStack {
                    Pill(text: IssuesDisplay.stateLabel(open: open, merged: merged),
                         color: merged ? Theme.violet : (open ? Theme.green : .secondary))
                    Text("#\(issue.number) · @\(issue.user?.login ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                if let body = issue.body, !body.isEmpty { MarkdownView(text: body) }
            }
            Section {
                ForEach(IssuesDisplay.actions(isPull: issue.isPull, open: open, merged: merged), id: \.self) { action in
                    Button(action.title, systemImage: action.symbol) { run(action) }
                        .frame(minHeight: 44)
                        .disabled(busy)
                }
                if let url = issue.htmlUrl.flatMap(URL.init(string:)) {
                    Link(destination: url) { Label("Ouvrir sur GitHub", systemImage: "safari") }
                        .frame(minHeight: 44)
                }
                if let info { Text(info).foregroundStyle(Theme.green) }
                if let error { Text(error).foregroundStyle(Theme.red) }
            }
            if !comments.isEmpty {
                Section(IssuesDisplay.commentsHeader(comments.count)) {
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
                Button("Commenter", systemImage: "paperplane") { send() }
                    .frame(minHeight: 44)
                    .disabled(sending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("#\(issue.number)")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .sensoryFeedback(.success, trigger: done) { _, _ in settings.haptics }
        .confirmationDialog(IssuesDisplay.mergeQuestion(issue), isPresented: $confirmMerge, titleVisibility: .visible) {
            Button("Fusionner") { merge() }
        }
        .confirmationDialog(IssuesDisplay.closeQuestion(issue), isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Fermer", role: .destructive) { setState("closed") }
        }
    }

    private func run(_ action: IssuesDisplay.Action) {
        switch action {
        case .merge: confirmMerge = true
        case .close: confirmClose = true
        case .reopen: setState("open")
        }
    }

    private func send() {
        sending = true
        Task {
            defer { sending = false }
            do {
                try await github.api.comment(repo.owner.login, repo.name, number: issue.number, body: reply)
                reply = ""
                error = nil
                done += 1
                await load()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func merge() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await github.api.mergePull(repo.owner.login, repo.name, number: issue.number)
                state = "closed"
                merged = true
                info = "Pull request fusionnée."
                error = nil
                done += 1
            } catch { self.error = error.localizedDescription }
        }
    }

    private func setState(_ target: String) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await github.api.setIssueState(repo.owner.login, repo.name, number: issue.number, state: target)
                state = target
                info = nil
                error = nil
                done += 1
            } catch { self.error = error.localizedDescription }
        }
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

/// GitHub Actions : les exécutions récentes (« Relancer » visible sur celles qui ont
/// échoué) et les workflows (lancer après confirmation).
struct ActionsView: View {
    let repo: Repo
    @Environment(GitHubSession.self) private var github
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var runs: [WorkflowRun] = []
    @State private var workflows: [Workflow] = []
    @State private var error: String?
    @State private var info: String?
    @State private var loading = true
    @State private var busy: Set<Int> = []
    @State private var toLaunch: Workflow?
    @State private var done = 0

    var body: some View {
        List {
            if let info { Text(info).foregroundStyle(Theme.green) }
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).foregroundStyle(Theme.red)
                    Button("Réessayer", systemImage: "arrow.clockwise") { Task { await load() } }
                        .frame(minHeight: 44)
                }
            }
            if !runs.isEmpty {
                Section {
                    ForEach(runs) { r in runRow(r) }
                } header: {
                    Text(ActionsDisplay.runsHeader(runs))
                }
            }
            if !workflows.isEmpty {
                Section("Workflows") {
                    ForEach(workflows) { w in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(w.name)
                                Text(w.file).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Lancer") { toLaunch = w }
                                .buttonStyle(.bordered)
                                .frame(minHeight: 44)
                                .disabled(busy.contains(w.id))
                                .accessibilityLabel("Lancer \(w.name)")
                        }
                    }
                }
            }
        }
        .overlay {
            if loading && runs.isEmpty && workflows.isEmpty {
                ProgressView()
            } else if !loading && error == nil && runs.isEmpty && workflows.isEmpty {
                ContentUnavailableView {
                    Label("Aucune action", systemImage: "gearshape.2")
                } description: {
                    Text("Ce dépôt n'a pas encore de workflow GitHub Actions.")
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sensoryFeedback(.success, trigger: done) { _, _ in settings.haptics }
        .confirmationDialog(toLaunch.map { ActionsDisplay.dispatchQuestion($0, branch: repo.branch) } ?? "",
                            isPresented: Binding(get: { toLaunch != nil }, set: { if !$0 { toLaunch = nil } }),
                            titleVisibility: .visible, presenting: toLaunch) { w in
            Button("Lancer") { dispatch(w) }
        }
    }

    private func runRow(_ r: WorkflowRun) -> some View {
        HStack(spacing: 10) {
            statusIcon(r)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).lineLimit(2)
                Text(ActionsDisplay.detail(r)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ActionsDisplay.accessibility(r))
            Spacer(minLength: 0)
            if ActionsDisplay.needsRerun(r) {
                Button("Relancer") { rerun(r) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .disabled(busy.contains(r.id))
                    .accessibilityLabel("Relancer \(r.title)")
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { if let url = r.htmlUrl.flatMap(URL.init(string:)) { openURL(url) } }
        .accessibilityAction(named: "Ouvrir sur GitHub") { if let url = r.htmlUrl.flatMap(URL.init(string:)) { openURL(url) } }
        .swipeActions {
            Button("Relancer", systemImage: "arrow.clockwise") { rerun(r) }
                .tint(.accentColor)
        }
    }

    @ViewBuilder
    private func statusIcon(_ r: WorkflowRun) -> some View {
        switch ActionsDisplay.state(r) {
        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .cancelled: Image(systemName: "slash.circle").foregroundStyle(.secondary)
        case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.red)
        case .running: ProgressView().controlSize(.small)
        }
    }

    private func rerun(_ r: WorkflowRun) {
        busy.insert(r.id)
        Task {
            defer { busy.remove(r.id) }
            do {
                try await github.api.rerun(repo.owner.login, repo.name, runId: r.id)
                info = "Exécution relancée."
                error = nil
                done += 1
                await load()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func dispatch(_ w: Workflow) {
        busy.insert(w.id)
        Task {
            defer { busy.remove(w.id) }
            do {
                try await github.api.dispatch(repo.owner.login, repo.name, workflowId: w.id, ref: repo.branch)
                info = ActionsDisplay.dispatched(w, branch: repo.branch)
                error = nil
                done += 1
            } catch { self.error = error.localizedDescription }
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

/// Les derniers commits d'une branche ; un toucher ouvre le commit sur GitHub.
struct CommitsView: View {
    let repo: Repo
    let branch: String
    @Environment(GitHubSession.self) private var github
    @Environment(\.openURL) private var openURL
    @State private var commits: [Commit] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        List {
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).foregroundStyle(Theme.red)
                    Button("Réessayer", systemImage: "arrow.clockwise") { Task { await load() } }
                        .frame(minHeight: 44)
                }
            }
            ForEach(commits) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).lineLimit(2)
                    Text(ActionsDisplay.commitDetail(c)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if let url = c.htmlUrl.flatMap(URL.init(string:)) { openURL(url) } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(ActionsDisplay.commitAccessibility(c))
                .accessibilityAddTraits(c.htmlUrl == nil ? [] : .isLink)
            }
        }
        .listStyle(.plain)
        .overlay {
            if loading && commits.isEmpty {
                ProgressView()
            } else if !loading && error == nil && commits.isEmpty {
                ContentUnavailableView("Aucun commit sur \(branch)", systemImage: "clock.arrow.circlepath")
            }
        }
        .refreshable { await load() }
        .task(id: branch) { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            commits = try await github.api.commits(repo.owner.login, repo.name, branch: branch)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
