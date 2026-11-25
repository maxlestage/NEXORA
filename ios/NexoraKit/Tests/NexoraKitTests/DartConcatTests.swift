import Foundation
import Testing
@testable import NexoraKit

/// Textes collés avec « + » que `flutter analyze` refuse (port de Flutter 2.2.109) :
/// le modèle est prévenu dès l'écriture quand la CI du dépôt passe l'analyse.
@Suite("Agent : textes collés avec « + »")
@MainActor
struct DartConcatTests {
    // Le test réellement écrit pour « coupe les titres rapides à 40 caractères…
    // Ajoute des tests unitaires » : lignes 5 et 6 refusées par flutter analyze.
    static let written = "import 'package:flutter_test/flutter_test.dart';\n"
        + "\n"
        + "void main() {\n"
        + "  test('coupe', () {\n"
        + "    final title = String.fromCharCodes(List.filled(39, 97)) + ' b';\n"
        + "    expect(f(title), String.fromCharCodes(List.filled(39, 97)) + '…');\n"
        + "  });\n"
        + "}\n"

    static let ci = "jobs:\n  app:\n    steps:\n      - run: flutter analyze\n"
    static let options = "include: package:flutter_lints/flutter.yaml\n"

    @Test("essai réel : les deux lignes du test sont signalées")
    func realCase() {
        #expect(dartConcatProblems(Self.written) == [
            "ligne 5 : final title = String.fromCharCodes(List.filled(39, 97)) + ' b';",
            "ligne 6 : expect(f(title), String.fromCharCodes(List.filled(39, 97)) + '…');",
        ])
    }

    @Test("comme l'analyseur : ce qu'il refuse est signalé")
    func refused() {
        for code in [
            "final t = x + 'c';",
            "final t = 'a' 'b' + x;",
            "final t = f(x) +\n    'y';",
            "final t = '''a''' + x;",
            "final t = 'a'.trim() + 'b';",
            "final t = x + '$x' + x;",
            "final t = '${x}a' + x;",
        ] {
            #expect(dartConcatProblems(code).count == 1, "\(code)")
        }
    }

    @Test("ce que l'analyseur accepte n'est pas signalé")
    func accepted() {
        for code in [
            "final t = 'a' + 'b';",
            "final t = 'a' * 30 + ' b';",
            "final t = '  ' * --depth + '=> x';",
            "final t = x + 'b'.trim();",
            #"final t = x + r'\d';"#,
            "s += 'x';",
            "final n = a + b;",
            "final t = '${a + b}';",
            "// x + 'a'",
            #"final t = 'x + \'a\'';"#,
        ] {
            #expect(dartConcatProblems(code).isEmpty, "\(code)")
        }
    }

    @Test("seules les lignes de l'agent comptent")
    func onlyAgentLines() throws {
        #expect(AgentRun.dartConcatHint("app/test/t.dart", Self.written, before: Self.written) == nil)
        let hint = try #require(AgentRun.dartConcatHint("app/test/t.dart", Self.written))
        #expect(hint.contains("flutter analyze"))
        #expect(hint.contains("ligne 5"))
        #expect(AgentRun.dartConcatHint("src/main.rs", Self.written) == nil)
    }

    @Test("quelle CI refuse les remarques de l'analyseur")
    func analyzeInfos() {
        #expect(AgentRun.dartAnalyzeRefusesInfos("- run: flutter analyze"))
        #expect(AgentRun.dartAnalyzeRefusesInfos("- run: dart analyze --fatal-infos"))
        #expect(!AgentRun.dartAnalyzeRefusesInfos("- run: dart analyze"))
        #expect(!AgentRun.dartAnalyzeRefusesInfos("- run: flutter analyze --no-fatal-infos"))
    }

    func session(_ files: [String: String]) async -> ScriptLLM {
        let w = act(["tool": "write_file", "args": ["path": "app/test/title_test.dart", "content": Self.written]])
        let llm = ScriptLLM([w])
        llm.whenEmpty = act(["tool": "finish", "args": ["summary": "fin"]])
        var all = files
        all["app/pubspec.yaml"] = "name: app\n"
        let run = makeRun(llm, hub: repoHub(all), repo: "NEXORA", branch: "master",
                          task: "Coupe les titres rapides à 40 caractères, avec des tests unitaires",
                          checks: false)
        run.specs.append("déjà compris")
        await run.run()
        return llm
    }

    @Test("dans une session : l'agent est prévenu dès l'écriture")
    func inSession() async {
        let llm = await session([".github/workflows/ci.yml": Self.ci, "app/analysis_options.yaml": Self.options])
        #expect(llm.last(1).contains("enregistré en brouillon"))
        #expect(llm.last(1).contains("prefer_interpolation_to_compose_strings"))
        #expect(llm.last(1).contains("ligne 5"))
    }

    @Test("sans flutter analyze en CI, ou règle coupée : rien")
    func noCheck() async {
        let plain = await session(["app/analysis_options.yaml": Self.options])
        #expect(plain.last(1).contains("enregistré en brouillon"))
        #expect(!plain.last(1).contains("prefer_interpolation"))
        let off = await session([
            ".github/workflows/ci.yml": Self.ci,
            "app/analysis_options.yaml": Self.options
                + "linter:\n  rules:\n    prefer_interpolation_to_compose_strings: false\n",
        ])
        #expect(!off.last(1).contains("prefer_interpolation"))
    }
}
