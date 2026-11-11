import NexoraKit
import SwiftUI
import UniformTypeIdentifiers

/// Les agents : intégrés et personnels, par catégorie. Créer, modifier, dupliquer,
/// importer (fichier ou adresse `.claude/agents/*.md`), partager, discuter. Puis
/// les skills et commandes installées, et les agents cloud de GitHub ; la
/// bibliothèque installe agents, skills, commandes et plugins depuis GitHub.
struct AgentsView: View {
    /// Les parties de l'onglet.
    enum Part: String, CaseIterable, Identifiable {
        case agents = "Agents"
        case skills = "Skills"
        case cloud = "Cloud GitHub"
        var id: String { rawValue }
    }

    /// Un texte à lire en entier (skill, commande).
    struct Reading: Identifiable {
        let title: String
        let text: String
        var id: String { title }
    }

    /// Une skill ou une commande à supprimer, après confirmation.
    struct Removal: Identifiable {
        let id: String
        let name: String
        let skill: Bool
    }

    @Environment(AgentLibrary.self) private var agents
    @Environment(ChatStore.self) private var chats
    @State private var part: Part = .agents
    @State private var editing: Agent?
    @State private var shown: Agent?
    @State private var reading: Reading?
    @State private var removing: Removal?
    @State private var cloud: CloudAgent?
    @State private var importing = false
    @State private var importURL = ""
    @State private var showURL = false
    @State private var message: String?
    @State private var query = ""
    @State private var chatPath: [String] = []
    @State private var showLibrary = false
    @State private var librarySpec: String?

