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
                    .disabled(run.running)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    shipping = true
                } label: {
                    Label(WorkspaceText.validateLabel(accepted), systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(accepted == 0 || run.running)
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

    var body: some View {
        let groups = run.acceptedByRepo
        // Chaque dépôt modifié a-t-il déjà sa pull request ? Sinon on demande comment
        // envoyer (un dépôt sans pull request ne part jamais en direct par surprise).
        let hasPull = !groups.isEmpty && groups.allSatisfy { run.pulls[$0.0.fullName] != nil }
        NavigationStack {
            Form {
                if groups.count > 1 {
                    Section {
                        Text("Un commit par dépôt : " + groups.map { "\($0.0.fullName) (\($0.1.count))" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Message de commit", text: $message, axis: .vertical)
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

/// La comparaison d'un brouillon, avec Accepter / Refuser / Modifier.
struct DraftDiffView: View {
    let run: AgentRun
    let path: String

    @Environment(\.colorScheme) private var scheme
    @State private var whole = false
    @State private var diff: DiffResult?
    @State private var error: String?
    @State private var editing = false
    @State private var toast: Toast?
    /// Les colonnes des numéros et des signes suivent la taille du texte.
    @ScaledMetric(relativeTo: .caption2) private var numberWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var signWidth: CGFloat = 16

    var body: some View {
        let ok = !run.rejected.contains(path)
        let content = run.changes.get(path) ?? nil
        let deleted = content == nil
        Group {
            if let error {
                ContentUnavailableView("Version d'origine illisible : \(error)", systemImage: "exclamationmark.triangle")
            } else if let d = diff {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text(path).font(.caption.monospaced()).lineLimit(1)
                        Pill(text: "+\(d.added)", color: Theme.green)
                        Pill(text: "−\(d.removed)", color: Theme.red)
                        if !ok { Pill(text: "refusé", color: .gray) }
                        if d.truncated { Pill(text: "comparaison simplifiée", color: Theme.amber) }
                        Spacer(minLength: 0)
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
                        run.setAccepted(path, false)
                    } label: {
                        Label("Refuser", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.red)
                } else {
                    Button {
                        run.setAccepted(path, true)
                    } label: {
                        Label("Accepter", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .padding(12)
            .background(.bar)
        }
        .task(id: content) { await load() }
        .sheet(isPresented: $editing) {
            DraftEditor(text: content ?? "") { saved in
                run.editDraft(path, saved.hasSuffix("\n") ? saved : saved + "\n")
                toast = Toast(text: "Brouillon modifié")
            }
        }
        .toast($toast)
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
    @State var text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

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
                    ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Enregistrer") {
                            onSave(text)
                            dismiss()
                        }
                    }
                }
        }
    }
}
