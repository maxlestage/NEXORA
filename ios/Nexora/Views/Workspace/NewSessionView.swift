import NexoraKit
import SwiftUI

/// Nouvelle session (`new_session_screen.dart`) : une mission, un ou plusieurs
/// dépôts, un modèle. Une fois lancée, la session prend la place du formulaire.
struct NewSessionView: View {
    /// Dépôt déjà choisi (depuis la page d'un dépôt).
    var repo: Repo?
    var branch: String?
    var agent: Agent?
    /// Choisir un dépôt dès l'ouverture (depuis la fiche d'un agent).
    var askRepoFirst = false

    /// Un dépôt de la session et sa branche.
    struct Pick: Identifiable, Hashable {
        let repo: Repo
        var branch: String
        var id: String { repo.fullName }
    }

    @Environment(SettingsStore.self) private var settings
    @Environment(GitHubSession.self) private var github
    @Environment(SessionStore.self) private var sessions
    @State private var task = ""
    @State private var chosenAgent: Agent??
    @State private var model: ModelRef?
    @State private var level: ThinkLevel?
    @State private var repos: [Pick]?
    @State private var starting = false
    @State private var started: String?
    @State private var toast: Toast?
    @State private var pickingRepo = false
    @State private var creatingRepo = false
    @State private var pickingAgent = false
    @State private var branchFor: Pick?
    @State private var branchText = ""
    @State private var askedFirst = false
    @State private var photos: [ChatPhotoDraft] = []
    @State private var loadingPhotos = false
    @FocusState private var missionFocused: Bool

    private var currentAgent: Agent? { chosenAgent ?? agent }
    private var picks: [Pick] { repos ?? repo.map { [Pick(repo: $0, branch: branch ?? $0.branch)] } ?? [] }

    var body: some View {
        if let started {
            SessionView(sessionId: started)
        } else {
            form
        }
    }

    private var form: some View {
        @Bindable var settings = settings
        let ref = model ?? settings.resolve(currentAgent?.model)
        let effort = level ?? ThinkLevel.named(currentAgent?.level) ?? settings.defaultLevel
        return Form {
            Section {
                NexusOrb(size: 72, satellites: 12, interactive: false, speed: 1.4)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                TextField(
                    "Mission",
                    text: $task,
                    prompt: Text("Ex. : fais une galerie d'art 3D dans le navigateur avec Paquets"),
                    axis: .vertical
                )
                .lineLimit(3...8)
                .focused($missionFocused)
                missionPhotos
            } header: {
                Text("Mission")
            }

            Section {
                ForEach(Array(picks.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 8) {
                        Image(systemName: p.repo.isPrivate ? "lock" : "globe")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.repo.fullName)
                                .font(.body.monospaced().weight(.bold))
                                .lineLimit(1)
                            Text(NewSessionDisplay.repoDetail(index: i, branch: p.branch))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            branchText = p.branch
                            branchFor = p
                        } label: {
                            Image(systemName: "arrow.triangle.branch")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Branche")
                        Button {
                            remove(p)
                        } label: {
                            Image(systemName: "xmark")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Retirer")
                    }
                    .swipeActions {
                        Button("Retirer", systemImage: "xmark", role: .destructive) { remove(p) }
                    }
                }
                Button(picks.isEmpty ? "Ajouter un dépôt" : "Ajouter un autre dépôt", systemImage: "plus") {
                    pickingRepo = true
                }
                .disabled(!github.connected)
                Button("Créer un dépôt", systemImage: "folder.badge.plus") { creatingRepo = true }
                    .disabled(!github.connected)
            } header: {
                Text("Dépôts")
            } footer: {
                if let hint = NewSessionDisplay.reposFooter(connected: github.connected, count: picks.count) {
                    Text(hint)
                }
            }

            Section {
                ModelEffortButton(
                    current: ref,
                    level: effort,
                    onModel: { model = $0 },
                    onLevel: { level = $0 }
                )
                QuotaBadge(providerId: ref.providerId)
                Button {
                    pickingAgent = true
                } label: {
                    HStack {
                        Text(currentAgent?.emoji ?? "🤖")
                        Text(currentAgent?.name ?? "Agent généraliste").foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $settings.agentAutoCi) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Faire passer la CI GitHub")
                        Text(NewSessionDisplay.autoCiCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if settings.agentAutoCi {
                    Toggle(isOn: $settings.agentAutoMerge) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fusionner quand la CI est verte")
                            Text(NewSessionDisplay.autoMergeCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Agent")
            } footer: {
                Text(NewSessionDisplay.agentFooter(autoCi: settings.agentAutoCi))
            }

            Section {
                Button {
                    Task { await start(ref: ref) }
                } label: {
                    Label("Lancer la session", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(starting)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Nouvelle session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Toujours visible, même clavier ouvert ou formulaire long.
            ToolbarItem(placement: .confirmationAction) {
                Button("Lancer") {
                    Task { await start(ref: ref) }
                }
                .disabled(starting)
            }
        }
        .toast($toast)
        .sheet(isPresented: $pickingRepo) {
            RepoPickerSheet { add($0) }
        }
        .sheet(isPresented: $creatingRepo) {
            CreateRepoSheet { add($0) }
        }
        .sheet(isPresented: $pickingAgent) {
            AgentPickerSheet(selected: currentAgent) { chosenAgent = .some($0) }
        }
        .alert("Branche de travail", isPresented: Binding(get: { branchFor != nil }, set: { if !$0 { branchFor = nil } })) {
            TextField("main", text: $branchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            Button("Annuler", role: .cancel) {}
            Button("OK") {
                let b = branchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let p = branchFor, !b.isEmpty else { return }
                var list = picks
                if let i = list.firstIndex(where: { $0.id == p.id }) { list[i].branch = b }
                repos = list
            }
        }
        .onAppear {
            missionFocused = repo != nil
            if askRepoFirst && !askedFirst && picks.isEmpty && github.connected {
                askedFirst = true
                pickingRepo = true
            }
        }
    }

    private func remove(_ p: Pick) {
        var list = picks
        list.removeAll { $0.id == p.id }
        repos = list
    }

    private func add(_ r: Repo) {
        if picks.contains(where: { $0.repo.fullName == r.fullName }) {
            toast = Toast(text: "\(r.fullName) est déjà dans la session.")
            return
        }
        repos = picks + [Pick(repo: r, branch: r.branch)]
    }

    /// Des photos (maquette, capture d'écran…) envoyées avec la mission.
    private var missionPhotos: some View {
        HStack(spacing: 8) {
            PhotoAttachButton(photos: $photos, loading: $loadingPhotos)
            if photos.isEmpty && !loadingPhotos {
                Text("Joindre des photos (maquette, capture…)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                PhotoDraftStrip(photos: $photos, loading: loadingPhotos)
            }
        }
    }

    private func start(ref: ModelRef) async {
        let mission = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = NewSessionDisplay.startProblem(mission: mission, repoCount: picks.count) {
            toast = Toast(text: problem, error: true)
            if mission.isEmpty { missionFocused = true }
            return
        }
        starting = true
        let run = await sessions.start(
            task: mission,
            repos: picks.map { RepoTarget($0.repo.owner.login, $0.repo.name, $0.branch) },
            model: ref,
            agent: currentAgent,
            level: level,
            images: photos.map { LLMImage(data: $0.data) }
        )
        starting = false
        if let run { started = run.id }
    }
}
