import Foundation

/// Logique d'affichage des issues et des pull requests d'un dépôt (IssuesListView,
/// IssueDetailView), testable sous Linux.
public enum IssuesDisplay {
    /// À partir de ce nombre d'éléments, une recherche apparaît.
    public static let searchFrom = 8

    /// Les éléments qui correspondent à la recherche : titre, numéro (« 12 » ou
    /// « #12 ») ou auteur, sans tenir compte des majuscules ni des accents.
    public static func filter(_ items: [Issue], query: String) -> [Issue] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return items }
        let number = q.hasPrefix("#") ? String(q.dropFirst()) : q
        return items.filter {
            String($0.number) == number
                || AgentsDisplay.matches(q, $0.title, $0.user.map { "@" + $0.login } ?? "")
        }
    }

    /// « 3 commentaires », « 1 commentaire », rien à zéro.
    public static func comments(_ n: Int?) -> String? {
        guard let n, n > 0 else { return nil }
        return n == 1 ? "1 commentaire" : "\(n) commentaires"
    }

    /// La ligne sous le titre : « #12 · @max · 3 commentaires · il y a 2 j ».
    public static func detail(_ i: Issue, now: Date = Date()) -> String {
        var parts = ["#\(i.number)"]
        if let u = i.user { parts.append("@\(u.login)") }
        if let c = comments(i.comments) { parts.append(c) }
        if let u = i.updatedAt, let d = ReposDisplay.parseDate(u) { parts.append(WorkspaceText.ago(d, now: now)) }
        return parts.joined(separator: " · ")
    }

    /// La ligne lue d'un trait par VoiceOver : « Pull request 12, Corriger le menu,
    /// par max, 3 commentaires ».
    public static func accessibility(_ i: Issue) -> String {
        var parts = ["\(i.isPull ? "Pull request" : "Issue") \(i.number)", i.title]
        if let u = i.user { parts.append("par \(u.login)") }
        if let c = comments(i.comments) { parts.append(c) }
        return parts.joined(separator: ", ")
    }

    /// L'état vide : « Aucune pull request ouverte », « Aucune issue fermée ».
    public static func emptyTitle(pulls: Bool, open: Bool) -> String {
        "Aucune \(pulls ? "pull request" : "issue") \(open ? "ouverte" : "fermée")"
    }

    /// Le texte sous l'état vide.
    public static func emptyHint(pulls: Bool, open: Bool) -> String {
        if !open { return "Rien n'a encore été fermé." }
        return pulls ? "Les pull requests de l'agent apparaîtront ici." : "Créez-en une avec « Nouvelle issue », en bas."
    }

    /// Le titre au-dessus de la liste : « 1 ouverte », « 12 fermées ».
    public static func count(_ n: Int, open: Bool) -> String {
        "\(n) \(open ? "ouverte" : "fermée")\(n > 1 ? "s" : "")"
    }

    /// La question posée avant de fusionner (action difficile à défaire).
    public static func mergeQuestion(_ i: Issue) -> String {
        "Fusionner « \(i.title) » ? Ses commits sont regroupés en un seul sur la branche principale."
    }

    /// La question posée avant de fermer.
    public static func closeQuestion(_ i: Issue) -> String {
        "Fermer \(i.isPull ? "la pull request" : "l'issue") #\(i.number) ? Vous pourrez la rouvrir."
    }
}
