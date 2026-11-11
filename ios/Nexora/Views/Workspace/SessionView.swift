import NexoraKit
import SwiftUI

/// Un texte à lire en entier (appui long sur une étape).
struct FullTextItem: Identifiable {
    let title: String
    let text: String
    var id: String { title + String(text.count) }
}

/// Une session (`session_screen.dart`) : le travail de l'agent pas à pas, en
/// direct, ses brouillons à valider, la CI et les pull requests, et un champ pour
/// lui donner une nouvelle instruction (même pendant le travail).
struct SessionView: View {
    let sessionId: String

    @Environment(SessionStore.self) private var sessions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var input = ""
    @State private var toast: Toast?
    @State private var full: FullTextItem?
    @State private var reviewing = false
    @State private var showDown = false
    @FocusState private var focused: Bool

    var body: some View {
        if let run = sessions.byId(sessionId) {
            content(run)
        } else {
            ContentUnavailableView("Session introuvable", systemImage: "questionmark.folder")
        }
    }

    private func content(_ run: AgentRun) -> some View {
        let stats = run.stats
        let busy = run.running || run.shipping
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    header(run, stats)
                    chips(run)
                    if !run.running && !run.shipping && !run.stranded.isEmpty { stranded(run) }
                    if !run.ciNote.isEmpty { ciNote(run) }
                    ForEach(run.ci.keys.sorted(), id: \.self) { key in
                        if let report = run.ci[key] { ciCard(run, key, report) }
                    }
                    // La mission en entier, à relire ou copier.
                    StepTile(step: AgentStep(.user, run.task), full: $full)
                        .padding(.top, 4)
                    ForEach(WorkspaceText.rows(run.steps)) { row in
                        switch row {
                        case let .tool(s, result, _):
                            ToolCard(tool: s, result: result, pending: run.running && result == nil, full: $full)
                        case let .ci(s, _):
                            NoteCard(
                                symbol: "flask", color: Theme.violet,
                                text: WorkspaceText.plain(s.text.replacingOccurrences(of: "🧪 ", with: "")), full: $full
                            )
                        case let .step(s, _):
                            StepTile(step: s, full: $full)
                        }
                    }
                    if run.running {
                        ProgressView().frame(maxWidth: .infinity).padding(16)
                    }
                    if run.interrupted && !run.running {
                        GlassCard(glow: Theme.amber, action: { sessions.continueSession(run.id, "") }) {
                            HStack(spacing: 10) {
                                Image(systemName: "play.circle").foregroundStyle(Theme.amber)
                                Text("Session interrompue (app fermée). Touchez pour reprendre là où l'agent s'était arrêté.")
                            }
                        }
                    }
                    if !run.changes.isEmpty { drafts(run, stats) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .onScrollGeometryChange(for: Bool.self) { g in
                g.contentSize.height - g.visibleRect.maxY > 300
            } action: { _, down in
                showDown = down
            }
            // Suit le travail en direct (sauf si l'utilisateur remonte lire).
            .onChange(of: run.steps.count) {
                if !showDown {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showDown {
                    Button {
                        withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(.regularMaterial, in: .circle)
                    }
                    .accessibilityLabel("Aller en bas")
                    .padding(14)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar(run, busy: busy) }
        }
        .navigationTitle(run.task)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if busy {
                    Button(role: .destructive) {
                        run.stop()
                    } label: {
                        Label("Arrêter", systemImage: "stop.circle")
                    }
                    .tint(Theme.red)
                } else {
                    Menu {
                        Button("Supprimer la session", systemImage: "trash", role: .destructive) {
                            sessions.delete(run.id)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $full) { f in FullTextView(title: f.title, text: f.text) }
        .navigationDestination(isPresented: $reviewing) {
            DraftReviewView(run: run) { toast = $0 }
        }
        .toast($toast)
        // Une pull request a pu être fusionnée ou fermée sur GitHub entre-temps.
        .task(id: run.id) { await run.refreshPulls() }
    }

    // MARK: - En-tête

    private func header(_ run: AgentRun, _ stats: (added: Int, removed: Int)) -> some View {
        GlassCard(glow: run.status.color) {
            HStack(spacing: 10) {
                NexusOrb(size: 56, satellites: 6, interactive: false, pulse: run.running)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.task)
                        .fontWeight(.bold)
                        .lineLimit(3)
                    Text(WorkspaceText.header(
                        run.status, actions: run.steps.filter { $0.kind == .tool }.count,
                        added: stats.added, removed: stats.removed
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    QuotaBadge(providerId: run.provider.id, dense: true)
                    if run.running { BackgroundStatusView() }
                }
            }
        }
    }

    private func chips(_ run: AgentRun) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(run.targets, id: \.fullName) { t in
                    Label("\(t.fullName) · \(run.refOf(t))", systemImage: "folder")
                        .font(.system(size: 11.5, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.fill.tertiary, in: .capsule)
                }
                ForEach(run.pulls.keys.sorted(), id: \.self) { key in
                    Button {
                        if let s = run.pulls[key], let u = URL(string: s) { openURL(u) }
                    } label: {
                        Label("PR \(key.components(separatedBy: "/").last ?? key)", systemImage: "arrow.triangle.merge")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Theme.violet.opacity(0.18), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Du travail resté sur une branche sans pull request.
    private func stranded(_ run: AgentRun) -> some View {
        GlassCard(glow: Theme.amber) {
            VStack(alignment: .leading, spacing: 8) {
                Text(WorkspaceText.strandedNote(run))
                Button {
                    Task {
                        let err = await sessions.recover(run)
                        toast = Toast(
                            text: err ?? (run.autoCi ? "Pull request ouverte : CI puis fusion en cours" : "Pull request ouverte"),
                            error: err != nil
                        )
                    }
                } label: {
                    Label(
                        run.autoCi && run.autoMerge ? "Ouvrir la PR, faire passer la CI et fusionner" : "Ouvrir la pull request",
                        systemImage: "arrow.triangle.merge"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func ciNote(_ run: AgentRun) -> some View {
        GlassCard(glow: run.ciNote.contains("✅") ? Theme.green : Theme.violet) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                Text(run.ciNote)
                Spacer(minLength: 0)
                if run.ciRounds >= AgentRun.maxCiRounds && !run.running {
                    Button("Relancer") { sessions.retryCi(run) }
                }
            }
        }
    }

    private func ciCard(_ run: AgentRun, _ key: String, _ report: CiReport) -> some View {
        let glow: Color = switch report.state {
        case .passed: Theme.green
        case .failed: Theme.red
        default: Theme.amber
        }
        let open: (() -> Void)? = report.runs.isEmpty ? nil : {
            if let u = URL(string: report.runs.first?.url ?? "https://github.com/\(key)/actions") { openURL(u) }
        }
        return GlassCard(glow: glow, action: open) {
            HStack(spacing: 10) {
                Image(systemName: "flask")
                Text(WorkspaceText.ciCard(key, report, several: run.ci.count > 1))
                Spacer(minLength: 0)
                if report.state == .waiting || report.state == .running {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func drafts(_ run: AgentRun, _ stats: (added: Int, removed: Int)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Brouillons à valider")
            GlassCard(glow: Theme.amber, action: run.running ? nil : { reviewing = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "checklist").foregroundStyle(Theme.amber)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WorkspaceText.draftsSummary(
                            files: run.changes.count, added: stats.added, removed: stats.removed,
                            rejected: run.rejected.count
                        ))
                        .fontWeight(.bold)
                        Text(run.running
                            ? "L'agent travaille encore…"
                            : "Relisez chaque fichier, acceptez ou refusez, puis validez : rien ne part sans vous.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let names = run.changes.keys.prefix(6)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(names), id: \.self) { p in
                                    Text(p.components(separatedBy: "/").last ?? p)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .strikethrough(run.rejected.contains(p))
                                }
                                if run.changes.count > 6 { Text("+\(run.changes.count - 6)").font(.caption) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if !run.running { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }
            }
        }
    }

    // MARK: - En bas : modèle, effort, nouvelle instruction

    private func bottomBar(_ run: AgentRun, busy: Bool) -> some View {
        VStack(spacing: 4) {
            // Le modèle et l'effort de la session : à changer à tout moment.
            HStack(spacing: 4) {
                ModelEffortButton(
                    current: ModelRef(run.provider.id, run.model),
                    level: run.level ?? .moyen,
                    onModel: { sessions.setModel(run, $0, run.level ?? .moyen) },
                    onLevel: { sessions.setModel(run, ModelRef(run.provider.id, run.model), $0) }
                )
                // Le crédit restant chez le fournisseur de la session.
                QuotaBadge(providerId: run.provider.id, dense: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                TextField(
                    busy ? "Préciser pendant le travail…" : "Nouvelle instruction pour cette session",
                    text: $input,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: .rect(cornerRadius: 18))
                Button {
                    followUp(run)
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .accessibilityLabel(busy ? "Envoyer (lu au tour suivant)" : "Envoyer")
                if busy {
                    Button {
                        run.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill").font(.title)
                    }
                    .tint(Theme.red)
                    .accessibilityLabel("Arrêter")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func followUp(_ run: AgentRun) {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        sessions.continueSession(run.id, t)
        input = ""
        focused = false
    }
}

// MARK: - Les étapes

/// Une étape de l'agent : ce qu'il a compris, une réflexion, une erreur, votre
/// message, un résultat, ou le résumé final.
struct StepTile: View {
    let step: AgentStep
    @Binding var full: FullTextItem?

    var body: some View {
        let text = WorkspaceText.stepText(step)
        switch step.kind {
        case .goal:
            // Au tout début : ce que l'agent a compris de votre demande, bien en vue.
            GlassCard(glow: Theme.amber) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Ce que l'agent a compris de votre demande", systemImage: "scope")
                        .fontWeight(.heavy)
                        .foregroundStyle(Theme.amber)
                    SpecView(text: text)
                }
            }
            .onLongPressGesture { full = FullTextItem(title: "Ce que l'agent a compris", text: text) }
            .padding(.vertical, 2)
        case .thought:
            ThoughtRow(text: text, full: $full)
        case .error:
            NoteCard(symbol: "exclamationmark.circle", color: Theme.red, text: WorkspaceText.plain(text), full: $full)
        case .user:
            // Votre message : une bulle à droite.
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(.system(size: 14.5))
                    .lineLimit(8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.16), in: .rect(cornerRadius: 16))
                    .onLongPressGesture { full = FullTextItem(title: "Votre message", text: text) }
            }
            .padding(.vertical, 2)
        case .result:
            NoteCard(symbol: "arrow.turn.down.right", color: .gray, text: text, full: $full)
        case .done, .tool:
            // Fin : le résumé, bien lisible.
            VStack(alignment: .leading, spacing: 6) {
                Label("Terminé", systemImage: "flag.checkered")
                    .fontWeight(.heavy)
                    .foregroundStyle(Theme.green)
                Text(WorkspaceText.plain(text))
                    .font(.system(size: 14.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.green.opacity(0.10), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.green.opacity(0.4)))
            .onLongPressGesture { full = FullTextItem(title: "Résumé", text: text) }
            .padding(.vertical, 2)
        }
    }
}

/// Une action de l'agent et son résultat, dans une carte compacte. Touchez pour
/// voir le résultat, appui long pour tout lire.
struct ToolCard: View {
    let tool: AgentStep
    let result: AgentStep?
    var pending = false
    @Binding var full: FullTextItem?
    @State private var open = false

    var body: some View {
        let verb = WorkspaceText.toolVerb(tool.tool)
        let failed = result?.kind == .error
        let out = result?.text ?? ""
        let target = tool.text.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: toolSymbol(tool.tool))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                Text(verb).font(.system(size: 13.5, weight: .bold))
                Text(target)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if pending {
                    ProgressView().controlSize(.mini)
                } else if result != nil {
                    Image(systemName: failed ? "exclamationmark.circle" : "checkmark")
                        .foregroundStyle(failed ? Theme.red : Theme.green)
                }
            }
            if failed && !open {
                Text(out)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.red)
                    .lineLimit(2)
                    .padding(.leading, 25)
            }
            if open {
                Text(out)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(failed ? Theme.red : .secondary)
                    .lineLimit(14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
        .onTapGesture { if !out.isEmpty { open.toggle() } }
        .onLongPressGesture { if !out.isEmpty { full = FullTextItem(title: "\(verb) \(target)", text: out) } }
        .padding(.vertical, 1)
    }
}

/// Une petite note colorée (erreur, rapport de CI…).
struct NoteCard: View {
    let symbol: String
    let color: Color
    let text: String
    @Binding var full: FullTextItem?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .font(.system(size: 13))
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.35)))
        .onLongPressGesture { full = FullTextItem(title: "Détail", text: text) }
        .padding(.vertical, 2)
    }
}

/// Une réflexion de l'agent : courte, discrète, à déplier.
struct ThoughtRow: View {
    let text: String
    @Binding var full: FullTextItem?
    @State private var open = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain").foregroundStyle(Theme.violet).padding(.top, 2)
            Text(WorkspaceText.plain(text))
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .lineLimit(open ? nil : 3)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .onTapGesture { open.toggle() }
        .onLongPressGesture { full = FullTextItem(title: "Réflexion", text: text) }
        .padding(.vertical, 2)
    }
}

/// Une demande en langage NEXORA : ses rubriques (OBJECTIF, DEMANDES…) en petites
/// capitales colorées, puis leurs lignes, sans rien fusionner.
struct SpecView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(WorkspaceText.specLines(text).enumerated()), id: \.offset) { i, line in
                switch line {
                case let .heading(h):
                    Text(h)
                        .font(.system(size: 11.5, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(Theme.amber)
                        .padding(.top, i == 0 ? 0 : 6)
                case let .text(t):
                    Text(t).font(.system(size: 14))
                }
            }
        }
    }
}
