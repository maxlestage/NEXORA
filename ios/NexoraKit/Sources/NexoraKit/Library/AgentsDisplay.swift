import Foundation

/// L'écran Agents, rendu simple : une recherche qui pardonne les accents et la casse,
/// et les outils d'un agent résumés en mots simples au lieu d'une liste technique.
public enum AgentsDisplay {
    /// Vrai si la recherche est vide, ou si l'un des textes la contient
    /// (sans tenir compte des majuscules, des accents ni des espaces autour).
    public static func matches(_ query: String, _ texts: String...) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return true }
        return texts.contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// « 1 outil », « 5 outils », ou rien s'il n'y en a pas.
    public static func toolsSummary(_ tools: [String]) -> String {
        switch tools.count {
        case 0: ""
        case 1: "1 outil"
        default: "\(tools.count) outils"
        }
    }

    /// Où placer « Ajouter des skills » dans l'onglet Skills.
    public enum AddPlace: Sendable, Equatable { case top, bottom, hidden }

    /// En haut tant qu'il n'y a rien (c'est l'action principale), sous la liste dès qu'il y a
    /// des skills ou des commandes (on vient d'abord pour les voir), masqué pendant une
    /// recherche (il cacherait les résultats).
    public static func addPlace(hasItems: Bool, query: String) -> AddPlace {
        if !hasItems { return .top }
        return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .bottom : .hidden
    }

    /// « Skills (3) » : l'en-tête de section avec le nombre, sans nombre si 0.
    public static func header(_ title: String, count: Int) -> String {
        count > 0 ? "\(title) (\(count))" : title
    }
}

/// Logique d'affichage du choix de l'agent d'une conversation (AgentPickerSheet),
/// testable sous Linux.
public enum AgentPickerDisplay {
    /// Une catégorie et ses agents retenus.
    public struct Group: Equatable, Sendable, Identifiable {
        public let category: String
        public let agents: [Agent]
        public var id: String { category }

        public init(category: String, agents: [Agent]) {
            self.category = category
            self.agents = agents
        }
    }

    /// L'agent correspond-il à la recherche ? Chaque mot doit se trouver dans son nom, sa
    /// description ou sa catégorie, sans majuscules, accents ni tirets (« redac mail »
    /// trouve « Rédacteur d'e-mails »).
    public static func matches(_ query: String, _ a: Agent) -> Bool {
        ModelPickerDisplay.matches(query, model: a.name, detail: a.description, provider: a.category)
    }

    /// Les agents qui correspondent à la recherche, rangés par catégorie dans l'ordre
    /// reçu ; les catégories vides ne sont pas gardées.
    public static func groups(_ agents: [Agent], query: String) -> [Group] {
        var order: [String] = []
        var found: [String: [Agent]] = [:]
        for a in agents where matches(query, a) {
            if found[a.category] == nil { order.append(a.category) }
            found[a.category, default: []].append(a)
        }
        return order.map { Group(category: $0, agents: found[$0] ?? []) }
    }

    /// La ligne « Sans agent » est-elle montrée ? Oui sans recherche, ou si la recherche
    /// la désigne (« sans », « assistant »…).
    public static func showsNone(query: String) -> Bool {
        ModelPickerDisplay.matches(query, model: "Sans agent", detail: "Assistant personnel")
    }

    /// Titre de l'état vide (nil s'il reste quelque chose à choisir).
    public static func emptyTitle(found: Int, query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard found == 0, !showsNone(query: q) else { return nil }
        return "Aucun agent pour « \(q) »"
    }

    /// Ce que lit VoiceOver pour une ligne : « Relecteur, Relit votre code, agent actuel ».
    public static func accessibility(name: String, description: String, selected: Bool) -> String {
        var parts = [name]
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { parts.append(d) }
        if selected { parts.append("agent actuel") }
        return parts.joined(separator: ", ")
    }
}

/// La fiche d'un agent (AgentEditorView), rendue simple : outils en mots simples,
/// raison du bouton Enregistrer grisé, et nom à taper (@…) pour appeler l'agent.
public enum AgentEditorDisplay {
    /// Le nom d'un outil en mots simples (le nom technique reste en légende).
    public static func toolLabel(_ name: String) -> String {
        switch name {
        case "list_files": "Lister les fichiers"
        case "read_file": "Lire un fichier"
        case "find_in_file": "Chercher dans un fichier"
        case "search_code": "Chercher dans le dépôt"
        case "edit_file": "Modifier un passage"
        case "write_file": "Écrire un fichier"
        case "delete_file": "Supprimer un fichier"
        case "github": "Utiliser GitHub (CI, pull requests)"
        default: name
        }
    }

    /// Les outils que l'on peut cocher (« finish » est toujours permis).
    public static func choosableTools(_ all: [String]) -> [String] {
        all.filter { $0 != "finish" }
    }

    /// Le résumé de la ligne Outils, repliée : « Tous » si aucun n'est coché
    /// (l'agent peut alors tous les utiliser), sinon « 3 sur 8 ».
    public static func toolsValue(_ tools: [String], total: Int) -> String {
        let n = tools.filter { $0 != "finish" }.count
        return n == 0 || n >= total ? "Tous" : "\(n) sur \(total)"
    }

    /// « @mon-agent » : ce que l'on tape au début d'un message pour appeler l'agent,
    /// ou nil tant qu'il n'a pas de nom.
    public static func handle(_ name: String) -> String? {
        let words = name.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? nil : "@" + words.joined(separator: "-").lowercased()
    }

    /// Pourquoi Enregistrer est grisé, ou nil si l'on peut enregistrer.
    public static func missing(name: String, prompt: String) -> String? {
        let noName = name.trimmingCharacters(in: .whitespaces).isEmpty
        let noPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (noName, noPrompt) {
        case (true, true): return "Donnez un nom et une consigne pour enregistrer."
        case (true, false): return "Donnez un nom pour enregistrer."
        case (false, true): return "Écrivez une consigne pour enregistrer."
        default: return nil
        }
    }
}
