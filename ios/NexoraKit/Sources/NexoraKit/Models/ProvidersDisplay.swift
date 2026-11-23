import Foundation

/// Logique d'affichage de l'onglet Modèles (liste des fournisseurs), testable sous Linux.
public enum ProvidersDisplay {
    /// Les filtres proposés, dans l'ordre : clé et libellé.
    public static let filters: [(key: String, label: String)] = [
        ("all", "Tous"), ("ready", "Prêts"), ("free", "Gratuits"), ("local", "Locaux"),
    ]

    /// Le fournisseur passe-t-il le filtre (« all », « ready », « free », « local ») ?
    public static func passes(_ p: ProviderDef, filter: String, ready: Bool) -> Bool {
        switch filter {
        case "free": p.free
        case "local": p.local || p.custom
        case "ready": ready
        default: true
        }
    }

    /// Les fournisseurs qui passent le filtre et la recherche (nom ou description,
    /// sans majuscules ni accents). L'ordre reçu est gardé.
    public static func filter(_ providers: [ProviderDef], filter: String, query: String,
                              isReady: (ProviderDef) -> Bool) -> [ProviderDef] {
        providers.filter {
            passes($0, filter: filter, ready: isReady($0))
                && AgentsDisplay.matches(query, $0.name, $0.description)
        }
    }

    /// Libellé d'un filtre avec son nombre : « Prêts · 3 » (« Tous » reste sans nombre).
    public static func filterLabel(_ key: String, label: String, providers: [ProviderDef],
                                   isReady: (ProviderDef) -> Bool) -> String {
        guard key != "all" else { return label }
        let n = providers.count { passes($0, filter: key, ready: isReady($0)) }
        return "\(label) · \(n)"
    }

    /// Une section de la liste : titre (vide = pas d'en-tête) et fournisseurs.
    public struct Section: Equatable, Sendable {
        public let title: String
        public let ids: [String]
    }

    /// Les fournisseurs prêts d'abord (« Prêts (n) »), puis « À configurer (n) ».
    /// Pas d'en-tête si un seul groupe n'est pas vide.
    public static func sections(_ list: [ProviderDef], isReady: (ProviderDef) -> Bool) -> [Section] {
        let ready = list.filter(isReady).map(\.id)
        let todo = list.filter { !isReady($0) }.map(\.id)
        if ready.isEmpty || todo.isEmpty { return list.isEmpty ? [] : [Section(title: "", ids: ready + todo)] }
        return [Section(title: "Prêts (\(ready.count))", ids: ready),
                Section(title: "À configurer (\(todo.count))", ids: todo)]
    }

    /// Étiquettes courtes sous le nom (l'état prêt / à configurer est donné par la section) :
    /// « gratuit », puis « local », « perso » ou « sans clé ».
    public static func tags(_ p: ProviderDef) -> [String] {
        var t: [String] = []
        if p.free { t.append("gratuit") }
        if p.local { t.append("local") } else if p.custom { t.append("perso") } else if !p.needsKey { t.append("sans clé") }
        return t
    }

    /// Ce que lit VoiceOver pour une ligne : « Groq, prêt, gratuit ».
    public static func accessibility(_ p: ProviderDef, ready: Bool) -> String {
        ([p.name, ready ? "prêt" : "clé requise"] + tags(p)).joined(separator: ", ")
    }

    /// Carte « Modèle par défaut » en tête de l'onglet (touchable : ouvre le sélecteur).
    public struct DefaultCard: Equatable, Sendable {
        public let note: String
        public let accessibility: String
        public let hint: String
        /// « 3 fournisseurs prêts » : ligne affichée sous le modèle en très grande taille
        /// de texte, à la place du compteur de droite qui écrasait le nom.
        public let readyLine: String
    }

    /// Sous-titre et VoiceOver de la carte : le fournisseur, ou ce qu'il faut faire
    /// quand aucun fournisseur n'est prêt.
    public static func defaultCard(model: String, provider: String, readyCount: Int) -> DefaultCard {
        let ready = readyCount == 0 ? "aucun fournisseur prêt"
            : readyCount == 1 ? "1 fournisseur prêt" : "\(readyCount) fournisseurs prêts"
        let note = readyCount == 0 ? "Ajoutez une clé ci-dessous" : provider
        let who = provider.isEmpty ? model : "\(model), \(provider)"
        return DefaultCard(note: note,
                           accessibility: "Modèle par défaut : \(who). \(ready.prefix(1).uppercased() + ready.dropFirst())",
                           hint: "Touchez pour changer de modèle",
                           readyLine: ready.prefix(1).uppercased() + ready.dropFirst())
    }

