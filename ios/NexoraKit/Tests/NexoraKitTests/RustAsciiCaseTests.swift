import Foundation
import Testing
@testable import NexoraKit

/// Ce que Pollinations a réellement écrit pour « ajoute slug() : minuscules, accents
/// retirés (é→e, à→a, ç→c…) » : « À » n'est jamais reconnu (port de Flutter 2.2.105).
private let written = """
pub fn slug(titre: &str) -> String {
    fn deaccent(c: char) -> Option<char> {
        match c {
            'á' | 'à' | 'â' => Some('a'),
            'é' | 'è' | 'ê' | 'ë' => Some('e'),
            'ç' => Some('c'),
            _ => None,
        }
    }
    let mut result = String::new();
    for ch in titre.chars() {
        let ch = ch.to_ascii_lowercase();
        let ch = deaccent(ch).unwrap_or(ch);
        if ch.is_ascii_alphanumeric() {
            result.push(ch);
        }
    }
    result
}

"""

@Suite("Agent : to_ascii_lowercase et lettres accentuées (Rust)")
struct RustAsciiCaseTests {
    @Test("le cas de l'essai réel est signalé, avec la correction")
    func realCase() throws {
        let p = try #require(rustAsciiCaseProblem(written))
        #expect(p.hasPrefix("ligne 12 (« let ch = ch.to_ascii_lowercase(); »)"))
        #expect(p.contains("« Á » reste « Á »"))
        #expect(p.contains("(ligne 4)"))
        #expect(p.contains("to_lowercase()"))
        let hint = AgentRun.rustAsciiCaseHint("site/src/contenu.rs", written)
        #expect(hint?.contains("erreur de logique dans site/src/contenu.rs") == true)
        #expect(AgentRun.rustAsciiCaseHint("site/src/contenu.dart", written) == nil)
    }

    @Test("version Unicode ou majuscules déjà écrites : rien à dire")
    func unicodeOrUppercase() {
        #expect(rustAsciiCaseProblem(written.replacingOccurrences(
            of: "for ch in titre.chars() {\n        let ch = ch.to_ascii_lowercase();",
            with: "for ch in titre.chars().flat_map(char::to_lowercase) {")) == nil)
        #expect(rustAsciiCaseProblem(written.replacingOccurrences(
            of: ".to_ascii_lowercase()", with: ".to_lowercase().next().unwrap()")) == nil)
        let both = """
        fn f(c: char) -> char {
            match c.to_ascii_lowercase() {
                'é' | 'É' => 'e',
                c => c,
            }
        }

        """
        #expect(rustAsciiCaseProblem(both) == nil)
        let site = """
        pub fn slug(nom: &str) -> String {
            for c in nom.trim().chars().flat_map(char::to_lowercase) {
                let c = match c {
                    'à' | 'â' => 'a',
                    c => c.to_ascii_lowercase(),
                };
            }
        }

        """
        #expect(rustAsciiCaseProblem(site) == nil)
        #expect(rustAsciiCaseProblem(site.replacingOccurrences(
            of: ".flat_map(char::to_lowercase)", with: "")) != nil)
    }

    @Test("sans lettre accentuée, ou dans un commentaire ou une chaîne : rien")
    func ignored() {
        for code in [
            "fn f(s: &str) -> String { s.to_ascii_lowercase() }\n",
            "fn f(c: char) -> char {\n    // 'é' est géré ailleurs\n    c.to_ascii_lowercase()\n}\n",
            "fn f(s: &str) -> String {\n    let t = \"pas 'é' ici\";\n    s.to_ascii_lowercase()\n}\n",
            // ß n'a pas de majuscule d'une lettre.
            "fn f(c: char) -> bool { c.to_ascii_lowercase() == 'ß' }\n",
        ] {
            #expect(rustAsciiCaseProblem(code) == nil, "\(code)")
        }
    }

    @Test("les lignes du fichier d'origine ne sont jamais visées")
    func originalLines() {
        #expect(rustAsciiCaseProblem(written, old: Set(written.components(separatedBy: "\n"))) == nil)
        #expect(AgentRun.rustAsciiCaseHint("site/src/lib.rs", written, before: written) == nil)
    }
}
