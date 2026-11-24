import Testing
@testable import NexoraKit

/// Parité Flutter 2.2.101 : la recherche élargie n'ignore que les espaces, « _ » et « - ».
@MainActor @Suite("Recherche élargie sans faux résultats")
struct SearchSquashTests {
    func act(_ tool: String, _ args: [String: Any]) -> String { NexoraKitTests.act(["tool": tool, "args": args]) }

    func search(_ query: String) async throws -> String {
        let files = [
            "lib/chat.dart": "void send(String text) {}\nfinal note = 'chargés en dollars';\n",
            "lib/version.dart": "int compare_versions(String a, String b) => 0;\n",
        ]
        let run = makeRun(
            ScriptLLM([act("search_code", ["query": query]), act("finish", ["summary": "ok"])]),
            hub: repoHub(files), task: "Cherche", checks: false
        )
        await run.run()
        return try #require(run.history.first { $0.content.hasPrefix("Résultat de search_code") }).content
    }

    @Test("ponctuation et accents comptent")
    func squash() {
        #expect(AgentRun.squashForSearch("send(\"   \"") == "send(\"\"")
        #expect(AgentRun.squashForSearch("compare versions") == "compareversions")
        #expect(AgentRun.squashForSearch("get-user_id") == "getuserid")
        #expect(AgentRun.squashForSearch("chargés") == "chargés")
    }

    @Test("« send(\"   \" » ne rend plus de lignes sans rapport")
    func noNoise() async throws {
        let r = try await search("send(\"   \"")
        #expect(!r.contains("dollars"))
        #expect(!r.contains("ignorant espaces"))
    }

    @Test("« compare versions » retrouve toujours compare_versions")
    func stillFolds() async throws {
        let r = try await search("compare versions")
        #expect(r.contains("compare_versions"))
    }
}