    /// Les actions de l'appui long sur un fournisseur (sans ouvrir sa fiche).
    public enum QuickAction: Sendable, Hashable {
        /// Ouvrir la page où créer une clé (gratuite ou non).
        case getKey
        /// Enregistrer la clé copiée dans le presse-papiers.
        case pasteKey
        /// Ouvrir la documentation du fournisseur.
        case docs
    }

    /// Les actions proposées : « Obtenir une clé » et « Coller la clé » tant qu'il en
    /// manque une, puis la documentation. Rien pour un fournisseur sans clé ni lien.
    public static func quickActions(_ p: ProviderDef, hasKey: Bool) -> [QuickAction] {
        var a: [QuickAction] = []
        let missing = p.needsKey && !hasKey
        if missing, !(p.keyUrl ?? "").isEmpty { a.append(.getKey) }
        if missing { a.append(.pasteKey) }
        if !(p.docsUrl ?? "").isEmpty { a.append(.docs) }
        return a
    }

    /// Libellé de « Obtenir une clé » (« Clé gratuite » pour un fournisseur gratuit).
    public static func getKeyLabel(_ p: ProviderDef) -> String {
        p.free ? "Clé gratuite" : "Obtenir une clé"
    }

    /// La clé lue dans le presse-papiers, si elle en a l'air : un seul mot de 8 à
    /// 512 caractères, sans espace ni retour à la ligne (une phrase ou une adresse
    /// copiée par erreur n'est pas enregistrée).
    public static func pastedKey(_ text: String?) -> String? {
        guard let k = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              (8...512).contains(k.count),
              !k.contains(where: \.isWhitespace),
              !k.hasPrefix("http://"), !k.hasPrefix("https://") else { return nil }
        return k
    }

    /// Le retour après « Coller la clé » : réussite, ou ce qui ne va pas.
    public static func pasteToast(name: String, saved: Bool) -> String {
        saved ? "Clé enregistrée : \(name) est prêt"
            : "Copiez d'abord la clé de \(name), puis réessayez"
    }
}

/// Logique d'affichage de la fiche d'un fournisseur (ProviderDetailView), testable sous Linux.
public enum ProviderDetailDisplay {
    /// « Comment faire » est-il replié ? Oui une fois le fournisseur configuré (clé
    /// enregistrée, ou serveur local qui a déjà donné ses modèles) : les modèles, l'action
    /// fréquente, remontent. Sinon les étapes restent ouvertes pour guider la mise en place.
    public static func helpFolded(_ p: ProviderDef, hasKey: Bool, modelCount: Int) -> Bool {
        hasKey || (p.local && modelCount > 0)
    }

    /// Au-delà de ce nombre de modèles, un champ de recherche est proposé.
    public static let searchThreshold = 12

    /// Le champ de recherche des modèles est-il utile ?
    public static func showsSearch(count: Int) -> Bool { count > searchThreshold }

    /// Les modèles qui correspondent à la recherche (id ou détail, sans majuscules ni
    /// accents), le modèle par défaut en tête ; l'ordre reçu est gardé pour les autres.
    public static func models(_ list: [ModelInfo], query: String, defaultId: String?) -> [ModelInfo] {
        let found = list.filter { AgentsDisplay.matches(query, $0.id, $0.detail ?? "") }
        guard let d = defaultId, let i = found.firstIndex(where: { $0.id == d }), i > 0 else { return found }
        var out = found
        out.insert(out.remove(at: i), at: 0)
        return out
    }

    /// Ce que lit VoiceOver pour un modèle de la fiche d'un fournisseur :
    /// « gpt-4o, 128k de contexte, gratuit, modèle par défaut ».
    public static func modelAccessibility(id: String, detail: String?, free: Bool, isDefault: Bool) -> String {
        var parts = [id]
        if let d = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { parts.append(d) }
        if free { parts.append("gratuit") }
        if isDefault { parts.append("modèle par défaut") }
        return parts.joined(separator: ", ")
    }

    /// L'aide lue après la ligne : rien si le modèle est déjà celui par défaut.
    public static func modelHint(isDefault: Bool) -> String {
        isDefault ? "" : "Touchez deux fois pour en faire le modèle par défaut"
    }

