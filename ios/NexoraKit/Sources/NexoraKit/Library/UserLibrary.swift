import Foundation

/// Ce que l'utilisateur a installé ou créé : ses agents, ses skills et ses
/// commandes. Les règles de l'app Flutter (`AgentState`), sans interface : noms
/// pour `@agent` et `/commande`, installation depuis un dépôt (la réinstaller met à
/// jour), « toujours active »… Enregistré sous les clés `agents`, `skills` et
/// `commands` (même JSON que l'app Flutter).
public struct UserLibrary: Sendable, Hashable {
    /// Les agents installés ou créés (sans ceux de l'app).
    public var agents: [Agent]
    public var skills: [Skill]
    public var commands: [SlashCommand]

    public init(agents: [Agent] = [], skills: [Skill] = [], commands: [SlashCommand] = []) {
        self.agents = agents
        self.skills = skills
        self.commands = commands
    }

    // MARK: - Noms

    public func skillNamed(_ name: String) -> Skill? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return skills.first { $0.name.lowercased() == n }
    }

    public func commandNamed(_ name: String) -> SlashCommand? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return commands.first { $0.name.lowercased() == n }
    }

    /// Un sous-agent par son nom (pour `@nom` dans le chat et la délégation). Les
    /// agents installés ou créés passent avant ceux de l'app (même nom).
    public func agentNamed(_ name: String, builtin: [Agent] = Catalog.builtinAgents) -> Agent? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)
        }
        let wanted = norm(n)
        return (agents + builtin).first { $0.name.lowercased() == n || norm($0.name) == wanted }
    }

    // MARK: - Agents

    public mutating func upsert(_ a: Agent) {
        if let i = agents.firstIndex(where: { $0.id == a.id }) { agents[i] = a } else { agents.append(a) }
    }

    public mutating func removeAgent(_ id: String) {
        agents.removeAll { $0.id == id }
    }

    /// Installe un agent depuis son texte Markdown. Réinstaller la même source
    /// remplace l'ancienne version.
    @discardableResult
    public mutating func installMarkdown(_ md: String, source: String? = nil, id: String = "inst:\(newId())") -> Agent? {
        guard let a = Agent.fromMarkdown(md, id: id, source: source) else { return nil }
        if let source { agents.removeAll { $0.source == source } }
        upsert(a)
        return a
    }

    // MARK: - Skills et commandes

    public mutating func setSkillAlways(_ id: String, _ v: Bool) {
        for i in skills.indices where skills[i].id == id { skills[i].always = v }
    }

    public mutating func removeSkill(_ id: String) {
        skills.removeAll { $0.id == id }
    }

    public mutating func removeCommand(_ id: String) {
        commands.removeAll { $0.id == id }
    }

    // MARK: - Installation depuis un dépôt

    /// Est-il déjà installé (même fichier source) ?
    public func isInstalled(_ item: LibraryItem) -> Bool {
        switch item.kind {
        case .agent: agents.contains { $0.source == item.source }
        case .skill: skills.contains { $0.source == item.source }
        case .command: commands.contains { $0.source == item.source }
        }
    }

    /// Installe un élément trouvé dans un dépôt, à partir du texte de son fichier
    /// (le réinstaller le met à jour). Rend `false` si le fichier est vide.
    @discardableResult
    public mutating func install(_ item: LibraryItem, text: String) -> Bool {
        switch item.kind {
        case .agent:
            guard var a = Agent.fromMarkdown(text, id: "inst:\(newId())", source: item.source) else { return false }
            if a.name.isEmpty || a.name == "Agent" { a.name = item.name }
            if let plugin = item.plugin, a.category == "Perso" { a.category = plugin }
            agents.removeAll { $0.source == item.source }
            upsert(a)
            return true
        case .skill:
            guard let sk = Skill.fromMarkdown(
                text, id: "skill:\(newId())", fallbackName: item.name, source: item.source,
                owner: item.owner, repo: item.repo, ref: item.ref, dir: item.dir, files: item.files
            ) else { return false }
            // Une mise à jour garde le réglage « Toujours » de la skill.
            var updated = sk
            updated.always = skills.first { $0.source == item.source }?.always ?? false
            skills.removeAll { $0.source == item.source }
            skills.append(updated)
            return true
        case .command:
            guard let c = SlashCommand.fromMarkdown(text, id: "cmd:\(newId())", name: item.name, source: item.source) else { return false }
            commands.removeAll { $0.source == item.source || $0.name == c.name }
            commands.append(c)
            return true
        }
    }

    // MARK: - Enregistrement

    /// Les trois listes en JSON (clés `agents`, `skills`, `commands`).
    public func encoded() -> (agents: Data, skills: Data, commands: Data) {
        let e = JSONEncoder()
        return ((try? e.encode(agents)) ?? Data("[]".utf8), (try? e.encode(skills)) ?? Data("[]".utf8), (try? e.encode(commands)) ?? Data("[]".utf8))
    }

    /// Relit les listes enregistrées ; un élément illisible est ignoré.
    public static func decode(agents: Data?, skills: Data?, commands: Data?) -> UserLibrary {
        UserLibrary(agents: lenient(agents), skills: lenient(skills), commands: lenient(commands))
    }

    static func lenient<T: Decodable>(_ data: Data?) -> [T] {
        guard let data, let list = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return list.compactMap { item in
            guard let d = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? JSONDecoder().decode(T.self, from: d)
        }
    }
}
