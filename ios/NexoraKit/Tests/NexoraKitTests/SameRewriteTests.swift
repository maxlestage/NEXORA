import Foundation
import Testing
@testable import NexoraKit

/// write_file qui réécrit un fichier à l'identique (port de Flutter 2.2.100) : l'agent
/// apprend que c'est déjà fait au lieu de lire « OK, enregistré » et de recommencer.
@Suite("Agent : un fichier réécrit à l'identique n'est plus un changement")
@MainActor
struct SameRewriteTests {
    static let test = """
    import 'package:test/test.dart';

    void main() {
      test('compte', () => expect(1 + 1, 2));
    }

    """

    static let repo = "def a():\n    return 1\n"

    func session(_ writes: [[String: Any]], between: Bool = false) async -> (AgentRun, ScriptLLM) {
        var steps = writes.map { act(["tool": "write_file", "args": $0]) }
        // Une autre action entre deux écritures (une répétition immédiate a déjà sa note).
        if between, steps.count > 1 { steps.insert(act(["tool": "read_file", "args": ["path": "lib/a.py"]]), at: 1) }
        let llm = ScriptLLM(steps)
        llm.whenEmpty = act(["tool": "finish", "args": ["summary": "fin"]])
        let run = makeRun(llm, hub: repoHub(["lib/a.py": Self.repo]), repo: "app",
                          task: "Ajoute un test", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        return (run, llm)
    }

    @Test("fins de ligne ignorées, le moindre changement compte")
    func compare() {
        #expect(AgentRun.sameText("a\nb\n", "a\nb"))
        #expect(AgentRun.sameText("a\r\nb\r\n\r\n", "a\nb\n"))
        #expect(!AgentRun.sameText("a\nb\n", "a\nb \n"))
        #expect(!AgentRun.sameText("a\n", nil))
    }

    @Test("le même brouillon réécrit : « Déjà fait », le brouillon reste")
    func twice() async {
        let (run, llm) = await session([
            ["path": "test/a_test.dart", "content": Self.test],
            ["path": "test/a_test.dart", "content": Self.test],
        ], between: true)
        #expect(llm.last(1).contains("enregistré en brouillon"))
        let r = llm.last(3)
        #expect(r.contains("Déjà fait : test/a_test.dart"))
        #expect(r.contains("appelle finish"))
        #expect(run.draft("test/a_test.dart") == Self.test)
    }

    @Test("identique au dépôt : aucun brouillon vide ; un vrai changement est écrit")
    func sameAsRepo() async {
        let (run, llm) = await session([["path": "lib/a.py", "content": "def a():\r\n    return 1"]])
        #expect(llm.last(1).contains("Rien n'a changé : ce contenu est identique à lib/a.py"))
        #expect(!run.changes.contains("lib/a.py"))
        let (edited, l2) = await session([["path": "lib/a.py", "content": "def a():\n    return 2\n"]])
        #expect(l2.last(1).contains("enregistré en brouillon"))
        #expect(edited.draft("lib/a.py") == "def a():\n    return 2\n")
    }
}
