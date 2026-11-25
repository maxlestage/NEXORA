import Foundation
import Testing
@testable import NexoraKit

/// Un brouillon cassé rappelé dans les relances (port de Flutter 2.2.106) : point
/// d'étape et recherches en rond remettent l'avertissement, oublié sinon quand
/// l'historique est raccourci.
@Suite("Agent : un brouillon cassé n'est plus oublié en route")
@MainActor
struct BrokenReminderTests {
    /// Un test coupé en deux : une « } » de trop (essai réel).
    static let broken = """
    fn version() -> String {
        "1".into()
    }

    #[cfg(test)]
    mod tests {
        #[test]
        fn a() {
            let x = 1;
        }
            assert_eq!(x, 1);
        }
    }

    """

    static let valid = "fn version() -> String {\n    \"1\".into()\n}\n"

    func search(_ q: String) -> String { act(["tool": "search_code", "args": ["query": q, "path": "src"]]) }

    func session(_ replies: [String], maxSteps: Int = 24) async -> ScriptLLM {
        let llm = ScriptLLM(replies)
        let count = replies.count
        // Ensuite, deux recherches refaites tour à tour (jamais deux fois de suite la même).
        llm.dynamic = { n, _, _ in
            n < count ? nil : .text(act(["tool": "search_code",
                                         "args": ["query": n % 2 == 1 ? "Response" : "body", "path": "src"]]))
        }
        let run = makeRun(llm, hub: repoHub(["src/main.rs": "fn main() {}\n"]), task: "Ajoute une route /version",
                          checks: false, maxSteps: maxSteps)
        run.specs.append("déjà compris")
        await run.run()
        return llm
    }

    func prompts(_ llm: ScriptLLM) -> [String] { (0..<llm.count).map { llm.last($0) } }

    @Test("rappelé quand l'agent tourne en rond")
    func circling() async {
        let llm = await session([act(["tool": "write_file", "args": ["path": "src/lib.rs", "content": Self.broken]])])
        let all = prompts(llm)
        #expect(all[1].contains("ne compilera pas"))
        #expect(!all[1].contains("AVANT TOUT"))
        let circling = all.filter { $0.contains("tu tournes en rond") }
        #expect(!circling.isEmpty)
        for p in circling {
            #expect(p.contains("AVANT TOUT : tes brouillons ne compilent plus"))
            #expect(p.contains("src/lib.rs ne compilera pas"))
        }
    }

    @Test("rappelé au point d'étape")
    func checkpoint() async {
        let llm = await session([
            act(["tool": "write_file", "args": ["path": "src/lib.rs", "content": Self.broken]]),
            search("a"), search("b"),
        ], maxSteps: 3)
        let point = prompts(llm).first { $0.contains("étapes sans terminer") }
        #expect(point?.contains("AVANT TOUT : tes brouillons ne compilent plus") == true)
        #expect(point?.contains("src/lib.rs ne compilera pas") == true)
    }

    @Test("rien n'est rappelé quand le code compile")
    func valid() async {
        let llm = await session([
            act(["tool": "write_file", "args": ["path": "src/lib.rs", "content": Self.valid]]),
            search("a"), search("b"),
        ], maxSteps: 3)
        let all = prompts(llm)
        #expect(all.contains { $0.contains("étapes sans terminer") })
        #expect(!all.contains { $0.contains("AVANT TOUT") })
    }
}
