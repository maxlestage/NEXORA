import NexoraKit
import SwiftUI

extension LibraryItemKind {
    /// Le symbole d'un type d'élément.
    var symbol: String {
        switch self {
        case .agent: "person.crop.circle"
        case .skill: "puzzlepiece.extension"
        case .command: "terminal"
        }
    }
}

/// La bibliothèque : installe des sous-agents, des skills, des commandes et des
/// plugins depuis GitHub, en quelques gestes (format de Claude Code).
struct InstallAgentsView: View {
    /// Un dépôt à parcourir tout de suite.
    var initialSpec: String?

    @Environment(AgentLibrary.self) private var agents
    @Environment(GitHubSession.self) private var github
    @State private var repoText = ""
    @State private var urlText = ""
    @State private var pasteText = ""
    /// Les dépôts parcourus (pour revenir d'un plugin au catalogue).
    @State private var stack: [RepoScan] = []
    @State private var selected: Set<String> = []
    @State private var kind: LibraryItemKind?
    @State private var filter = ""
    @State private var busy = false
    @State private var progress: (done: Int, total: Int)?
    @State private var message: String?
    @State private var started = false

    private var scan: RepoScan? { stack.last }

    var body: some View {
        Group {
            if let scan { results(scan) } else { home }
        }
        .navigationTitle(scan.map { "\($0.owner)/\($0.repo)" } ?? "Bibliothèque")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(stack.count > 1)
        .toolbar {
            if stack.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Retour", systemImage: "chevron.backward") {
                        stack.removeLast()
                        selected.removeAll()
                    }
                }
            }
            if scan != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Autres sources", systemImage: "square.grid.2x2") {
                        stack.removeAll()
                        selected.removeAll()
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if busy {
                Group {
                    if let p = progress, p.total > 0 {
                        ProgressView(value: Double(p.done), total: Double(p.total))
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let scan, !selected.isEmpty { installBar(scan) }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .task {
            guard !started else { return }
            started = true
            if let initialSpec { await browse(initialSpec) }
        }
    }

    // MARK: - Accueil

    /// Les sources recommandées, un dépôt au choix, une URL, un texte.
    private var home: some View {
        List {
            Section {
                Text("Ajoutez des sous-agents (spécialistes qui travaillent à part et rendent un rapport), des skills (savoir-faire chargés seulement quand ils servent), des commandes (/…) et des plugins (des paquets de tout ça), au format de Claude Code.")
                    .font(.subheadline)
            }
            Section("Sources recommandées") {
                ForEach(LibraryScanner.sources) { src in
                    Button {
                        Task { await browse(src.spec) }
                    } label: {
                        HStack(spacing: 12) {
                            Text(src.emoji).font(.title)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(src.title).font(.headline).foregroundStyle(.primary)
                                Text(src.description).font(.caption).foregroundStyle(.secondary)
                                Text(src.spec).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .disabled(busy)
                }
            }
            Section("N'importe quel dépôt GitHub") {
                HStack {
                    TextField("propriétaire/dépôt[/dossier] ou lien github.com", text: $repoText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { Task { await browse(repoText) } }
                    Button {
                        Task { await browse(repoText) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(busy)
                    .accessibilityLabel("Parcourir")
                }
            }
            Section("Un agent depuis une URL") {
                HStack {
                    TextField("https://github.com/…/agents/mon-agent.md", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        Task { await fromURL() }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(busy)
                    .accessibilityLabel("Installer depuis l'URL")
                }
            }
            Section("Coller un agent (.md)") {
                TextEditor(text: $pasteText)
                    .font(.footnote.monospaced())
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if pasteText.isEmpty {
                            Text("---\nname: mon-agent\ndescription: …\n---\nTu es…")
                                .font(.footnote.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                Button("Installer", systemImage: "plus", action: fromPaste)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Contenu d'un dépôt

    /// Ce qu'un dépôt contient, rangé par type.
    private func results(_ scan: RepoScan) -> some View {
        let q = filter.lowercased()
        let shown = scan.items
            .filter { kind == nil || $0.kind == kind }
            .filter { q.isEmpty || $0.path.lowercased().contains(q) || ($0.plugin ?? "").lowercased().contains(q) }
        let plugins = scan.plugins.filter {
            q.isEmpty || $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
        let allSelected = !shown.isEmpty && shown.allSatisfy { selected.contains($0.key) }
        return List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("Tout (\(scan.items.count))", symbol: nil, on: kind == nil) { kind = nil }
                        ForEach(LibraryItemKind.allCases, id: \.self) { k in
                            let n = scan.of(k).count
                            if n > 0 {
                                chip("\(k.label(plural: true)) (\(n))", symbol: k.symbol, on: kind == k) { kind = k }
                            }
                        }
                    }
                }
                TextField("Filtrer (python, react, sécurité, pdf…)", text: $filter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if !plugins.isEmpty {
                Section {
                    ForEach(plugins.prefix(150)) { p in
                        Button {
                            Task { await browse(p.spec, push: true) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "shippingbox").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.headline).foregroundStyle(.primary)
                                    if !p.description.isEmpty {
                                        Text(p.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .disabled(busy)
                    }
                } header: {
                    Text("Plugins (\(plugins.count))")
                } footer: {
                    Text("Un plugin regroupe des sous-agents, des skills et des commandes : touchez-en un pour voir son contenu et l'installer.")
                }
            }
            if !shown.isEmpty {
                Section {
                    ForEach(shown.prefix(400)) { item in
                        itemRow(item)
                    }
                } header: {
                    HStack {
                        Text("\(shown.count) élément\(shown.count > 1 ? "s" : "")")
                        Spacer()
                        Button(allSelected ? "Tout décocher" : "Tout sélectionner") {
                            if allSelected {
                                selected.subtract(shown.map(\.key))
                            } else {
                                selected.formUnion(shown.map(\.key))
                            }
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
    }

    private func chip(_ title: String, symbol: String?, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.15)), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func itemRow(_ item: NexoraKit.LibraryItem) -> some View {
        let on = selected.contains(item.key)
        var details = [item.kind.label()]
        if let plugin = item.plugin { details.append("plugin \(plugin)") }
        if item.kind == .skill && !item.files.isEmpty { details.append("\(item.files.count) fichier(s)") }
        return Button {
            if on { selected.remove(item.key) } else { selected.insert(item.key) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(details.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if agents.isInstalled(item) {
                    Pill(text: "installé", color: Theme.green)
                } else {
                    Image(systemName: item.kind.symbol).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func installBar(_ scan: RepoScan) -> some View {
        Button {
            Task { await installSelected(scan.items) }
        } label: {
            Label(
                progress.map { "Installation \($0.done)/\($0.total)…" }
                    ?? "Installer \(selected.count) élément\(selected.count > 1 ? "s" : "")",
                systemImage: "square.and.arrow.down"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(busy)
        .padding()
        .background(.bar)
    }

    // MARK: - Actions

    private func browse(_ spec: String, push: Bool = false) async {
        let s = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let found = try await github.api.libraryScan(s)
            if !push { stack.removeAll() }
            stack.append(found)
            selected.removeAll()
            kind = nil
            filter = ""
            if found.isEmpty {
                message = "Rien trouvé : ni sous-agents (agents/*.md), ni skills (SKILL.md), ni commandes (commands/*.md), ni plugins."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func installSelected(_ items: [NexoraKit.LibraryItem]) async {
        let todo = items.filter { selected.contains($0.key) }
        let api = github.api
        busy = true
        progress = (0, todo.count)
        var ok = 0
        var done = 0
        // Quatre téléchargements à la fois : rapide, sans saturer le réseau.
        var i = 0
        while i < todo.count {
            let batch = Array(todo[i..<min(i + 4, todo.count)])
            let texts = await api.libraryTexts(batch)
            for (item, text) in zip(batch, texts) {
                if let text, agents.install(item, text: text) { ok += 1 }
            }
            done += batch.count
            progress = (done, todo.count)
            i += 4
        }
        busy = false
        progress = nil
        selected.removeAll()
        message = ok == todo.count
            ? "\(ok) élément\(ok > 1 ? "s" : "") installé\(ok > 1 ? "s" : "") 🎉"
            : "\(ok) sur \(todo.count) installés (les autres sont illisibles)"
    }

    private func fromURL() async {
        busy = true
        defer { busy = false }
        do {
            let a = try await agents.importURL(urlText)
            message = "\(a.emoji) \(a.name) installé"
        } catch {
            message = error.localizedDescription
        }
    }

    private func fromPaste() {
        if let a = agents.importMarkdown(pasteText) {
            pasteText = ""
            message = "\(a.emoji) \(a.name) installé"
        } else {
            message = "Texte vide."
        }
    }
}
