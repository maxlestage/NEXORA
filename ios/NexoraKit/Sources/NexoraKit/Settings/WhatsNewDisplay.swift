import Foundation

/// Une version telle qu'affichée dans Réglages → Nouveautés : seulement les points
/// qui correspondent au filtre et à la recherche.
public struct ShownRelease: Sendable, Hashable, Identifiable {
    public let release: Release
    public let points: [String]
    /// La version la plus récente (mise en avant).
    public let isLatest: Bool

    public var id: String { release.id }

    public init(release: Release, points: [String], isLatest: Bool) {
        self.release = release
        self.points = points
        self.isLatest = isLatest
    }
}

/// Les textes et choix d'affichage de l'écran Nouveautés (WhatsNewView), testables
/// sous Linux.
public enum WhatsNewDisplay {
    /// Les versions affichées d'abord ; les plus anciennes viennent sur demande
    /// (plus de 150 versions sinon à faire défiler).
    public static let pageSize = 10

    public static let searchPrompt = "Chercher une nouveauté"

    /// La ligne d'en-tête : la version installée, sans jargon.
    public static func header(installed: String) -> String {
        "Version installée : \(installed)"
    }

    /// Les versions qui ont au moins un point du type choisi et dont chaque mot de la
    /// recherche se trouve dans le numéro, le titre ou un point (sans accents ni
    /// majuscules). Si la recherche porte sur le titre ou le numéro, tous les points
    /// (du type choisi) restent ; sinon seuls les points trouvés.
    public static func filter(_ all: [Release], only: ChangeKind?, query: String) -> [ShownRelease] {
        let words = Help.normalize(query).split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "?" }).map(String.init)
        let latest = all.first?.id
        return all.compactMap { r in
            var points = r.points.filter { only == nil || Changelog.kind(of: $0) == only }
            guard !points.isEmpty else { return nil }
            if !words.isEmpty {
                let head = Help.normalize(r.version + "\n" + r.title)
                let texts = points.map(Help.normalize)
                guard words.allSatisfy({ w in head.contains(w) || texts.contains { $0.contains(w) } }) else { return nil }
                if !words.allSatisfy({ head.contains($0) }) {
                    let kept = zip(points, texts).filter { _, t in words.contains { t.contains($0) } }.map(\.0)
                    if !kept.isEmpty { points = kept }
                }
            }
            return ShownRelease(release: r, points: points, isLatest: r.id == latest)
        }
    }

    /// Les versions à afficher et le nombre de plus anciennes encore cachées.
    public static func visible(_ shown: [ShownRelease], limit: Int) -> (items: [ShownRelease], hidden: Int) {
        let n = max(0, limit)
        return (Array(shown.prefix(n)), max(0, shown.count - n))
    }

    /// Le bouton en bas de liste : « Voir 10 versions plus anciennes (sur 37) ».
    public static func moreLabel(hidden: Int) -> String {
        let n = min(hidden, pageSize)
        let what = n == 1 ? "1 version plus ancienne" : "\(n) versions plus anciennes"
        return hidden > n ? "Voir \(what) (sur \(hidden))" : "Voir \(what)"
    }

    /// « 1 version », « 12 versions » (pendant un filtre ou une recherche).
    public static func resultsLabel(_ n: Int) -> String {
        n == 1 ? "1 version" : "\(n) versions"
    }

    /// Le message quand rien ne correspond.
    public static func emptyTitle(only: ChangeKind?, query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return "Rien pour « \(q) »" }
        if let only { return "Aucun changement « \(only.label) »" }
        return "Aucune nouveauté"
    }

    public static let emptyHint = "Essayez un seul mot, ou le filtre « Tout »."

    // MARK: - Fenêtre « Quoi de neuf » après une mise à jour

    /// Le nombre de points montrés dans la fenêtre quand plusieurs versions ont été
    /// manquées (avant : jusqu'à 10 cartes complètes à faire défiler).
    public static let highlightsLimit = 5

    /// Le titre de la fenêtre : la version installée, même si plusieurs ont été
    /// manquées (avant : « depuis la 3.0.80 », qui laissait croire qu'elle était exclue).
    public static func sheetTitle(installed: String) -> String {
        "Quoi de neuf dans NEXORA \(installed)"
    }

    /// Les points forts de plusieurs versions : d'abord les nouveautés, puis les
    /// améliorations, puis les corrections, les plus récentes en premier dans chaque
    /// groupe, sans doublon ; et le nombre de points laissés de côté.
    public static func highlights(_ releases: [Release], limit: Int = WhatsNewDisplay.highlightsLimit) -> (points: [String], hidden: Int) {
        var seen = Set<String>()
        var unique: [String] = []
        for p in releases.flatMap(\.points) {
            let key = Changelog.withoutTag(p).lowercased()
            if seen.insert(key).inserted { unique.append(p) }
        }
        let order = ChangeKind.allCases
        let sorted = order.flatMap { k in unique.filter { Changelog.kind(of: $0) == k } }
        let n = max(0, limit)
        return (Array(sorted.prefix(n)), max(0, sorted.count - n))
    }

    /// Sous les points forts : « et 12 autres changements ».
    public static func otherChanges(_ hidden: Int) -> String? {
        guard hidden > 0 else { return nil }
        return hidden == 1 ? "et 1 autre changement" : "et \(hidden) autres changements"
    }
}
