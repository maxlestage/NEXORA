import Foundation

/// L'écran Agents, rendu simple : une recherche qui pardonne les accents et la casse,
/// et les outils d'un agent résumés en mots simples au lieu d'une liste technique.
public enum AgentsDisplay {
    /// Vrai si la recherche est vide, ou si chacun de ses mots se trouve dans l'un des
    /// textes, dans n'importe quel ordre (« code revue » trouve « Revue de code »),
    /// sans tenir compte des majuscules, des accents ni des espaces autour.
    public static func matches(_ query: String, _ texts: String...) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { w in
            texts.contains { $0.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
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

    /// Ce que l'on supprime dans l'onglet (agent perso, skill ou commande).
    public enum RemovalKind: Sendable, Equatable { case agent, skill, command }

    /// Titre de la confirmation : « Supprimer l'agent « Relecteur » ? ».
    public static func removalTitle(_ name: String, kind: RemovalKind) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let what = switch kind {
        case .agent: "l'agent"
        case .skill: "la skill"
        case .command: "la commande"
        }
        return n.isEmpty ? "Supprimer \(what) ?" : "Supprimer \(what) « \(n) » ?"
    }

    /// Une phrase sous le titre : ce qui est perdu et ce qui reste.
    public static func removalMessage(_ kind: RemovalKind) -> String {
        switch kind {
        case .agent: "Sa consigne est perdue ; ses conversations restent, sans elle."
        case .skill, .command: "Vous pourrez la réinstaller depuis la bibliothèque."
        }
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
    /// reçu ; les catégories vides ne sont pas gardées. `excluding` : l'agent déjà montré
    /// en tête (« Agent actuel »), pour ne pas l'afficher deux fois.
    public static func groups(_ agents: [Agent], query: String, excluding: String? = nil) -> [Group] {
        var order: [String] = []
        var found: [String: [Agent]] = [:]
        for a in agents where a.id != excluding && matches(query, a) {
            if found[a.category] == nil { order.append(a.category) }
            found[a.category, default: []].append(a)
        }
        return order.map { Group(category: $0, agents: found[$0] ?? []) }
    }

    /// L'agent actuel, montré en tête (section « Agent actuel ») sans recherche, pour le
    /// retrouver sans faire défiler ; nil sans agent, pendant une recherche, ou s'il n'est
    /// plus dans la bibliothèque.
    public static func current(_ agents: [Agent], selected: Agent?, query: String) -> Agent? {
        guard let selected, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return agents.first { $0.id == selected.id }
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

    /// Lignes laissées à la description d'un agent : deux d'ordinaire, quatre en très grand
    /// texte (deux lignes n'y montrent que quelques mots, pas de quoi choisir).
    public static func descriptionLines(bigText: Bool) -> Int { bigText ? 4 : 2 }

    /// Le nom affiché : en très grand texte l'emoji passe devant le nom (« 🔍 Relecteur »)
    /// au lieu d'occuper une colonne à part, qui prend la largeur de la description.
    public static func title(emoji: String, name: String, bigText: Bool) -> String {
        let e = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return bigText && !e.isEmpty ? "\(e) \(name)" : name
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

    /// Fermer la fiche ferait perdre une saisie : l'agent n'est plus celui de l'ouverture.
    /// Des espaces ajoutés autour d'un texte ne comptent pas.
    public static func losesChanges(original: Agent, edited: Agent) -> Bool {
        func tidy(_ a: Agent) -> Agent {
            var b = a
            b.name = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
            b.description = a.description.trimmingCharacters(in: .whitespacesAndNewlines)
            b.emoji = a.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            b.systemPrompt = a.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            b.category = a.category.trimmingCharacters(in: .whitespacesAndNewlines)
            b.tools = a.tools.sorted()
            return b
        }
        return tidy(original) != tidy(edited)
    }

    /// Le titre de la question posée avant de fermer une fiche modifiée.
    public static func leaveTitle(isNew: Bool) -> String {
        isNew ? "Abandonner ce nouvel agent ?" : "Abandonner les modifications ?"
    }

    /// Ce que l'on perd en abandonnant, et pourquoi « Enregistrer » manque s'il manque.
    public static func leaveMessage(isNew: Bool, missing: String?) -> String {
        let lost = isNew ? "L'agent ne sera pas créé." : "L'agent restera comme avant."
        guard let missing else { return lost }
        return lost + " " + missing
    }
}