    var body: some View {
        NavigationStack(path: $chatPath) {
            List {
                switch part {
                case .agents: agentList
                case .skills: skillList
                case .cloud: cloudList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Partie", selection: $part) {
                    ForEach(Part.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)
            }
            .searchable(text: $query, prompt: searchPrompt)
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Bibliothèque", systemImage: "square.and.arrow.down") { openLibrary() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nouvel agent", systemImage: "plus") {
                            editing = Agent(id: "custom:\(newId())", name: "", systemPrompt: "", emoji: "🤖")
                        }
                        Button("Importer un fichier .md", systemImage: "doc") { importing = true }
                        Button("Importer depuis une adresse", systemImage: "link") { showURL = true }
                        Button("Bibliothèque GitHub", systemImage: "square.and.arrow.down") { openLibrary() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un agent")
                }
            }
            .sheet(item: $editing) { a in
                AgentEditorView(agent: a)
            }
            .sheet(item: $shown) { a in
                AgentDetailSheet(
                    agent: a,
                    onChat: {
                        shown = nil
                        chatPath.append(chats.create(agent: a).id)
                    },
                    onEdit: { agent in
                        shown = nil
                        // L'éditeur s'ouvre une fois la fiche refermée.
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            editing = agent
                        }
                    }
                )
            }
            .sheet(item: $reading) { r in
                NavigationStack {
                    ScrollView {
                        MarkdownView(text: r.text).padding()
                    }
                    .navigationTitle(r.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Fermer") { reading = nil } }
                    }
                }
            }
            .sheet(item: $cloud) { a in
                CloudAgentSheet(agent: a)
            }
            .confirmationDialog(
                "Supprimer \(removing?.name ?? "") ?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible,
                presenting: removing
            ) { r in
                Button("Supprimer", role: .destructive) {
                    if r.skill { agents.removeSkill(r.id) } else { agents.removeCommand(r.id) }
                }
                Button("Annuler", role: .cancel) {}
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: true) { result in
                guard case let .success(urls) = result else { return }
                var count = 0
                for url in urls {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: url, encoding: .utf8), agents.importMarkdown(text, source: url.lastPathComponent) != nil {
                        count += 1
                    }
                }
                message = count > 0 ? "\(count) agent(s) importé(s)." : "Aucun agent trouvé dans ces fichiers."
            }
            .alert("Importer depuis une adresse", isPresented: $showURL) {
                TextField("https://github.com/…/agent.md", text: $importURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Annuler", role: .cancel) {}
                Button("Importer") {
                    let url = importURL
                    Task {
                        do {
                            let a = try await agents.importURL(url)
                            message = "\(a.emoji) \(a.name) importé."
                            importURL = ""
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Un fichier Markdown d'agent (format .claude/agents de Claude Code), sur GitHub ou ailleurs.")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .navigationDestination(for: String.self) { id in ChatView(conversationId: id) }
            .navigationDestination(isPresented: $showLibrary) {
                InstallAgentsView(initialSpec: librarySpec)
            }
        }
    }

    private var searchPrompt: String {
        part == .skills ? "Chercher une skill ou une commande" : "Chercher un agent"
    }

    private func openLibrary(_ spec: String? = nil) {
        librarySpec = spec
        showLibrary = true
    }

    // MARK: - Agents

    @ViewBuilder
    private var agentList: some View {
        ForEach(agents.byCategory, id: \.0) { category, list in
            let visible = list.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
            if !visible.isEmpty {
                Section(category) {
                    ForEach(visible) { a in
                        row(a)
                    }
                }
            }
        }
        if agents.custom.isEmpty && query.isEmpty {
            Section {
                Button("Installer des agents depuis GitHub", systemImage: "square.and.arrow.down") { openLibrary() }
            } footer: {
                Text("Créez un agent avec votre propre consigne, ou installez-en depuis GitHub (format .claude/agents/*.md compatible).")
            }
        }
    }

    private func row(_ a: Agent) -> some View {
        Button {
            shown = a
        } label: {
            HStack(spacing: 12) {
                Text(a.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.headline).foregroundStyle(.primary)
                    if !a.description.isEmpty {
                        Text(a.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if !a.tools.isEmpty {
                        Text(a.tools.joined(separator: " · ")).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
        }
        .contextMenu {
            Button("Discuter", systemImage: "bubble.left") {
                let c = chats.create(agent: a)
                chatPath.append(c.id)
            }
            if a.builtin {
                Button("Dupliquer pour modifier", systemImage: "plus.square.on.square") { editing = agents.duplicate(a) }
            } else {
                Button("Modifier", systemImage: "pencil") { editing = a }
                Button("Supprimer", systemImage: "trash", role: .destructive) { agents.delete(a.id) }
            }
            ShareLink(item: a.toMarkdown(), preview: SharePreview("\(a.name).md")) {
                Label("Partager (.md)", systemImage: "square.and.arrow.up")
            }
        }
        .swipeActions {
            if !a.builtin {
                Button(role: .destructive) { agents.delete(a.id) } label: { Label("Supprimer", systemImage: "trash") }
                Button { editing = a } label: { Label("Modifier", systemImage: "pencil") }
            }
        }
    }

    // MARK: - Skills et commandes

    @ViewBuilder
    private var skillList: some View {
        let skills = agents.skills.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
        let commands = agents.commands.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
        if agents.skills.isEmpty && agents.commands.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("Aucune skill ni commande", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("Une skill est un savoir-faire (créer un PDF, faire une revue de code, suivre une méthode…) que l'assistant charge seulement quand il sert. Une commande se lance avec /nom dans le chat.")
                } actions: {
                    Button("Skills officielles d'Anthropic", systemImage: "square.and.arrow.down") { openLibrary("anthropics/skills") }
                        .buttonStyle(.borderedProminent)
                }
            }
            .listRowBackground(Color.clear)
        } else {
            if !skills.isEmpty {
                Section {
                    ForEach(skills) { sk in
                        HStack(spacing: 12) {
                            Button {
                                reading = Reading(title: sk.name, text: sk.instructions)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "puzzlepiece.extension").foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sk.name).font(.headline).foregroundStyle(.primary)
                                        if !sk.description.isEmpty {
                                            Text(sk.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.borderless)
                            Toggle("Toujours", isOn: Binding(get: { sk.always }, set: { agents.setSkillAlways(sk.id, $0) }))
                                .labelsHidden()
                                .accessibilityLabel("Toujours active : \(sk.name)")
                        }
                        .contextMenu {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                removing = Removal(id: sk.id, name: sk.name, skill: true)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                removing = Removal(id: sk.id, name: sk.name, skill: true)
                            } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("Skills")
                } footer: {
                    Text("L'assistant voit leur nom et leur description, et charge une skill quand elle sert. L'interrupteur (« Toujours ») l'ajoute à chaque conversation.")
                }
            }
            if !commands.isEmpty {
                Section {
                    ForEach(commands) { c in
                        Button {
                            reading = Reading(title: "/\(c.name)", text: c.body)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "terminal").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("/\(c.name)").font(.headline.monospaced()).foregroundStyle(.primary)
                                    Text(c.description.isEmpty ? c.body : c.description)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .contextMenu {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                removing = Removal(id: c.id, name: "/\(c.name)", skill: false)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                removing = Removal(id: c.id, name: "/\(c.name)", skill: false)
                            } label: { Label("Supprimer", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("Commandes")
                } footer: {
                    Text("Tapez / dans le chat pour les lancer.")
                }
            }
            Section {
                Button("En ajouter depuis la bibliothèque", systemImage: "square.and.arrow.down") { openLibrary() }
            } footer: {
                Text("Balayez vers la gauche ou appuyez longuement pour supprimer.")
            }
        }
    }

    // MARK: - Agents cloud

    @ViewBuilder
    private var cloudList: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Des agents qui codent sur GitHub").font(.headline)
                Text("Installez un workflow dans un dépôt, ajoutez la clé en secret, puis lancez des instructions depuis votre téléphone. L'agent travaille sur les serveurs de GitHub et ouvre une pull request.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        Section {
            ForEach(Catalog.cloudAgents.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { a in
                Button {
                    cloud = a
                } label: {
                    HStack(spacing: 12) {
                        Text(a.emoji)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background((a.free ? Theme.green : Theme.violet).opacity(0.18), in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(a.name).font(.headline).foregroundStyle(.primary)
                                if a.free { Pill(text: "gratuit", color: Theme.green) }
                            }
                            Text(a.description).font(.caption).foregroundStyle(.secondary)
                            Text("Secret : \(a.secrets.joined(separator: ", "))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

/// La fiche d'un agent et ses actions.
struct AgentDetailSheet: View {
    let agent: Agent
    let onChat: () -> Void
    let onEdit: (Agent) -> Void

    @Environment(AgentLibrary.self) private var agents
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Text(agent.emoji)
                            .font(.system(size: 34))
                            .frame(width: 60, height: 60)
                            .background((agent.builtin ? Theme.violet : Color.accentColor).opacity(0.18), in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name).font(.title2.bold())
                            Text(agent.builtin ? "Intégré" : agent.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if !agent.description.isEmpty { Text(agent.description) }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button("Discuter", systemImage: "bubble.left", action: onChat)
                                .buttonStyle(.borderedProminent)
                            ShareLink(item: agent.toMarkdown(), preview: SharePreview("\(agent.name).md")) {
                                Label("Partager", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            if agent.builtin {
                                Button("Dupliquer", systemImage: "plus.square.on.square") {
                                    onEdit(agents.duplicate(agent))
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Modifier", systemImage: "pencil") { onEdit(agent) }
                                    .buttonStyle(.bordered)
                                Button("Supprimer", systemImage: "trash", role: .destructive) {
                                    agents.delete(agent.id)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    Text("Consigne").font(.headline).padding(.top, 6)
                    MarkdownView(text: "```markdown\n\(agent.toMarkdown())\n```")
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Un agent cloud : ce qu'il fait, le secret à ajouter et son workflow.
struct CloudAgentSheet: View {
    let agent: CloudAgent

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(agent.emoji).font(.largeTitle)
                        Text(agent.name).font(.title2.bold())
                        if agent.free { Pill(text: "gratuit", color: Theme.green) }
                    }
                    Text(agent.description)
                    LabeledContent("Secret", value: agent.secrets.joined(separator: ", "))
                        .font(.subheadline.monospaced())
                    if let help = agent.secretHelpUrl, let url = URL(string: help) {
                        Link("Obtenir la clé", destination: url)
                    }
                    if let mention = agent.mention {
                        Text("Mentionnez \(mention) dans une issue ou une pull request pour le lancer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Ajoutez la clé dans le dépôt : Settings → Secrets and variables → Actions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(agent.path).font(.headline.monospaced()).padding(.top, 6)
                    MarkdownView(text: "```yaml\n\(agent.yaml)\n```")
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: agent.yaml, preview: SharePreview(agent.workflowFile)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Partager le workflow")
                }
            }
        }
    }
}

/// Créer ou modifier un agent.
struct AgentEditorView: View {
    @State var agent: Agent
    @Environment(AgentLibrary.self) private var agents
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var pickModel = false
    @State private var toolsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Identité") {
                    HStack {
                        TextField("🤖", text: $agent.emoji)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                        TextField("Nom", text: $agent.name)
                    }
                    TextField("Description courte", text: $agent.description, axis: .vertical)
                    TextField("Catégorie", text: $agent.category)
                }
                Section {
                    TextEditor(text: $agent.systemPrompt)
                        .frame(minHeight: 180)
                        .font(.callout)
                } header: {
                    Text("Consigne (prompt système)")
                } footer: {
                    Text("Décrivez le rôle, le ton et les règles de l'agent. Appelez-le dans n'importe quelle conversation avec @\(agent.name.lowercased().replacingOccurrences(of: " ", with: "-")).")
                }
                Section("Préférences") {
                    Button {
                        pickModel = true
                    } label: {
                        LabeledContent("Modèle", value: agent.model ?? "Celui de la conversation")
                    }
                    if agent.model != nil {
                        Button("Utiliser le modèle de la conversation") { agent.model = nil }
                    }
                    Picker("Effort", selection: Binding(get: { ThinkLevel.named(agent.level) }, set: { agent.level = $0?.rawValue })) {
                        Text("Celui de la conversation").tag(ThinkLevel?.none)
                        ForEach(ThinkLevel.allCases) { Text("\($0.emoji) \($0.label)").tag(Optional($0)) }
                    }
                    TextField("Outils (list_files, read_file…)", text: $toolsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(agent.name.isEmpty ? "Nouvel agent" : agent.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        agent.tools = toolsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        if agent.emoji.isEmpty { agent.emoji = "🤖" }
                        agents.save(agent)
                        dismiss()
                    }
                    .disabled(agent.name.trimmingCharacters(in: .whitespaces).isEmpty || agent.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { toolsText = agent.tools.joined(separator: ", ") }
            .sheet(isPresented: $pickModel) {
                ModelPickerSheet(selected: settings.resolve(agent.model)) { agent.model = $0.key }
            }
        }
    }
}
