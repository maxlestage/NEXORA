import Foundation
import NexoraKit
import Observation

/// Les agents : ceux fournis avec NEXORA et les vôtres (créés, importés depuis un
/// fichier Markdown `.claude/agents/*.md` ou une adresse), plus les skills et les
/// commandes installées depuis la bibliothèque (règles dans `UserLibrary`).
@MainActor
@Observable
final class AgentLibrary {
    private(set) var custom: [Agent] = []
    /// Les skills installées (savoir-faire chargés quand ils servent).
    private(set) var skills: [Skill] = []
    /// Les commandes installées (`/nom` dans le chat).
    private(set) var commands: [SlashCommand] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let lib = UserLibrary.decode(
            agents: defaults.data(forKey: "agents"), skills: defaults.data(forKey: "skills"),
            commands: defaults.data(forKey: "commands")
        )
        custom = lib.agents
        skills = lib.skills
        commands = lib.commands
    }

    /// Les agents, skills et commandes de l'utilisateur, pour les règles du cœur.
    var library: UserLibrary { UserLibrary(agents: custom, skills: skills, commands: commands) }

    /// Applique une modification de la bibliothèque, puis l'enregistre.
    @discardableResult
    private func update<T>(_ f: (inout UserLibrary) -> T) -> T {
        var lib = library
        let out = f(&lib)
        custom = lib.agents
        skills = lib.skills
        commands = lib.commands
        persist()
        return out
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
        if let a = agentNamed(name) { return a }
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

    /// Importe un agent depuis du Markdown. Réimporter la même source remplace
    /// l'ancienne version.
    @discardableResult
    func importMarkdown(_ text: String, source: String? = nil) -> Agent? {
        update { $0.installMarkdown(text, source: source) }
    }

    /// Importe un agent depuis une adresse (fichier brut, page github.com/…/blob/…, gist).
    func importURL(_ raw: String) async throws -> Agent {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = try await GitHubAPI(token: nil).libraryDownload(url)
        guard let a = importMarkdown(text, source: url) else {
            throw GitHubError("Ce fichier ne contient pas d'agent (consigne vide).")
        }
        return a
    }

    // MARK: - Bibliothèque : sous-agents, skills et commandes

    /// Un sous-agent par son nom (les vôtres d'abord).
    func agentNamed(_ name: String) -> Agent? { library.agentNamed(name) }

    func skillNamed(_ name: String) -> Skill? { library.skillNamed(name) }

    func commandNamed(_ name: String) -> SlashCommand? { library.commandNamed(name) }

    func setSkillAlways(_ id: String, _ v: Bool) { update { $0.setSkillAlways(id, v) } }

    func removeSkill(_ id: String) { update { $0.removeSkill(id) } }

    func removeCommand(_ id: String) { update { $0.removeCommand(id) } }

    /// Est-il déjà installé (même fichier source) ?
    func isInstalled(_ item: NexoraKit.LibraryItem) -> Bool { library.isInstalled(item) }

    /// Installe un élément d'un dépôt dont le fichier est déjà lu.
    @discardableResult
    func install(_ item: NexoraKit.LibraryItem, text: String) -> Bool { update { $0.install(item, text: text) } }

    /// Télécharge et installe un élément d'un dépôt (le réinstaller le met à jour).
    func installItem(_ api: GitHubAPI, _ item: NexoraKit.LibraryItem) async -> Bool {
        guard let text = try? await api.libraryRawFile(item.owner, item.repo, ref: item.ref, path: item.path) else { return false }
        return install(item, text: text)
    }

    /// Le résultat d'une installation depuis un lien.
    enum SkillLinkResult {
        /// Installées : le compte rendu à afficher.
        case done(String)
        /// Trop de skills pour tout installer d'un coup : à choisir dans la
        /// bibliothèque, ouverte sur ce dépôt.
        case choose(spec: String, count: Int)
    }

    /// Installe les skills d'un lien GitHub (dépôt, dossier, page ou fichier
    /// SKILL.md). Au-delà de `SkillImport.maxDirect`, propose de choisir.
    func installSkills(fromLink link: String, api: GitHubAPI) async throws -> SkillLinkResult {
        guard let spec = SkillImport.spec(from: link) else {
            throw GitHubError("Collez un lien GitHub : propriétaire/dépôt, un dossier, ou la page d'un SKILL.md.")
        }
        let scan = try await api.libraryScan(spec)
        let found = SkillImport.skills(in: scan)
        if found.isEmpty {
            if !scan.isEmpty { return .choose(spec: spec, count: scan.items.count) }
            throw GitHubError("Aucune skill (fichier SKILL.md) à cette adresse.")
        }
        if found.count > SkillImport.maxDirect { return .choose(spec: spec, count: found.count) }
        let texts = await api.libraryTexts(found)
        var installed = 0, already = 0, failed = 0
        for (item, text) in zip(found, texts) {
            let was = isInstalled(item)
            if let text, install(item, text: text) {
                if was { already += 1 } else { installed += 1 }
            } else {
                failed += 1
            }
        }
        return .done(SkillImport.report(installed: installed, already: already, failed: failed))
    }

    /// Relit sur GitHub chaque skill installée depuis un dépôt (nouvelle version
    /// des instructions), en gardant son réglage « Toujours ». Rend le compte rendu.
    func updateSkills(api: GitHubAPI) async -> String {
        let items = skills.compactMap(SkillImport.item(for:))
        if items.isEmpty { return "Aucune skill venue de GitHub à mettre à jour." }
        let texts = await api.libraryTexts(items)
        var ok = 0, failed = 0
        for (item, text) in zip(items, texts) {
            if let text, install(item, text: text) { ok += 1 } else { failed += 1 }
        }
        var out = ok == 1 ? "1 skill à jour" : "\(ok) skills à jour"
        if failed > 0 { out += " · \(failed) introuvable\(failed > 1 ? "s" : "") sur GitHub" }
        return out + "."
    }

    /// Le contenu d'un fichier d'une skill (scripts, références), lu sur GitHub.
    func readSkillFile(_ api: GitHubAPI, _ skill: Skill, _ file: String) async throws -> String {
        try await api.librarySkillFile(skill, file: file)
    }

    private func persist() {
        let data = library.encoded()
        defaults.set(data.agents, forKey: "agents")
        defaults.set(data.skills, forKey: "skills")
        defaults.set(data.commands, forKey: "commands")
    }
}
