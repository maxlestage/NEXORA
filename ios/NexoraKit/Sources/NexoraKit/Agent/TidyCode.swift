import Foundation

// Port de `tidyCode` (Flutter 2.2.77, agent_runner.dart).

/// Une ligne qui finit une instruction, un bloc ou un commentaire.
private let codeEnd = DRegex(#"(^\s*(//|#\[|@).*|[;{}\]),]|\*/)$"#)

/// Une ligne qui commence une déclaration, un commentaire ou ferme un bloc.
private let codeStart = DRegex(
    #"^(//|/\*|#\[|@|\}|\]|\)|(pub(\(\w+\))?\s+)?(fn|mod|use|impl|struct|enum|"#
        + #"const|static|trait|type|let|async|unsafe|extern|macro_rules!)\b|"#
        + #"(import|export|part|library|class|abstract|sealed|final|var|void|late|"#
        + #"mixin|extension|enum|typedef|return|if|for|while|test|group|setUp|"#
        + #"tearDown|expect|assert)\b|[A-Z]\w*(<.*>)?\??\s+\w+\s*[(=;]|"#
        + #"\w+\s*\()"#
)

/// Les lignes vides en trop dans du code Rust ou Dart écrit par l'agent : deux
/// lignes vides de suite, ou une ligne vide à la fin du fichier. En essai réel,
/// l'agent en laissait à chaque ajout de fonction ; `cargo fmt --check` et
/// `dart format` les refusent, et la CI échouait pour rien (un tour de plus,
/// tout l'historique renvoyé). Ramenées à une seule, entre deux lignes de code
/// seulement (jamais dans un long texte entre guillemets). Un fichier d'origine
/// qui en contenait déjà (projet sans formateur) est laissé tel quel.
func tidyCode(_ path: String, _ text: String, before: String? = nil) -> String {
    guard path.hasSuffix(".rs") || path.hasSuffix(".dart") else { return text }
    var out = text
    if before == nil || !DRegex(#"\n[ \t]*\n[ \t]*\n"#).hasMatch(before!) {
        out = DRegex(#"(?:^|(?<=\n))([^\n]*)\n(?:[ \t]*\n){2,}(?=([^\n]*))"#).replaceAllMapped(out) { m in
            let prev = (m.groups[1] ?? "").trimRight()
            let next = (m.groups[2] ?? "").trimLeft()
            let keep = codeEnd.hasMatch(prev) && codeStart.hasMatch(next)
            return keep ? (m.groups[1] ?? "") + "\n\n" : (m.groups[0] ?? "")
        }
    }
    if before == nil || !before!.hasSuffix("\n\n") {
        if let end = DRegex(#"\n(?:[ \t]*\n)+\z"#).firstMatch(out),
           codeEnd.hasMatch(out.sub(0, end.start).trimRight()) {
            out = out.sub(0, end.start) + "\n"
        }
    }
    return out
}
