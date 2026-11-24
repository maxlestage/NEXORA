import Foundation
import Testing
@testable import NexoraKit

/// Lignes Dart trop longues pour `dart format` (port de Flutter 2.2.81) : le modèle
/// est prévenu dès l'écriture quand la CI du dépôt vérifie le format.
@Suite("Agent : lignes trop longues pour dart format")
@MainActor
struct DartFormatHintTests {
    // La ligne réellement écrite en essai réel pour « ajoute un getter totalWords » :
    // 86 caractères, refusée par dart format en CI.
    static let long = #"      final words = m.content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;"#

    static let written = "class Conversation {\n"
        + "  final List<String> messages = [];\n"
        + "  int get totalWords {\n"
        + "    return messages.fold(0, (sum, m) {\n"
        + long + "\n"
        + "      return sum + words;\n"
        + "    });\n"
        + "  }\n"
        + "}\n"

    static let ci = "jobs:\n  app:\n    steps:\n"
        + "      - run: dart format --output=none --set-exit-if-changed lib test\n"

    @Test("essai réel : la ligne de 86 caractères est signalée")
    func realCase() throws {
        let hint = try #require(AgentRun.dartFormatHint("app/lib/chat.dart", Self.written))
        #expect(hint.contains("ligne 5 (86 caractères)"))
        #expect(hint.contains("final words = m.content.split"))
        #expect(hint.contains("dart format"))
    }

    @Test("ce que dart format laisse long n'est pas signalé")
    func leftLong() {
        let text = [
            "import 'package:nexora/un/chemin/tres/long/pour/depasser/la/limite/de/quatre/vingts.dart';",
            "  // Un commentaire très long qui dépasse largement les quatre-vingts caractères permis.",
            #"    hintText: 'Ex. : ajoute un mode sombre à l\'app et mets à jour le README',"#,
            "          ? 'Pull request ouverte : CI puis fusion en cours, merci de patienter'",
            "  final a = f(1); // un commentaire en fin de ligne qui est vraiment très très long",
            "  const t = '''",
            "Un texte sur plusieurs lignes, long, très long, bien plus long que quatre-vingts.",
            "''';",
            "// dart format off",
            "  final List<int> valeurs = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];",
            "// dart format on",
        ].joined(separator: "\n")
        #expect(AgentRun.dartFormatHint("lib/a.dart", text) == nil)
    }

    @Test("seules les lignes de l'agent comptent, à la largeur du projet")
    func onlyAgentLines() {
        #expect(AgentRun.dartFormatHint("app/lib/chat.dart", Self.written, before: Self.written) == nil)
        #expect(AgentRun.dartFormatHint("app/lib/chat.dart", Self.written, width: 100) == nil)
        #expect(AgentRun.dartFormatHint("src/main.rs", Self.written) == nil)
    }

