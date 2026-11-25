import Testing
@testable import NexoraKit

/// Parité Flutter 2.2.110 : un nom de code retrouvé seulement en mots séparés est
/// annoncé comme absent ; find_in_file retrouve un texte exact lu à tort comme une
/// expression régulière.
@MainActor @Suite("Recherche : nom en mots séparés, texte exact")
struct SearchSplitNameTests {
    func act(_ tool: String, _ args: [String: Any]) -> String { NexoraKitTests.act(["tool": tool, "args": args]) }

    let files = [
        "lib/api.dart": "class Api {\n  String get user => _user;\n  String get_token() => '';\n}\n",
        "lib/http.dart": "void check(res) {\n  if (res.statusCode >= 400) throw 'x';\n}\n",
    ]

    func result(_ tool: String, _ args: [String: Any]) async throws -> String {
        let run = makeRun(
            ScriptLLM([act(tool, args), act("finish", ["summary": "ok"])]),
            hub: repoHub(files), task: "Cherche", checks: false
        )
        await run.run()
        return try #require(run.history.first { $0.content.hasPrefix("Résultat de \(tool)") }).content
    }

    @Test("nom de code")
    func codeName() {
        #expect(AgentRun.codeName("getUser"))
        #expect(AgentRun.codeName("get_user"))
        #expect(!AgentRun.codeName("user"))
        #expect(!AgentRun.codeName("Api"))
        #expect(!AgentRun.codeName("get user"))
    }

    @Test("« getUser » trouvé seulement dans « get user » : annoncé absent")
    func splitAbsent() async throws {
        let r = try await result("search_code", ["query": "getUser"])
        #expect(r.contains("il n'existe pas"))
        #expect(r.contains("String get user"))
        #expect(!r.contains("ligne(s) contiennent « getUser »"))
    }

    @Test("« getToken » trouve toujours get_token")
    func underscoreKept() async throws {
        let r = try await result("search_code", ["query": "getToken"])
        #expect(r.contains("ligne(s) contiennent « getToken »"))
        #expect(!r.contains("il n'existe pas"))
    }

    @Test("find_in_file retrouve un texte exact avec parenthèses")
    func plainFallback() async throws {
        let r = try await result("find_in_file", ["path": "lib/http.dart", "pattern": "if (res.statusCode >= 400)"])
        #expect(r.contains(">2:"))
        #expect(!r.contains("Aucune ligne"))
    }
}
