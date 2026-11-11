import NexoraKit
import SwiftUI

// Les petites pièces de l'atelier : couleurs d'état, choix d'un dépôt, état de
// l'arrière-plan.

extension SessionStatus {
    /// La couleur de l'état (`statusColor`).
    var color: Color {
        switch self {
        case .running: .accentColor
        case .review: Theme.amber
        case .shipped: Theme.violet
        case .done: Theme.green
        case .stopped: Theme.red
        }
    }
}

/// Le symbole d'un outil de l'agent (`_toolLook`).
func toolSymbol(_ tool: String?) -> String {
    switch tool {
    case "read_file": "doc.text"
    case "find_in_file": "text.magnifyingglass"
    case "search_code": "magnifyingglass"
    case "list_files": "folder"
    case "edit_file": "pencil"
    case "write_file": "doc.badge.plus"
    case "delete_file": "trash"
    case "github": "cloud"
    case "use_skill", "read_skill_file": "sparkles"
    case "delegate": "person.2"
    case "ci": "flask"
    default: "wrench.and.screwdriver"
    }
}

/// Une demande de choix de dépôt : `pickRepo` de l'app Flutter.
struct RepoPickerSheet: View {
    let onPick: (Repo) -> Void

    @Environment(GitHubSession.self) private var github
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    creating = true
                } label: {
                    Label("Créer un nouveau dépôt", systemImage: "folder.badge.plus")
                }
                if github.loading { ProgressView() }
                ForEach(github.repos.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }) { r in
                    Button {
                        onPick(r)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: r.isPrivate ? "lock" : "globe")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.fullName).foregroundStyle(.primary)
                                if let d = r.description, !d.isEmpty {
                                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Choisir un dépôt")
            .navigationTitle("Dépôt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .task { if github.repos.isEmpty { await github.loadRepos() } }
            .sheet(isPresented: $creating) {
                CreateRepoSheet { repo in
                    onPick(repo)
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Pendant le travail : est-ce que le système laisse l'app continuer en
/// arrière-plan ? (Diagnostic, pour savoir à quoi s'attendre en quittant l'app ;
/// `ui/widgets/background_status.dart`.)
struct BackgroundStatusView: View {
    @State private var status: BackgroundStatus?

    var body: some View {
        Group {
            if let note = status?.note {
                Label {
                    Text(note.text)
                } icon: {
                    Image(systemName: note.symbol)
                }
                .font(.caption)
                .foregroundStyle(note.tone == .good ? Theme.green : Theme.amber)
                .padding(.top, 4)
            }
        }
        .task {
            while !Task.isCancelled {
                let s = BackgroundWork.shared.jobs.status()
                if s != status { status = s }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
