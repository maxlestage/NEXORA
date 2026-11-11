import NexoraKit
import SwiftUI

/// La liste des conversations : recherche, épinglées en premier, nouvelle
/// conversation avec ou sans agent.
struct ConversationsView: View {
    @Environment(ChatStore.self) private var chats
    @Environment(AgentLibrary.self) private var agents
    @State private var path: [String] = []
    @State private var query = ""
    @State private var results: [ConversationStore.Meta]?
    @State private var renaming: ConversationStore.Meta?
    @State private var newTitle = ""
    @State private var pickAgent = false

    private var list: [ConversationStore.Meta] { results ?? chats.index }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if chats.index.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune conversation", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Posez votre première question : Pollinations répond tout de suite, sans clé ni compte.")
                    } actions: {
                        Button("Nouvelle conversation", action: newChat).buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(list) { meta in
                            NavigationLink(value: meta.id) { row(meta) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { chats.delete(meta.id) } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { chats.togglePin(meta.id) } label: {
                                        Label(meta.pinned ? "Désépingler" : "Épingler", systemImage: meta.pinned ? "pin.slash" : "pin")
                                    }
                                    .tint(Theme.amber)
                                }
                                .contextMenu {
                                    Button { chats.togglePin(meta.id) } label: {
                                        Label(meta.pinned ? "Désépingler" : "Épingler", systemImage: "pin")
                                    }
                                    Button {
                                        newTitle = meta.title
                                        renaming = meta
                                    } label: { Label("Renommer", systemImage: "pencil") }
                                    Button(role: .destructive) { chats.delete(meta.id) } label: {
                                        Label("Supprimer", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $query, prompt: "Chercher dans les conversations")
                    .task(id: query) {
                        if query.isEmpty { results = nil; return }
                        try? await Task.sleep(for: .milliseconds(250))
                        results = await chats.search(query)
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nouvelle conversation", systemImage: "square.and.pencil", action: newChat)
                        Button("Avec un agent…", systemImage: "person.crop.circle.badge.plus") { pickAgent = true }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    } primaryAction: {
                        newChat()
                    }
                    .accessibilityLabel("Nouvelle conversation")
                }
            }
            .navigationDestination(for: String.self) { id in
                ChatView(conversationId: id)
            }
            .sheet(isPresented: $pickAgent) {
                AgentPickerSheet(selected: nil) { agent in
                    let c = chats.create(agent: agent)
                    path.append(c.id)
                }
            }
            .alert("Renommer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Titre", text: $newTitle)
                Button("Annuler", role: .cancel) {}
                Button("Renommer") {
                    if let r = renaming, !newTitle.trimmingCharacters(in: .whitespaces).isEmpty { chats.rename(r.id, newTitle) }
                }
            }
        }
    }

    private func newChat() {
        let c = chats.create()
        path.append(c.id)
    }

    private func row(_ meta: ConversationStore.Meta) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if meta.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Theme.amber) }
                if let a = meta.agentId.flatMap({ agents.agent($0) }) { Text(a.emoji) }
                Text(meta.title).font(.headline).lineLimit(1)
                Spacer()
                Text(meta.updated, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
            }
            if !meta.preview.isEmpty {
                Text(meta.preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
