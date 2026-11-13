import NexoraKit
import SwiftUI

/// Les routines (`routines_screen.dart`) : une mission relancée toute seule, à
/// activer, désactiver et configurer.
struct RoutinesView: View {
    @Environment(RoutineBook.self) private var routines
    @State private var toast: Toast?
    @State private var creating = false
    @State private var started: String?

    var body: some View {
        List {
            ForEach(routines.routines) { r in
                NavigationLink {
                    RoutineEditorView(routine: r)
                } label: {
                    RoutineRow(routine: r, error: routines.errors[r.id]) { on in
                        Task {
                            let err = await routines.setEnabled(r.id, on)
                            toast = Toast(
                                text: err ?? (on ? "Routine « \(r.name) » activée" : "Routine désactivée"),
                                error: err != nil
                            )
                        }
                    }
                }
                // Action fréquente, avant seulement dans la fiche de la routine.
                .swipeActions(edge: .leading) {
                    Button("Lancer", systemImage: "play.fill") {
                        Task { await runNow(r) }
                    }
                    .tint(Color.accentColor)
                }
            }
        }
        .overlay {
            if routines.routines.isEmpty {
                ContentUnavailableView {
                    Label("Aucune routine", systemImage: "alarm")
                } description: {
                    Text(RoutinesDisplay.emptyHint)
                } actions: {
                    Button("Créer une routine") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nouvelle routine", systemImage: "plus") { creating = true }
            }
        }
        .navigationDestination(isPresented: $creating) { RoutineEditorView(routine: nil) }
        .navigationDestination(item: $started) { id in SessionView(sessionId: id) }
        .toast($toast)
    }

    private func runNow(_ r: Routine) async {
        if let run = await routines.runNow(r.id) {
            started = run.id
        } else {
            toast = Toast(text: r.runner == .github ? "Routine lancée sur GitHub" : "Le passage précédent travaille encore")
        }
    }
}

/// Une routine dans la liste, avec son interrupteur.
struct RoutineRow: View {
    let routine: Routine
    let error: String?
    let onToggle: (Bool) -> Void

    var body: some View {
        let r = routine
        HStack(spacing: 12) {
            Image(systemName: r.runner == .github ? "icloud.and.arrow.up" : "iphone")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).fontWeight(.bold)
                Text(RoutinesDisplay.rowDetail(r))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if let error {
                    Text(error).font(.caption).foregroundStyle(Theme.red).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Toggle("Active", isOn: Binding(get: { r.enabled }, set: { onToggle($0) }))
                .labelsHidden()
                .accessibilityLabel("Routine active : \(r.name)")
        }
    }
}

/// Créer ou configurer une routine.
struct RoutineEditorView: View {
    let routine: Routine?

    @Environment(RoutineBook.self) private var routines
    @Environment(SettingsStore.self) private var settings
    @Environment(GitHubSession.self) private var github
    @Environment(\.dismiss) private var dismiss
    @State private var r: Routine
    @State private var window: Bool
    @State private var saving = false
    @State private var pickingRepo = false
    @State private var toast: Toast?
    @State private var started: String?
    @State private var confirmDelete = false

    init(routine: Routine?) {
        self.routine = routine
        let r = routine ?? Routine(
            id: String(Int(Date().timeIntervalSince1970 * 1000)), name: "", task: "", repos: [], startMinute: 11 * 60
        )
        _r = State(initialValue: r)
        _window = State(initialValue: r.endMinute != nil)
    }

    /// Une heure de la journée (minutes depuis minuit) comme date d'aujourd'hui.
    private func timeBinding(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                let m = get()
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                set((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }
        )
    }

