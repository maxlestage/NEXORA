import Testing
@testable import NexoraKit

/// Lignes vides en trop dans le Rust et le Dart écrits par l'agent (port de
/// Flutter 2.2.77, tidy_code_test.dart).
@Suite("Agent : lignes vides en trop dans le code")
struct TidyCodeTests {
    @Test("Rust : deux lignes vides ramenées à une, fin de fichier propre")
    func rust() {
        let before = "pub const A: u8 = 1;\n\n#[cfg(test)]\nmod t {}\n"
        let agent = "pub const A: u8 = 1;\n\n\n/// Compte.\npub fn n() -> usize {\n"
            + "    0\n}\n\n\n#[cfg(test)]\nmod t {}\n\n"
        #expect(tidyCode("site/src/contenu.rs", agent, before: before)
            == "pub const A: u8 = 1;\n\n/// Compte.\npub fn n() -> usize {\n"
            + "    0\n}\n\n#[cfg(test)]\nmod t {}\n")
    }

    @Test("Dart : entre deux fonctions et dans un test")
    func dart() {
        let agent = "import 'a.dart';\n\n\n\nString f() => '';\n  \n\nvoid main() {\n"
            + "  test('x', () {});\n}\n\n\n"
        #expect(tidyCode("app/lib/utils/texte.dart", agent)
            == "import 'a.dart';\n\nString f() => '';\n\nvoid main() {\n"
            + "  test('x', () {});\n}\n")
    }

    @Test("un long texte entre guillemets n'est pas touché")
    func strings() {
        let html = "const PAGE: &str = r#\"<p>Un</p>\n\n\n<p>Deux</p>\n\"#;\n"
            + "const T: &str = \"fin.\n\n\nsuite\";\n"
        #expect(tidyCode("site/src/pages.rs", html) == html)
    }

    @Test("un fichier d'origine déjà aéré est laissé tel quel")
    func looseOrigin() {
        let before = "fn a() {}\n\n\nfn b() {}\n\n"
        let agent = "fn a() {}\n\n\nfn b() {}\n\n\nfn c() {}\n\n"
        #expect(tidyCode("src/lib.rs", agent, before: before) == agent)
    }

    @Test("les autres fichiers ne changent pas")
    func others() {
        let md = "# Titre\n\n\n- point\n\n"
        #expect(tidyCode("README.md", md) == md)
        #expect(tidyCode("ci.yml", "a: 1\n\n\nb: 2\n") == "a: 1\n\n\nb: 2\n")
    }

    @Test("appliqué aux brouillons de l'agent (edit_file)")
    func withEdit() {
        let src = "pub const A: u8 = 1;\n\n#[cfg(test)]\nmod t {}\n"
        let out = applyEdit(src, "pub const A: u8 = 1;\n", "pub const A: u8 = 1;\n\n\npub fn n() {}\n").0
        #expect(out != nil)
        #expect(tidyCode("src/lib.rs", out ?? "", before: src)
            == "pub const A: u8 = 1;\n\npub fn n() {}\n\n#[cfg(test)]\nmod t {}\n")
    }

    // Remarques de flutter analyze dans le Dart de l'agent (port de Flutter 2.2.80).

    @Test("Dart : accolades inutiles et doc en tête de fichier (essai réel)")
    func dartLintsRealRun() {
        let agent = "/// Utility functions for duration formatting.\n\n"
            + "/// Formats a [Duration].\n"
            + "String formatDuree(Duration d) {\n"
            + "  final hours = d.inHours;\n"
            + "  final minutesStr = '${d.inMinutes % 60}'.padLeft(2, '0');\n"
            + "  return '${hours} h ${minutesStr} min';\n"
            + "}\n"
        #expect(tidyCode("app/lib/utils/duration_utils.dart", agent)
            == "// Utility functions for duration formatting.\n\n"
            + "/// Formats a [Duration].\n"
            + "String formatDuree(Duration d) {\n"
            + "  final hours = d.inHours;\n"
            + "  final minutesStr = '${d.inMinutes % 60}'.padLeft(2, '0');\n"
            + "  return '$hours h $minutesStr min';\n"
            + "}\n")
    }

    @Test("Dart : les accolades utiles restent")
    func dartLintsUsefulBraces() {
        let agent = "final a = '${n}s ${n}_x ${o.p} ${f()} ${n}$m';\n"
            + "final b = '\\${n} ';\n"
        #expect(tidyCode("lib/a.dart", agent) == agent)
    }

    @Test("Dart : jamais dans une chaîne brute ni hors d'un texte")
    func dartLintsRawAndCode() {
        let agent = "final a = r'${n} ';\n"
            + "final b = r\"\"\"\n${n} \n\"\"\";\n"
            + "// voir ${n} ici\n"
            + "final c = '''\n${n} ok''';\n"
        #expect(tidyCode("lib/a.dart", agent)
            == "final a = r'${n} ';\n"
            + "final b = r\"\"\"\n${n} \n\"\"\";\n"
            + "// voir ${n} ici\n"
            + "final c = '''\n$n ok''';\n")
    }

    @Test("Dart : interpolations imbriquées")
    func dartLintsNested() {
        let agent = "final s = '${ok ? '${a} !' : \"${b}.\"} ${c}';\n"
        #expect(tidyCode("lib/a.dart", agent) == "final s = '${ok ? '$a !' : \"$b.\"} $c';\n")
    }

    @Test("Dart : les lignes du fichier d'origine restent telles quelles")
    func dartLintsKeepOriginal() {
        let before = "/// Outils.\n\nfinal a = '${x} ';\n"
        let agent = "/// Outils.\n\nfinal a = '${x} ';\nfinal b = '${y} ';\n"
        #expect(tidyCode("lib/a.dart", agent, before: before)
            == "/// Outils.\n\nfinal a = '${x} ';\nfinal b = '$y ';\n")
    }

    @Test("Dart : une doc rattachée à quelque chose reste une doc")
    func dartLintsAttachedDoc() {
        let lib = "/// La bibliothèque.\nlibrary;\n\nimport 'a.dart';\n"
        let fn = "/// Compte.\nint n() => 0;\n"
        #expect(tidyCode("lib/a.dart", lib) == lib)
        #expect(tidyCode("lib/b.dart", fn) == fn)
        #expect(tidyCode("lib/c.dart", "/// Outils.\nimport 'a.dart';\n") == "// Outils.\nimport 'a.dart';\n")
    }

    @Test("Dart : le Rust n'est pas concerné")
    func dartLintsNotRust() {
        let rust = "/// Doc.\n\nfn f() { format!(\"${x}\"); }\n"
        #expect(tidyCode("src/lib.rs", rust) == rust)
    }

    @Test("Dart : la barre oblique inutile devant un guillemet de l'autre sorte est retirée (essai réel)")
    func dartLintsUselessQuoteEscapes() {
        let agent = #"final body = '''{\"message\": \"Invalid API key\"}''';"# + "\n"
            + #"final b = "l\'API";"# + "\n" + #"final c = '\"x\"';"# + "\n"
        #expect(tidyCode("test/a_test.dart", agent)
            == #"final body = '''{"message": "Invalid API key"}''';"# + "\n"
            + #"final b = "l'API";"# + "\n" + #"final c = '"x"';"# + "\n")
    }

    @Test("Dart : barres utiles, chaînes brutes, commentaires et lignes d'origine intacts")
    func dartLintsUsefulEscapesKept() {
        let kept = #"final a = 'c\'est';"# + "\n" + #"final b = "un \"mot\"";"# + "\n"
            + #"final c = r'\"';"# + "\n" + #"// '\"' en commentaire"# + "\n"
            + #"final d = '\\"';"# + "\n"
        #expect(tidyCode("lib/a.dart", kept) == kept)
        let before = #"final a = '\"x\"';"# + "\n"
        let agent = before + #"final b = '\"y\"';"# + "\n"
        #expect(tidyCode("lib/a.dart", agent, before: before)
            == before + #"final b = '"y"';"# + "\n")
        // Mêlée à une interpolation inutile sur la même ligne.
        #expect(tidyCode("lib/b.dart", #"final e = '\"${x}\" ok';"# + "\n")
            == #"final e = '"$x" ok';"# + "\n")
    }
}
