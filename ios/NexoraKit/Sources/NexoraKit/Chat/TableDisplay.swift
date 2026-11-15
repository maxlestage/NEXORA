import Foundation

/// Les textes d'un tableau du chat (en-tête, copie, VoiceOver), sans interface.
/// La première ligne est l'en-tête du tableau.
public enum TableDisplay {
    /// Nombre de colonnes (la ligne la plus longue).
    public static func columnCount(_ rows: [[String]]) -> Int {
        rows.map(\.count).max() ?? 0
    }

    /// Nombre de lignes de données (en-tête exclu).
    public static func dataRowCount(_ rows: [[String]]) -> Int {
        max(rows.count - 1, 0)
    }

    /// En-tête du bloc : « Tableau · 5 lignes » (le nombre n'apparaît qu'à partir de 2).
    public static func title(_ rows: [[String]]) -> String {
        let n = dataRowCount(rows)
        return n > 1 ? "Tableau · \(n) lignes" : "Tableau"
    }

    /// Une cellule sans sa mise en forme Markdown (gras, italique, code, liens).
    public static func plain(_ cell: String) -> String {
        var s = cell
        // [texte](lien) → texte
        while let open = s.range(of: "["),
              let mid = s.range(of: "](", range: open.upperBound..<s.endIndex),
              let close = s.range(of: ")", range: mid.upperBound..<s.endIndex) {
            let label = s[open.upperBound..<mid.lowerBound]
            s.replaceSubrange(open.lowerBound..<close.upperBound, with: label)
        }
        for mark in ["**", "__", "~~", "`"] { s = s.replacingOccurrences(of: mark, with: "") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Le tableau à copier : colonnes séparées par des tabulations, une ligne par rangée
    /// (se colle tel quel dans Numbers, Excel ou Notes).
    public static func copyText(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { plain($0).replacingOccurrences(of: "\t", with: " ") }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// Ce que VoiceOver dit d'une ligne de données : « Nom : Alice, Âge : 30 »
    /// (une cellule sans en-tête est lue seule, une cellule vide est sautée).
    public static func spokenRow(header: [String], row: [String]) -> String {
        row.indices.compactMap { i -> String? in
            let value = plain(row[i])
            if value.isEmpty { return nil }
            let name = i < header.count ? plain(header[i]) : ""
            return name.isEmpty ? value : "\(name) : \(value)"
        }.joined(separator: ", ")
    }

    /// Ce que VoiceOver dit de l'en-tête du bloc : « Tableau, 3 colonnes, 5 lignes ».
    public static func spoken(_ rows: [[String]]) -> String {
        let c = columnCount(rows), n = dataRowCount(rows)
        return "Tableau, \(c) \(c > 1 ? "colonnes" : "colonne"), \(n) \(n > 1 ? "lignes" : "ligne")"
    }
}
