import NexoraKit
import SwiftUI

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
                let running = sessions.runningCount
                Text(running > 0 ? "Sessions (\(running) en cours)" : "Sessions (\(sessions.sessions.count))")
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
    @State private var removing: AgentRun?
    @State private var toast: Toast?

    var body: some View {
        Group {
            if sessions.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.sessions.isEmpty {
                empty
            } else {
                List {
                    RoutinesBanner()
                    ForEach(sessions.sessions, id: \.id) { run in
                        NavigationLink {
                            SessionView(sessionId: run.id)
                        } label: {
                            SessionTile(run: run)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                if run.changes.isEmpty {
                                    delete(run)
                                } else {
                                    removing = run
                                }
                            } label: {
                                Label("Supprimer", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
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
            Text("\(run.changes.count) brouillon(s) non envoyé(s) seront perdus.")
        }
        .toast($toast)
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
                Text("Une session = une mission pour l'agent, sur un ou plusieurs dépôts. Elle travaille même quand vous quittez l'écran, et vous pouvez la reprendre avec de nouvelles instructions.")
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
        .accessibilityElement(children: .combine)
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
