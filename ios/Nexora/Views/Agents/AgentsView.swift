import NexoraKit
import SwiftUI
import UniformTypeIdentifiers

/// Les agents : intégrés et personnels, par catégorie. Créer, modifier, dupliquer,
/// importer (fichier ou adresse `.claude/agents/*.md`), partager, discuter.
struct AgentsView: View {
    @Environment(AgentLibrary.self) private var agents
    @Environment(ChatStore.self) private var chats
    @State private var editing: Agent?
    @State private var importing = false
    @State private var importURL = ""
    @State private var showURL = false
    @State private var message: String?
    @State private var query = ""
    @State private var chatPath: [String] = []

    var body: some View {
        NavigationStack(path: $chatPath) {
            List {
                ForEach(agents.byCategory, id: \.0) { category, list in
                    let shown = list.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
                    if !shown.isEmpty {
                        Section(category) {
                            ForEach(shown) { a in
                                row(a)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Chercher un agent")
            .navigationTitle("Agents")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nouvel agent", systemImage: "plus") {
                            editing = Agent(id: "custom:\(newId())", name: "", systemPrompt: "", emoji: "🤖")
                        }
                        Button("Importer un fichier .md", systemImage: "doc") { importing = true }
                        Button("Importer depuis une adresse", systemImage: "link") { showURL = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un agent")
                }
            }
            .sheet(item: $editing) { a in
                AgentEditorView(agent: a)
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
        }
    }

    private func row(_ a: Agent) -> some View {
        Button {
            let c = chats.create(agent: a)
            chatPath.append(c.id)
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