    var body: some View {
        let model = settings.resolve(r.model)
        let level = ThinkLevel.named(r.level) ?? settings.defaultLevel
        let agents = Catalog.cloudAgents
        let agent = agents.first { $0.id == r.cloudAgent } ?? agents.first
        var preview = r
        preview.endMinute = window ? (r.endMinute ?? 23 * 60) : nil
        return Form {
            Section {
                Toggle("Routine active", isOn: $r.enabled)
                TextField("Nom", text: $r.name)
            }

            Section {
                TextField(
                    "Mission à chaque passage",
                    text: $r.task,
                    prompt: Text("Ex. : optimise l'app, corrige les bugs et vérifie que tout fonctionne"),
                    axis: .vertical
                )
                .lineLimit(3...8)
            } header: {
                Text("Mission à chaque passage")
            }

            Section {
                ForEach(r.repos, id: \.self) { spec in
                    HStack {
                        Text(spec).font(.body.monospaced())
                        Spacer()
                        Button {
                            r.repos.removeAll { $0 == spec }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Retirer \(spec)")
                    }
                }
                Button("Ajouter un dépôt", systemImage: "plus") { pickingRepo = true }
                    .disabled(!github.connected)
            } header: {
                Text("Dépôts")
            } footer: {
                if let hint = RoutinesDisplay.reposFooter(connected: github.connected) { Text(hint) }
            }

            Section {
                Picker("Toutes les", selection: $r.everyMinutes) {
                    ForEach(Routine.intervals, id: \.self) { m in
                        Text(WorkspaceText.interval(m)).tag(m)
                    }
                }
                DatePicker(
                    r.everyMinutes >= 1440 ? "Chaque jour à \(Routine.hm(r.startMinute))" : "À partir de \(Routine.hm(r.startMinute))",
                    selection: timeBinding({ r.startMinute }, { r.startMinute = $0 }),
                    displayedComponents: .hourAndMinute
                )
                if r.everyMinutes < 1440 {
                    Toggle(isOn: Binding(get: { window }, set: { v in
                        window = v
                        r.endMinute = v ? (r.endMinute ?? 23 * 60) : nil
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Seulement pendant une plage horaire")
                            Text(window ? "Sinon : 24 h/24" : "Jour et nuit (24 h/24)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if window {
                        DatePicker(
                            "Jusqu'à \(Routine.hm(r.endMinute ?? 23 * 60))",
                            selection: timeBinding({ r.endMinute ?? 23 * 60 }, { r.endMinute = $0 }),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            } header: {
                Text("Quand")
            } footer: {
                Text("\(preview.scheduleLabel).")
            }

            Section {
                Picker("Où", selection: $r.runner) {
                    Label("Téléphone", systemImage: "iphone").tag(RoutineRunner.app)
                    Label("GitHub 24 h/24", systemImage: "cloud").tag(RoutineRunner.github)
                }
                .pickerStyle(.segmented)
                if r.runner == .app {
                    Text("Une session de l'agent NEXORA, avec votre modèle. Elle tourne quand l'app est ouverte ou en arrière-plan ; un passage manqué est rattrapé au retour dans l'app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ModelEffortButton(
                        current: model,
                        level: level,
                        onModel: { r.model = $0.key },
                        onLevel: { r.level = $0.rawValue }
                    )
                    Toggle("Faire passer la CI GitHub", isOn: $r.autoCi)
                    if r.autoCi {
                        Toggle("Fusionner quand la CI est verte", isOn: $r.autoMerge)
                    }
                } else {
                    Text("Un workflow planifié est écrit dans chaque dépôt : il tourne sur les serveurs de GitHub, même téléphone éteint, et ouvre une pull request. Il faut la clé de l'agent en secret du dépôt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Agent cloud", selection: $r.cloudAgent) {
                        ForEach(agents) { a in
                            Text("\(a.emoji) \(a.name)").tag(a.id)
                        }
                    }
                    if let agent {
                        Text("Secret à ajouter : \(agent.secrets.joined(separator: " · "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Où")
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if saving { ProgressView() } else { Image(systemName: "checkmark") }
                        Text("Enregistrer")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
                if routine != nil {
                    Button {
                        Task { await runNow() }
                    } label: {
                        Label("Lancer maintenant", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle(routine == nil ? "Nouvelle routine" : "Routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if routine != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Supprimer", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .confirmationDialog("Supprimer la routine ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                Task {
                    await routines.delete(r.id)
                    dismiss()
                }
            }
            Button("Annuler", role: .cancel) {}
        }
        .sheet(isPresented: $pickingRepo) {
            RepoPickerSheet { repo in
                let spec = "\(repo.fullName)@\(repo.branch)"
                if !r.repos.contains(where: { $0.components(separatedBy: "@").first == repo.fullName }) {
                    r.repos.append(spec)
                }
            }
        }
        .navigationDestination(item: $started) { id in SessionView(sessionId: id) }
        .toast($toast)
    }

    private func save() async {
        if let problem = RoutinesDisplay.saveProblem(task: r.task, repos: r.repos) {
            toast = Toast(text: problem, error: true)
            return
        }
        let task = r.task.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
        r.name = name.isEmpty ? RoutinesDisplay.defaultName(task) : name
        r.task = task
        r.endMinute = window ? (r.endMinute ?? 23 * 60) : nil
        // Une nouvelle routine part du prochain créneau (pas de rattrapage).
        if routine == nil { r.lastRun = Date() }
        saving = true
        let err = await routines.save(r)
        saving = false
        if let err {
            toast = Toast(text: "Enregistrée, mais GitHub a refusé : \(err)", error: true)
            return
        }
        toast = Toast(text: "Routine enregistrée")
        dismiss()
    }

    private func runNow() async {
        if let run = await routines.runNow(r.id) {
            started = run.id
        } else {
            toast = Toast(text: r.runner == .github ? "Routine lancée sur GitHub" : "Le passage précédent travaille encore")
        }
    }
}