    /// L'adresse du serveur est-elle affichée d'emblée ? Oui pour un serveur local ou
    /// perso, ou si elle a été modifiée ; sinon elle est rangée dans « Adresse avancée ».
    public static func addressInline(_ p: ProviderDef, modified: Bool) -> Bool {
        p.local || p.custom || modified
    }

    /// Reste-t-il une clé ou une adresse tapée mais pas enregistrée ? (comparaison sans
    /// espaces autour) Sert à enregistrer en quittant la fiche, pour ne rien perdre.
    public static func unsaved(key: String, storedKey: String?, url: String, baseUrl: String) -> Bool {
        let clean = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return clean(key) != clean(storedKey ?? "") || clean(url) != clean(baseUrl)
    }

    /// L'adresse d'un nouveau serveur perso, prête à enregistrer : sans espaces autour ni
    /// « / » final, complétée de « http:// » si l'utilisateur n'a tapé que
    /// « 192.168.1.10:8080/v1 ». `nil` si elle est inutilisable (vide, espaces, pas d'hôte,
    /// autre protocole que http/https) : « Ajouter » reste alors éteint.
    public static func serverAddress(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") && !s.hasSuffix("://") { s.removeLast() }
        guard let c = URLComponents(string: s), let scheme = c.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = c.host, !host.isEmpty else { return nil }
        return s
    }

    /// L'adresse à enregistrer quand on quitte la fiche d'un fournisseur : la nouvelle,
    /// nettoyée, si elle est utilisable ET différente de l'actuelle ; sinon `nil` (rien n'est
    /// enregistré). Avant, un champ vidé ou une faute de frappe était enregistré tel quel et
    /// rendait le fournisseur inutilisable sans rien dire.
    public static func editedAddress(_ raw: String, current: String) -> String? {
        guard let address = serverAddress(raw) else { return nil }
        return address == (serverAddress(current) ?? current) ? nil : address
    }

    /// Le nom enregistré pour un nouveau serveur : celui tapé, sinon l'hôte de l'adresse
    /// (un nom vide laissait une ligne sans titre dans la liste).
    public static func serverName(_ raw: String, address: String) -> String {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return URLComponents(string: address)?.host ?? "Serveur perso"
    }

    /// Ce qui s'affiche sous le formulaire quand l'adresse ne convient pas (rien si elle va).
    public static func serverAddressHint(_ raw: String) -> String? {
        guard serverAddress(raw) == nil else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Indiquez l'adresse du serveur, par ex. http://192.168.1.10:8080/v1"
            : "Adresse invalide : elle doit ressembler à http://192.168.1.10:8080/v1"
    }

    /// Message de confirmation avant de supprimer un serveur perso.
    public static func deleteConfirmation(name: String, isDefault: Bool) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "« \(n.isEmpty ? "Serveur perso" : n) » et sa clé seront supprimés."
        return isDefault ? base + " C'est votre modèle par défaut : un autre sera utilisé à sa place." : base
    }

    /// Le bouton « Coller » s'affiche-t-il dans le champ de la clé ? Seulement quand le
    /// champ est vide : coller la clé copiée devient un seul appui.
    public static func showsPaste(key: String) -> Bool {
        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Phrase de la liste de modèles vide, qui dit quoi faire ensuite.
    public static func emptyModels(needsKey: Bool, hasKey: Bool) -> String {
        needsKey && !hasKey
            ? "Aucun modèle : collez d'abord la clé, puis chargez la liste."
            : "Aucun modèle pour l'instant : chargez la liste du serveur."
    }

    /// Durée lisible : « 850 ms », « 1,2 s ».
    public static func duration(ms: Int) -> String {
        guard ms >= 1000 else { return "\(max(ms, 0)) ms" }
        let tenths = (ms + 50) / 100
        return "\(tenths / 10),\(tenths % 10) s"
    }

    /// Résultat d'un test réussi, en mots simples : « Ça marche : gpt-4o a répondu en 1,2 s (« OK »). »
    public static func testSuccess(model: String, ms: Int, answer: String) -> String {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = a.count > 80 ? String(a.prefix(80)) + "…" : a
        let said = short.isEmpty ? "" : " (« \(short) »)"
        return "Ça marche : \(model) a répondu en \(duration(ms: ms))\(said)."
    }
}

