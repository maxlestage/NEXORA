import Foundation
import NexoraKit
import Observation

/// Les agents : ceux fournis avec NEXORA et les vôtres (créés, importés depuis un
/// fichier Markdown `.claude/agents/*.md` ou une adresse).
@MainActor
@Observable
final class AgentLibrary {
    private(set) var custom: [Agent] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "agents"),
           let list = try? JSONDecoder().decode([Agent].self, from: data) {
            custom = list
        }
    }

    var all: [Agent] { Catalog.builtinAgents + custom }

    /// Les agents rangés par catégorie, dans l'ordre d'apparition.
    var byCategory: [(String, [Agent])] {
        var order: [String] = []
        var groups: [String: [Agent]] = [:]
        for a in all {
            if groups[a.category] == nil { order.append(a.category) }
            groups[a.category, default: []].append(a)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    func agent(_ id: String) -> Agent? { all.first { $0.id == id } }

    /// L'agent appelé par `@nom` (nom ou identifiant, sans tenir compte de la casse).
    func named(_ name: String) -> Agent? {
        let n = name.lowercased()
        return all.first { a in
            a.name.lowercased().replacingOccurrences(of: " ", with: "-") == n
                || a.id.lowercased() == n
                || a.id.lowercased().hasSuffix(":" + n)
        }
    }

    func save(_ agent: Agent) {
        var a = agent
        a.builtin = false
        if let i = custom.firstIndex(where: { $0.id == a.id }) { custom[i] = a } else { custom.append(a) }
        persist()
    }

    func delete(_ id: String) {
        custom.removeAll { $0.id == id }
        persist()
    }

    /// Copie modifiable d'un agent (intégré ou non).
    func duplicate(_ agent: Agent) -> Agent {
        var a = agent
        a = Agent(
            id: "custom:\(newId())", name: agent.name + " (copie)", systemPrompt: agent.systemPrompt,
            description: agent.description, emoji: agent.emoji, model: agent.model, level: agent.level,
            tools: agent.tools, source: "custom", category: "Perso"
        )
        save(a)
        return a
    }

    /// Importe un ou plusieurs agents depuis du Markdown.
    @discardableResult
    func importMarkdown(_ text: String, source: String? = nil) -> Agent? {
        guard let a = Agent.fromMarkdown(text, id: "custom:\(newId())", source: source) else { return nil }
        save(a)
        return a
    }

    /// Importe un agent depuis une adresse (fichier brut GitHub, gist…).
    func importURL(_ raw: String) async throws -> Agent {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Une page github.com/…/blob/… devient le fichier brut.
        if s.contains("github.com/"), s.contains("/blob/") {
            s = s.replacingOccurrences(of: "github.com/", with: "raw.githubusercontent.com/")
                .replacingOccurrences(of: "/blob/", with: "/")
        }
        guard let url = URL(string: s) else { throw GitHubError("Adresse invalide") }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubError("Fichier introuvable", status: http.statusCode)
        }
        guard let a = importMarkdown(String(decoding: data, as: UTF8.self), source: s) else {
            throw GitHubError("Ce fichier ne contient pas d'agent (consigne vide).")
        }
        return a
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(custom), forKey: "agents")
    }
}
