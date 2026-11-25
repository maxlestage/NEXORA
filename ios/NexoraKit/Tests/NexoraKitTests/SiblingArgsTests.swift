import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.108 (app/test/sibling_args_test.dart).
@Suite struct SiblingArgsTests {
    @Test func argumentsACoteDeToolRepris() {
        let read = parseToolCalls("```json\n{\"tool\": \"read_file\", \"path\": \"app/lib/a.dart\"}\n```")
        #expect(read.count == 1)
        #expect(read.first?.tool == "read_file")
        #expect(read.first?.args["path"] as? String == "app/lib/a.dart")

        let write = parseToolCalls(
            "```json\n{\"actions\":[{\"tool\":\"repo_browser.write_file\","
                + "\"args\":{\"path\":\"app/test/a_test.dart\"},\"content\":\"void main() {}\\n\"}]}\n```")
        #expect(write.count == 1)
        #expect(write.first?.args["path"] as? String == "app/test/a_test.dart")
        #expect(write.first?.args["content"] as? String == "void main() {}\n")
    }

    @Test func argsPrimeEtNomDeLOutilPasUnArgument() {
        let c = parseToolCalls(
            "```json\n{\"tool\": \"write_file\", \"args\": {\"path\": \"a.dart\", "
                + "\"content\": \"bon\"}, \"content\": \"autre\", \"thought\": \"t\"}\n```")
        #expect(c.count == 1)
        #expect(c.first?.args["content"] as? String == "bon")
        #expect(c.first?.args["thought"] == nil)

        let n = parseToolCalls("```json\n{\"name\": \"read_file\", \"arguments\": {\"path\": \"b.dart\"}}\n```")
        #expect(n.count == 1)
        #expect(n.first?.args.count == 1)
        #expect(n.first?.args["path"] as? String == "b.dart")

        let skill = parseToolCalls("```json\n{\"tool\": \"use_skill\", \"name\": \"relecture\"}\n```")
        #expect(skill.first?.args["name"] as? String == "relecture")
    }

    @Test func jsonDUneAutreActionPasPrisPourLeContenu() {
        let calls = parseToolCalls(
            "```json\n{\"actions\":[{\"tool\":\"write_file\",\"args\":{\"path\":"
                + "\"app/lib/services/number_format.dart\"}}]}\n```\n"
                + "```json\n{\"actions\":[{\"tool\":\"repo_browser.write_file\",\"args\":{\"path\":"
                + "\"app/test/number_format_test.dart\"},\"content\":\"void main() {}\\n\"}]}\n```")
        #expect(calls.map { $0.args["path"] as? String } == [
            "app/lib/services/number_format.dart", "app/test/number_format_test.dart",
        ])
        // Le premier reste sans contenu : il sera demandé, pas inventé.
        #expect(calls.first?.args["content"] == nil)
        #expect(calls.last?.args["content"] as? String == "void main() {}\n")
    }

    @Test func vraiContenuApresLeJSONResteLeContenu() {
        let code = parseToolCalls(
            "```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"a.dart\"}}\n```\n```dart\nint f() => 1;\n```")
        #expect(code.count == 1)
        #expect(code.first?.args["content"] as? String == "int f() => 1;\n")

        let fixture = parseToolCalls(
            "```json\n{\"tool\":\"write_file\",\"args\":{\"path\":\"test/action.json\"}}\n```\n"
                + "```json\n{\"tool\": \"finish\", \"args\": {}}\n```")
        #expect(fixture.count == 1)
        #expect(fixture.first?.args["content"] as? String == "{\"tool\": \"finish\", \"args\": {}}\n")
    }
}
