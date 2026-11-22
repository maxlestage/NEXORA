import NexoraKit
import SwiftUI

/// La comparaison d'un brouillon avec la version d'origine (calculée à part pour
/// ne pas bloquer l'écran sur un gros fichier).
@MainActor
func draftDiff(_ run: AgentRun, _ path: String) async throws -> DiffResult {
    let before = try await run.original(path)
    let after = run.changes.get(path) ?? nil
    return await Task.detached { lineDiff(before, after) }.value
}

/// Relire les brouillons de l'agent, choisir ceux à garder, puis les valider
/// (`draft_review_screen.dart`) : commit ou pull request, puis la CI est suivie.
struct DraftReviewView: View {
    let run: AgentRun
    /// Un message pour l'écran de la session (envoi réussi ou refusé).
    var onMessage: (Toast) -> Void = { _ in }

    @Environment(SessionStore.self) private var sessions
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var shipping = false
    /// L'envoi sur GitHub est en cours (plusieurs secondes) : Valider attend.
    @State private var sending = false
    @State private var toast: Toast?
    /// Augmente à chaque envoi réussi (vibration).
    @State private var shipped = 0

    var body: some View {
        let paths = run.changes.keys.sorted()
        let accepted = run.accepted.count
        Group {
            if paths.isEmpty {
                ContentUnavailableView {
                    Label("Plus rien à valider", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.green)
                } description: {
                    Text("Tous les brouillons ont été envoyés.")
                }
            } else {
                List {
                    Section {
                        Text(DraftsDisplay.intro)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        ForEach(paths, id: \.self) { path in
                            DraftRow(run: run, path: path)
                        }
                    }
                }
            }
        }
        .navigationTitle("Valider les brouillons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Une action directe au lieu d'un menu à deux choix.
            if !paths.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(DraftsDisplay.bulkLabel(accepted: accepted, total: paths.count)) {
                        run.setAllAccepted(DraftsDisplay.bulkAccepts(accepted: accepted, total: paths.count))
                    }
                    .frame(minHeight: 44)
                    .disabled(run.running || sending)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    shipping = true
                } label: {
                    if let label = DraftsDisplay.sendingLabel(sending) {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(label)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label(WorkspaceText.validateLabel(accepted), systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!DraftsDisplay.canValidate(accepted: accepted, running: run.running, sending: sending))
                if let hint = DraftsDisplay.emptyHint(accepted: accepted, total: paths.count) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(.bar)
        }
        .sensoryFeedback(.success, trigger: shipped) { _, _ in settings.haptics }
        .sheet(isPresented: $shipping) {
            ShipSheet(run: run) { message, branch, openPr, hasPull in
                Task { await ship(message: message, branch: branch, openPr: openPr, hasPull: hasPull) }
            }
            .presentationDetents([.medium, .large])
        }
        .toast($toast)
    }

    /// Envoie les brouillons acceptés : chaque dépôt qui a déjà sa pull request la
    /// met à jour ; les autres en ouvrent une (si demandé), ou un commit direct.
    private func ship(message: String, branch: String?, openPr: Bool, hasPull: Bool) async {
        // Un seul envoi à la fois : un second enverrait les mêmes fichiers deux fois.
        guard !sending else { return }
        sending = true
        defer { sending = false }
        do {
            let results = try await run.commitAll(
                message: message.isEmpty ? run.task : message,
                targetBranch: branch,
                openPr: openPr
            )
            // Les tests GitHub sont suivis ; en cas d'échec, l'agent corrige.
            let sessions = sessions
            let run = run
            Task { await sessions.verify(run) }
            let pulls = results.filter(\.isPull)
            if !results.isEmpty { shipped += 1 }
            if let text = WorkspaceText.shipToast(results, hasPull: hasPull) {
                onMessage(Toast(text: text))
                toast = Toast(text: text)
            }
            if !hasPull, let first = pulls.first, let u = URL(string: first.result) { openURL(u) }
            if run.changes.isEmpty { dismiss() }
        } catch {
            toast = Toast(text: error.localizedDescription, error: true)
        }
    }
}

/// Valider les brouillons : message de commit, et comment envoyer.
struct ShipSheet: View {
    let run: AgentRun
    /// (message, nouvelle branche ou `nil`, ouvrir une pull request, PR déjà ouverte).
    let onShip: (String, String?, Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var branch = WorkspaceText.newBranch()
    @State private var pr = true
    @State private var ready = false

    /// Ce qui empêche d'ouvrir la pull request sur ce nom de branche (`nil` : il convient).
    private var branchProblem: String? { WorkspaceText.branchProblem(branch) }

    var body: some View {
        let groups = run.acceptedByRepo
        // Chaque dépôt modifié a-t-il déjà sa pull request ? Sinon on demande comment
        // envoyer (un dépôt sans pull request ne part jamais en direct par surprise).
        let hasPull = !groups.isEmpty && groups.allSatisfy { run.pulls[$0.0.fullName] != nil }
        NavigationStack {
            Form {
                Section {
                    TextField("Message de commit", text: $message, prompt: Text("Message (sinon : la mission)"), axis: .vertical)
                        .lineLimit(1...6)
                } footer: {
                    if groups.count > 1 {
                        Text("Un commit par dépôt\n" + groups.map { WorkspaceText.shipRepo($0.0.fullName, files: $0.1.count) }.joined(separator: "\n"))
                    }
                }
                if hasPull {
                    Section {
                        Text("Les changements s'ajoutent à la branche et à la pull request déjà ouvertes par cette session.")
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Section {
                        Toggle(isOn: $pr) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nouvelle branche + pull request")
                                Text(WorkspaceText.prSubtitle(pr: pr, multi: run.multi, branch: run.branch))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if pr {
                            TextField("Branche", text: $branch)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Nom de la branche")
                        }
                    } footer: {
                        if pr, let problem = branchProblem {
                            Text(problem).foregroundStyle(.red)
                        }
                    }
                }
                Section {
                    Button {
                        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        let target = hasPull || !pr ? nil : branch.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                        onShip(msg, target, hasPull || pr, hasPull)
                    } label: {
                        Label(WorkspaceText.shipButton(hasPull: hasPull, repos: groups.count, pr: pr), systemImage: "icloud.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!hasPull && pr && branchProblem != nil)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(WorkspaceText.validateLabel(run.accepted.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
        .onAppear {
            if !ready {
                ready = true
                message = run.commitMessage
            }
        }
    }
}

/// Un brouillon : accepté ou non, ce qui change, et sa comparaison.
struct DraftRow: View {
    let run: AgentRun
    let path: String

    @State private var diff: DiffResult?
    @State private var failed = false

    var body: some View {
        let content = run.changes.get(path) ?? nil
        let deleted = content == nil
        let ok = !run.rejected.contains(path)
        let kind: DraftsDisplay.Kind = deleted
            ? .deleted
            : ((run.originals[path] ?? nil) == nil && diff != nil ? .added : .modified)
        HStack(spacing: 6) {
            Button {
                run.setAccepted(path, !ok)
            } label: {
                Image(systemName: ok ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(ok ? Color.accentColor : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(ok ? "Décocher \(path)" : "Cocher \(path)")
            NavigationLink {
                DraftDiffView(run: run, path: path)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(path)
                        .font(.footnote.monospaced())
                        .strikethrough(!ok)
                    HStack(spacing: 6) {
                        switch kind {
                        case .deleted: Pill(text: kind.label, color: Theme.red)
                        case .added: Pill(text: kind.label, color: Theme.green)
                        case .modified: Pill(text: kind.label, color: Theme.amber)
                        }
                        if let diff {
                            Pill(text: "+\(diff.added)", color: Theme.green)
                            Pill(text: "−\(diff.removed)", color: Theme.red)
                        } else if failed {
                            Pill(text: "origine illisible", color: .gray)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DraftsDisplay.rowAccessibility(
                    path: path, kind: kind, added: diff?.added, removed: diff?.removed, accepted: ok
                ))
            }
        }
        // Balayage : cocher ou décocher sans viser la case.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(ok ? "Décocher" : "Cocher", systemImage: ok ? "xmark" : "checkmark") {
                run.setAccepted(path, !ok)
            }
            .tint(ok ? Theme.red : Theme.green)
        }
        // Recalculée seulement si le brouillon a changé (modifié à la main).
        .task(id: content) {
            do {
                diff = try await draftDiff(run, path)
                failed = false
            } catch {
                failed = true
            }
        }
    }
}

/// La comparaison d'un brouillon, avec Cocher / Décocher / Modifier, et
/// « Suivant » pour relire tous les brouillons sans revenir à la liste.
struct DraftDiffView: View {
    let run: AgentRun

    /// Le brouillon montré (change avec « Suivant »).
    @State private var path: String

    @Environment(\.colorScheme) private var scheme
    @Environment(SettingsStore.self) private var settings
    @State private var whole = false
    @State private var diff: DiffResult?
    @State private var error: String?
    @State private var editing = false
    @State private var toast: Toast?
    /// Compteur des choix Cocher / Décocher, pour la vibration.
    @State private var toggled = 0
    /// Les colonnes des numéros et des signes suivent la taille du texte.
    @ScaledMetric(relativeTo: .caption2) private var numberWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var signWidth: CGFloat = 16

    init(run: AgentRun, path: String) {
        self.run = run
        _path = State(initialValue: path)
    }

    var body: some View {
        let ok = !run.rejected.contains(path)
        let content = run.changes.get(path) ?? nil
        let deleted = content == nil
        let paths = run.changes.keys.sorted()
        let next = DraftsDisplay.next(after: path, in: paths)
        Group {
            if let error {
                ContentUnavailableView(
                    DraftsDisplay.loadErrorTitle,
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if let d = diff {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(path).font(.caption.monospaced()).lineLimit(1)
                        Pill(text: "+\(d.added)", color: Theme.green)
                        Pill(text: "−\(d.removed)", color: Theme.red)
                        if !ok { Pill(text: DraftsDisplay.uncheckedPill, color: .gray) }
                        if d.truncated { Pill(text: "comparaison simplifiée", color: Theme.amber) }
                        Spacer(minLength: 0)
                        if let place = DraftsDisplay.position(of: path, in: paths) {
                            Text(place)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    lines(d)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(path.components(separatedBy: "/").last ?? path)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    whole.toggle()
                } label: {
                    Image(systemName: whole ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(whole ? "Changements seulement" : "Fichier entier")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                if !deleted {
                    Button {
                        editing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Modifier")
                }
                if ok {
                    Button(role: .destructive) {
                        toggle(false)
                    } label: {
                        Label(DraftsDisplay.toggleLabel(accepted: true), systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.red)
                } else {
                    Button {
                        toggle(true)
                    } label: {
                        Label(DraftsDisplay.toggleLabel(accepted: false), systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let next {
                    Button {
                        diff = nil
                        error = nil
                        path = next
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Brouillon suivant")
                    .accessibilityHint(next)
                }
            }
            .controlSize(.large)
            .padding(12)
            .background(.bar)
        }
        // Relancée quand le brouillon change ou qu'on passe au suivant.
        .task(id: DraftKey(path: path, content: content)) { await load() }
        .sheet(isPresented: $editing) {
            DraftEditor(text: content ?? "") { saved in
                run.editDraft(path, saved.hasSuffix("\n") ? saved : saved + "\n")
                toast = Toast(text: "Brouillon modifié")
            }
        }
        .toast($toast)
        .sensoryFeedback(.selection, trigger: toggled) { _, _ in settings.haptics }
    }

    /// Coche ou décoche le brouillon montré, avec un avis et une vibration.
    private func toggle(_ accepted: Bool) {
        run.setAccepted(path, accepted)
        toggled += 1
        toast = Toast(text: DraftsDisplay.toggleToast(accepted: accepted))
    }

    private struct DraftKey: Hashable {
        let path: String
        let content: String?
    }

    private func load() async {
        do {
            diff = try await draftDiff(run, path)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func lines(_ d: DiffResult) -> some View {
        let rows: [DiffLine?] = whole ? d.lines.map { Optional($0) } : withContext(d.lines)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, line in
                    if let l = line {
                        row(l)
                    } else {
                        Text("⋯ lignes identiques")
                            .font(.caption2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(Theme.violet.opacity(0.08))
                    }
                }
            }
        }
        .background(scheme == .dark ? Color(hex: 0x0A0A12) : Color(hex: 0xFAFAFD))
    }

    private func row(_ l: DiffLine) -> some View {
        let (bg, sign): (Color, String) = switch l.kind {
        case .added: (Theme.green.opacity(0.14), "+")
        case .removed: (Theme.red.opacity(0.14), "−")
        case .same: (.clear, " ")
        }
        return HStack(alignment: .top, spacing: 0) {
            Text(verbatim: (l.newNo ?? l.oldNo).map { "\($0)" } ?? "")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(width: numberWidth, alignment: .trailing)
            Text(sign)
                .font(.caption.monospaced())
                .frame(width: signWidth)
            Text(l.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(bg)
    }
}

/// Modifier un brouillon à la main.
struct DraftEditor: View {
    /// Le texte à l'ouverture : sert à savoir s'il y a des retouches à perdre.
    private let original: String
    let onSave: (String) -> Void

    @State private var text: String
    @State private var confirmLeave = false
    @Environment(\.dismiss) private var dismiss

    init(text: String, onSave: @escaping (String) -> Void) {
        original = text
        self.onSave = onSave
        _text = State(initialValue: text)
    }

    private var losesEdit: Bool { DraftsDisplay.losesEdit(original: original, text: text) }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.footnote.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 8)
                .navigationTitle("Modifier le brouillon")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            if losesEdit { confirmLeave = true } else { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        // Rien de retouché : rien à enregistrer (ni faux avis « Brouillon modifié »).
                        Button("Enregistrer") { save() }
                            .disabled(!losesEdit)
                    }
                }
                // Des retouches en cours : un balayage ne ferme plus la fenêtre sans demander.
                .interactiveDismissDisabled(losesEdit)
                .confirmationDialog(DraftsDisplay.leaveEditTitle, isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Enregistrer") { save() }
                    Button("Abandonner", role: .destructive) { dismiss() }
                    Button("Continuer à modifier", role: .cancel) {}
                } message: {
                    Text(DraftsDisplay.leaveEditMessage)
                }
        }
    }

    private func save() {
        onSave(text)
        dismiss()
    }
}