    func session(_ files: [String: String], writes: Int = 1, content: String = written) async -> ScriptLLM {
        let w = act(["tool": "write_file", "args": ["path": "app/lib/chat.dart", "content": content]])
        let llm = ScriptLLM(Array(repeating: w, count: writes))
        llm.whenEmpty = act(["tool": "finish", "args": ["summary": "fin"]])
        var all = files
        all["app/pubspec.yaml"] = "name: app\n"
        let run = makeRun(llm, hub: repoHub(all), repo: "NEXORA", branch: "master",
                          task: "Ajoute un getter totalWords à Conversation", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        return llm
    }

    @Test("CI avec dart format : prévenu dès l'écriture, une seule fois")
    func inSession() async {
        let llm = await session([".github/workflows/ci.yml": Self.ci], writes: 2)
        #expect(llm.last(1).contains("enregistré en brouillon"))
        #expect(llm.last(1).contains("ligne 5 (86 caractères)"))
        // La même écriture refaite ne répète pas l'alerte.
        let all = llm.messages(2).compactMap { $0["content"] }.joined()
        #expect(all.components(separatedBy: "caractères au plus par ligne").count == 2)
    }

    @Test("pas de vérification du format en CI, ou largeur du projet respectée : rien n'est dit")
    func noCheck() async {
        let plain = await session([:])
        #expect(plain.last(1).contains("enregistré en brouillon"))
        #expect(!plain.last(1).contains("caractères au plus par ligne"))
        let wide = await session([".github/workflows/ci.yml": Self.ci,
                                  "app/analysis_options.yaml": "formatter:\n  page_width: 100\n"])
        #expect(!wide.last(1).contains("caractères au plus par ligne"))
    }

    // Indentation refusée par dart format (port de Flutter 2.2.99) : le « RegExp( »
    // réellement écrit pour « fais renvoyer le titre d'une page d'erreur HTML ».
    static let badIndent = "String errorFromBody(String body) {\n"
        + "  final t = body.trim();\n"
        + "  if (t.startsWith('<html')) {\n"
        + "    final titleMatch = RegExp(\n"
        + "    r'<title>(.*?)</title>',\n"
        + "    caseSensitive: false,\n"
        + "    dotAll: true,\n"
        + "  ).firstMatch(t);\n"
        + "    if (titleMatch != null) return titleMatch.group(1)!;\n"
        + "  }\n"
        + "  return t;\n"
        + "}\n"

    static let goodIndent = "String errorFromBody(String body) {\n"
        + "  final t = body.trim();\n"
        + "  if (t.startsWith('<html')) {\n"
        + "    final titleMatch = RegExp(\n"
        + "      r'<title>(.*?)</title>',\n"
        + "      caseSensitive: false,\n"
        + "      dotAll: true,\n"
        + "    ).firstMatch(t);\n"
        + "    if (titleMatch != null) return titleMatch.group(1)!;\n"
        + "  }\n"
        + "  return t;\n"
        + "}\n"

    @Test("essai réel : arguments et fermeture mal indentés")
    func realIndent() {
        let found = dartIndentProblems(Self.badIndent)
        #expect(found.count == 2)
        #expect(found.first?.hasPrefix("ligne 5 : 4 espaces") == true)
        #expect(found.first?.contains("il en faut 6") == true)
        #expect(found.last?.hasPrefix("ligne 8 : « ) »") == true)
        #expect(found.last?.contains("4 espaces (et non 2)") == true)
        #expect(dartIndentProblems(Self.goodIndent).isEmpty)
    }

    @Test("ce que dart format écrit ainsi n'est pas signalé")
    func formatterIndent() {
        let code = "void f(\n"
            + "  String q, {\n"
            + "  required int n,\n"
            + "}) {\n"
            + "  final a = ok\n"
            + "      ? g(\n"
            + "          1,\n"
            + "        )\n"
            + "      : 2;\n"
            + "  final b = list\n"
            + "      .where(\n"
            + "        (x) => x > 1,\n"
            + "      )\n"
            + "      .toList();\n"
            + "  test('un long titre '\n"
            + "      'sur deux lignes', (\n"
            + "    WidgetTester tester,\n"
            + "  ) async {});\n"
            + "  if ( // commentaire\n"
            + "  a) {}\n"
            + "  final c = h(\n"
            + "    '\'\'\n"
            + "texte\n"
            + "'\'\',\n"
            + "  );\n"
            + "  final d = [\n"
            + "    1,\n"
            + "  ];\n"
            + "}\n"
        #expect(dartIndentProblems(code).isEmpty)
    }

    @Test("les lignes du fichier d'origine ne sont pas visées")
    func indentOnlyAgentLines() {
        let old = Set(Self.badIndent.components(separatedBy: "\n"))
        #expect(dartIndentProblems(Self.badIndent, old: old).isEmpty)
        #expect(AgentRun.dartIndentHint("app/lib/a.dart", Self.badIndent, before: Self.badIndent) == nil)
        #expect(AgentRun.dartIndentHint("src/main.rs", Self.badIndent) == nil)
    }

    @Test("CI avec dart format : indentation signalée dès l'écriture ; sinon rien")
    func indentInSession() async {
        let llm = await session([".github/workflows/ci.yml": Self.ci], content: Self.badIndent)
        #expect(llm.last(1).contains("enregistré en brouillon"))
        #expect(llm.last(1).contains("mal indenté"))
        #expect(llm.last(1).contains("ligne 8 : « ) »"))
        let plain = await session([:], content: Self.badIndent)
        #expect(plain.last(1).contains("enregistré en brouillon"))
        #expect(!plain.last(1).contains("mal indenté"))
    }
}
