import Foundation

// Où commence le code orphelin d'une accolade fermante de trop (port de
// brace_hint.dart, Flutter 2.2.107).
//
// Essai réel : pour ajouter un test, le modèle collait « } » puis sa nouvelle
// fonction au milieu d'une fonction existante. La fin de celle-ci (des lignes
// indentées comme dans un corps de fonction) se retrouvait hors de toute
// fonction, et l'accolade de trop n'apparaissait qu'à la fin du fichier :
// l'avertissement montrait la dernière ligne, pas l'endroit cassé.

/// Les débuts de ligne qui peuvent légitimement suivre une « } » seule avec
/// plus d'indentation (suite d'une expression, commentaire, fermeture).
let braceContinuations = [
    "}", ")", "]", ".", "?", ":", "&&", "||", "+", "-", "*", "/", "=", ",",
    "else", "catch", "on ", "finally", "where", "as ",
]

private func braceTrimLeft(_ s: String) -> Substring {
    s.drop { $0.isWhitespace }
}

private func braceIndent(_ s: String) -> Int {
    s.utf16.count - braceTrimLeft(s).utf16.count
}

/// La première ligne (numéro à partir de 1) qui suit une « } » seule sur sa
/// ligne (parmi `closers`, les lignes où une vraie accolade de code se ferme)
/// en étant PLUS indentée qu'elle, avant la ligne `before` : c'est là que du
/// code s'est retrouvé hors de son bloc. Rend (ligne de la « } », ligne
/// orpheline), ou `nil`.
public func orphanAfterClose(_ lines: [String], _ closers: [Int], _ before: Int) -> (close: Int, orphan: Int)? {
    for c in Set(closers).sorted() {
        if c >= before || c < 1 || c > lines.count { continue }
        let closing = lines[c - 1]
        if closing.trimmingCharacters(in: .whitespacesAndNewlines) != "}" { continue }
        var next = c + 1
        while next <= lines.count && lines[next - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next += 1
        }
        if next > lines.count || next >= before { continue }
        let text = lines[next - 1]
        let t = braceTrimLeft(text)
        if braceContinuations.contains(where: { t.hasPrefix($0) }) { continue }
        if braceIndent(text) > braceIndent(closing) { return (c, next) }
    }
    return nil
}

/// La phrase à ajouter à l'erreur « accolade en trop » quand le code orphelin
/// est trouvé, ou `nil`.
public func orphanNote(_ lines: [String], _ closers: [Int], _ before: Int) -> String? {
    guard let found = orphanAfterClose(lines, closers, before) else { return nil }
    var t = lines[found.orphan - 1].trimmingCharacters(in: .whitespacesAndNewlines)
    let u = Array(t.utf16)
    if u.count > 120 { t = String(utf16CodeUnits: Array(u[0..<120]), count: 120) + "…" }
    return "le décalage commence sans doute ligne \(found.orphan) (« \(t) ») : elle est "
        + "plus indentée que la « } » de la ligne \(found.close) juste avant, qui a donc "
        + "fermé son bloc trop tôt (du code inséré au milieu d'une fonction, qui "
        + "en a laissé la fin dehors). Remets ces lignes dans leur fonction, ou "
        + "retire cette « } »"
}
