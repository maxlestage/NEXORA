import NexoraKit
import SwiftUI
import UIKit

/// L'onglet Code une fois connecté (`_CodeHome` de `ui/github/github_screen.dart`) :
/// les sessions de l'agent (comme Claude Code) et les dépôts.
struct CodeHomeView: View {
    enum Part: Hashable {
        case sessions, repos
    }

    @Environment(SessionStore.self) private var sessions
    @Environment(GitHubSession.self) private var github
    @State private var part: Part = .sessions
    @State private var newSession = false

    var body: some View {
        Group {
            switch part {
            case .sessions: SessionsListView(onNew: { newSession = true })
            case .repos: ReposView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Partie", selection: $part) {
                Text(SessionsDisplay.pickerLabel(
                    total: sessions.sessions.count,
                    running: sessions.runningCount,
                    toReview: sessions.reviewCount
                ))
                .tag(Part.sessions)
                Text("Dépôts (\(github.repos.count))").tag(Part.repos)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .navigationTitle("Code")
        .toolbar {
            if part == .sessions {
                ToolbarItem(placement: .primaryAction) {
                    Button("Nouvelle session", systemImage: "plus") { newSession = true }
                }
            }
        }
        .navigationDestination(isPresented: $newSession) { NewSessionView() }
    }
}

/// Les sessions de l'agent, comme la liste de Claude Code (`sessions_list.dart`).
struct SessionsListView: View {
    var onNew: (() -> Void)?

    @Environment(SessionStore.self) private var sessions
    @Environment(SettingsStore.self) private var settings
    @State private var removing: AgentRun?
    @State private var toast: Toast?
    @State private var query = ""
    @State private var stopped = 0

    var body: some View {
        Group {
            if sessions.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.sessions.isEmpty {
                empty
            } else {
                list
            }
        }
        .confirmationDialog(
            "Supprimer la session ?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { run in
            Button("Supprimer", role: .destructive) { delete(run) }
            Button("Annuler", role: .cancel) {}
        } message: { run in
            Text(SessionsDisplay.deleteWarning(drafts: run.changes.count, running: run.status == .running) ?? "")
        }
        .toast($toast)
        .sensoryFeedback(.warning, trigger: stopped) { _, _ in settings.haptics }
    }

    /// Les sessions groupées : à relire, en cours, puis récentes ; avec une
    /// recherche dès qu'il y en a beaucoup.
    @ViewBuilder private var list: some View {
        let all = sessions.sessions
        let shown = all.filter { AgentsDisplay.matches(query, $0.task, $0.reposLabel) }
        let content = List {
            if query.isEmpty { RoutinesBanner() }
            ForEach(SessionsDisplay.sections(shown) { $0.status }, id: \.kind) { section in
                Section {
                    ForEach(section.items, id: \.id) { run in row(run) }
                } header: {
                    if let title = section.title { Text(title) }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if shown.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        if all.count >= SessionsDisplay.searchThreshold {
            content.searchable(text: $query, prompt: "Rechercher une session")
        } else {
            content
        }
    }

    private func row(_ run: AgentRun) -> some View {
        NavigationLink {
            SessionView(sessionId: run.id)
        } label: {
            SessionTile(run: run)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { askDelete(run) } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if run.status == .running {
                Button { stop(run) } label: {
                    Label("Arrêter", systemImage: "stop.fill")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            ForEach(SessionsDisplay.quickActions(run.status), id: \.self) { action in
                switch action {
                case .stop:
                    Button("Arrêter l'agent", systemImage: "stop.fill") { stop(run) }
                case .copyTask:
                    Button("Copier la mission", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = run.task
                        toast = Toast(text: "Mission copiée")
                    }
                case .delete:
                    Button("Supprimer", systemImage: "trash", role: .destructive) { askDelete(run) }
                }
            }
        }
    }

    /// Supprime tout de suite s'il n'y a rien à perdre, sinon demande confirmation
    /// (brouillons non envoyés ou agent encore au travail).
    private func askDelete(_ run: AgentRun) {
        if SessionsDisplay.deleteWarning(drafts: run.changes.count, running: run.status == .running) == nil {
            delete(run)
        } else {
            removing = run
        }
    }

    private func stop(_ run: AgentRun) {
        sessions.stop(run.id)
        stopped += 1
        toast = Toast(text: "Agent arrêté : brouillons gardés")
    }

    private func delete(_ run: AgentRun) {
        sessions.delete(run.id)
        toast = Toast(text: "Session supprimée")
    }

    private var empty: some View {
        ScrollView {
            VStack(spacing: 12) {
                RoutinesBanner()
                    .padding(.bottom, 12)
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Aucune session")
                    .font(.title2.weight(.heavy))
                Text("Donnez une mission à l'agent sur vos dépôts. Il continue même si vous quittez l'écran.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let onNew {
                    Button("Nouvelle session", systemImage: "plus", action: onNew)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                }
            }
            .padding(24)
        }
    }
}

/// Une session dans la liste.
struct SessionTile: View {
    let run: AgentRun

    var body: some View {
        let status = run.status
        let stats = run.stats
        HStack(spacing: 12) {
            Group {
                switch status {
                case .running: ProgressView().controlSize(.small)
                case .shipped: Image(systemName: "arrow.triangle.merge").foregroundStyle(Theme.violet)
                case .stopped: Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.red)
                default: Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.task)
                    .font(.headline)
                    .lineLimit(1)
                subtitle(status, stats.added, stats.removed)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if status == .review {
                Circle().fill(Color.accentColor).frame(width: 9, height: 9)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SessionsDisplay.tileAccessibility(
            task: run.task, status: status, reposLabel: run.reposLabel,
            added: stats.added, removed: stats.removed, ago: WorkspaceText.ago(run.updatedAt)
        ))
    }

    private func subtitle(_ status: SessionStatus, _ added: Int, _ removed: Int) -> Text {
        let base = WorkspaceText.tileSubtitle(status, reposLabel: run.reposLabel)
        let ago = WorkspaceText.ago(run.updatedAt)
        if added + removed > 0 && status != .review {
            let plus = Text("+\(added) ").foregroundStyle(Theme.green)
            let minus = Text("−\(removed)").foregroundStyle(Theme.red)
            return Text("\(base) · \(plus)\(minus) · \(ago)")
        }
        return Text(verbatim: "\(base) · \(ago)")
    }
}

/// L'accès aux routines, en tête de la liste des sessions.
struct RoutinesBanner: View {
    @Environment(RoutineBook.self) private var routines

    var body: some View {
        NavigationLink {
            RoutinesView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "alarm").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Routines").font(.headline)
                    Text(WorkspaceText.routinesBanner(active: routines.activeCount, total: routines.routines.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