/// Logique d'affichage du sélecteur de modèle du chat (ModelPickerSheet), testable sous Linux.
public enum ModelPickerDisplay {
    /// Le texte sans majuscules, accents ni séparateurs (« Llama-3.1 » → « llama31 »).
    static func squash(_ s: String) -> String {
        let plain = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(plain.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Le modèle correspond-il à la recherche ? Chaque mot doit se trouver dans l'id du
    /// modèle, son détail ou le nom du fournisseur, sans tenir compte des tirets, points,
    /// espaces, majuscules ni accents : « llama 3 » trouve « llama-3.1-8b ».
    public static func matches(_ query: String, model: String, detail: String = "", provider: String = "") -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map { squash(String($0)) }.filter { !$0.isEmpty }
        if words.isEmpty { return true }
        let hay = squash(model) + " " + squash(detail) + " " + squash(provider)
        return words.allSatisfy { hay.contains($0) }
    }

    /// Phrase d'une section de fournisseur restée vide (nil si elle a des modèles).
    public static func emptySection(onlyFree: Bool, hasLiveList: Bool) -> String? {
        if onlyFree { return "Aucun modèle gratuit chez ce fournisseur." }
        return hasLiveList ? "Aucun modèle." : "Aucun modèle : touchez « Charger la liste »."
    }

    /// État vide de toute la liste : titre, phrase et bouton qui la débloque
    /// (nil s'il reste au moins un modèle à montrer).
    public struct Empty: Equatable, Sendable {
        public let title: String
        public let message: String
        public let action: String
    }

    public static func empty(found: Int, query: String, onlyFree: Bool) -> Empty? {
        guard found == 0 else { return nil }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if onlyFree {
            return Empty(title: q.isEmpty ? "Aucun modèle gratuit" : "Aucun modèle gratuit pour « \(q) »",
                         message: "Le filtre « Gratuits » cache les modèles payants.",
                         action: "Voir aussi les payants")
        }
        if !q.isEmpty {
            return Empty(title: "Aucun modèle pour « \(q) »",
                         message: "Essayez un autre nom, ou montrez tous les fournisseurs.",
                         action: "Effacer la recherche")
        }
        return nil
    }

    /// Section du haut (recherche vide) : le modèle actuel en tête s'il n'est pas déjà un
    /// favori, puis les favoris. Ainsi le modèle en cours se retrouve sans faire défiler.
    public static func top(selected: ModelRef?, favorites: [ModelRef]) -> [ModelRef] {
        guard let selected, !favorites.contains(selected) else { return favorites }
        return [selected] + favorites
    }

    /// Titre de cette section (nil si elle est vide).
    public static func topTitle(selected: ModelRef?, favorites: [ModelRef]) -> String? {
        let current = selected.map { !favorites.contains($0) } ?? false
        switch (current, favorites.isEmpty) {
        case (false, true): return nil
        case (true, true): return "Modèle actuel"
        case (true, false): return "Actuel et favoris"
        case (false, false): return "⭐ Favoris"
        }
    }

    /// Légende de la ligne « Chercher les nouveaux modèles », placée en bas (action rare).
    public static func catalogNote(updated: String) -> String {
        updated.isEmpty ? "Liste intégrée à l'app" : "Liste du \(updated)"
    }

    /// Les badges d'un modèle en une ligne (« gratuit · local »), pour la très grande taille
    /// de texte où ils passent sous le nom ; `nil` s'il n'y en a aucun.
    public static func tags(free: Bool, local: Bool) -> String? {
        let tags = (free ? ["gratuit"] : []) + (local ? ["local"] : [])
        return tags.isEmpty ? nil : tags.joined(separator: " · ")
    }

    /// Lignes laissées au nom d'un modèle : une seule d'ordinaire, trois en très grand texte
    /// (sinon « claude-son… » et « claude-son… » ne se distinguent plus).
    public static func lineLimit(bigText: Bool) -> Int { bigText ? 3 : 1 }

    /// Ce que lit VoiceOver pour une ligne : « gpt-4o, OpenAI, gratuit, modèle actuel ».
    public static func accessibility(model: String, provider: String, free: Bool, local: Bool, selected: Bool) -> String {
        var parts = [model, provider]
        if free { parts.append("gratuit") }
        if local { parts.append("local") }
        if selected { parts.append("modèle actuel") }
        return parts.joined(separator: ", ")
    }
}
