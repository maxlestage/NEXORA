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
}
