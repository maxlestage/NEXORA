import Foundation
import Testing
@testable import NexoraKit

/// write_file avec seulement du code nouveau sur un long fichier (port de Flutter
/// 2.2.93) : ajouté à la fin au lieu d'être refusé, le code existant est gardé.
@Suite("Agent : une fonction ajoutée par write_file n'est plus refusée")
@MainActor
struct WriteAdditionTests {
    /// Un vrai fichier Dart assez long (comme llm_parsers.dart).
    static let long: String = {
        var l = ["import 'dart:convert';", ""]
        for i in 0..<40 {
            l += ["/// Lit le champ \(i) d'une réponse.",
                  "String? field\(i)(Map<String, dynamic> j) {",
                  "  final v = j['field\(i)'];",
                  "  return v is String ? v : jsonEncode(v);",
                  "}", ""]
        }
        return l.joined(separator: "\n")
    }()

    /// Ce qu'a écrit le modèle en essai réel : seulement la fonction ajoutée.
    static let onlyNew = """
    String shortModelName(String id) {
      final idx = id.lastIndexOf('/');
      if (idx == -1) return id;
      return id.substring(idx + 1);
    }

    """

    @Test("une fonction nouvelle seule, un module de tests Rust : des ajouts")
    func additions() {
        #expect(AgentRun.pureAddition("lib/parsers.dart", before: Self.long, content: Self.onlyNew))
        let rs = "#[cfg(test)]\nmod tests {\n    use super::*;\n\n    #[test]\n    fn compte() {\n"
            + "        assert_eq!(word_count(\"a b\"), 2);\n    }\n}\n"
        let lib = Self.long.replacingOccurrences(of: "String?", with: "fn").replacingOccurrences(of: "'", with: "\"")
        #expect(AgentRun.pureAddition("src/lib.rs", before: lib, content: rs))
    }

    @Test("import, morceau en retrait, lignes reprises, documentation, contenu long : pas des ajouts")
    func notAdditions() {
        #expect(!AgentRun.pureAddition("lib/parsers.dart", before: Self.long, content: "import 'package:x/x.dart';\n" + Self.onlyNew))
        #expect(!AgentRun.pureAddition("lib/parsers.dart", before: Self.long, content: "  final v = id.trim();\n  return v.split('/').last;\n"))
        #expect(!AgentRun.pureAddition("lib/parsers.dart", before: Self.long,
                                       content: "String? field3(Map<String, dynamic> j) {\n  final v = j['x'];\n  return null;\n}\n"))
        #expect(!AgentRun.pureAddition("README.md", before: String(repeating: "x\n", count: 4000), content: "## Tests\n\ncargo test\n"))
        #expect(!AgentRun.pureAddition("lib/a.dart", before: String(repeating: "x\n", count: 100), content: Self.onlyNew + Self.onlyNew))
    }

    func session(_ write: [String: Any]) async -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM([act(["tool": "write_file", "args": write])])
        llm.whenEmpty = act(["tool": "finish", "args": ["summary": "fin"]])
        let run = makeRun(llm, hub: repoHub(["lib/parsers.dart": Self.long]), repo: "app",
                          task: "Ajoute shortModelName dans lib/parsers.dart", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        return (run, llm)
    }

    @Test("essai réel : seulement la fonction nouvelle sur un long fichier, ajoutée à la fin")
    func appended() async {
        let (run, llm) = await session(["path": "lib/parsers.dart", "content": Self.onlyNew])
        let d = run.draft("lib/parsers.dart") ?? ""
        #expect(d.hasPrefix(Self.long.trimRight()))
        #expect(d.contains("String shortModelName(String id) {"))
        #expect(d.trimRight().hasSuffix("return id.substring(idx + 1);\n}"))
        let r = llm.last(1)
        #expect(r.contains("c'est un AJOUT"))
        #expect(!r.contains("la fin du fichier serait perdue"))
    }

    @Test("avec un import en tête : toujours refusé ; \"force\" remplace vraiment")
    func refusedOrForced() async {
        let (run, llm) = await session(["path": "lib/parsers.dart", "content": "import 'package:x/x.dart';\n" + Self.onlyNew])
        #expect(!run.changes.contains("lib/parsers.dart"))
        #expect(llm.last(1).contains("ERREUR"))
        let (forced, _) = await session(["path": "lib/parsers.dart", "content": Self.onlyNew, "force": true])
        #expect(forced.draft("lib/parsers.dart")?.contains("field3") == false)
        #expect(forced.draft("lib/parsers.dart")?.contains("shortModelName") == true)
    }
}
