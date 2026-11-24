import Foundation
import Testing
@testable import NexoraKit

/// edit_file avec seulement une plage de lignes (port de Flutter 2.2.88) : les
/// lignes sont montrées puis remplacées, au lieu de « il manque le texte ».
@Suite("Agent : modifications par numéros de lignes")
struct AgentLineRangeTests {
    static let notes = (1...30).map { "- Point numéro \($0)" }.joined(separator: "\n")

    @MainActor
    func notesRun(_ llm: ScriptLLM) -> AgentRun {
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(["site/notes.md": Self.notes + "\n"]), task: "Corrige les points 4 à 6", checks: false)
        run.specs.append("déjà compris")
        return run
    }

    func expected(_ replaced: String) -> String {
        var lines = Self.notes.components(separatedBy: "\n")
        lines.replaceSubrange(3..<6, with: [replaced])
        return lines.joined(separator: "\n") + "\n"
    }

    @Test("plage seule : les lignes sont montrées, puis remplacées par le texte suivant")
    @MainActor
    func rangeThenText() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/notes.md\",\"line_start\":4,\"line_end\":6}}\n```",
            "```markdown\n- Points 4 à 6 réunis\n```",
        ])
        let run = notesRun(llm)
        await run.run()
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("EN ATTENTE du nouveau texte des lignes 4 à 6"))
        #expect(second.contains("5: - Point numéro 5"))
        #expect(!second.contains("il manque le texte"))
        #expect(run.draft("site/notes.md") == expected("- Points 4 à 6 réunis"))
    }

    @Test("plage avec le nouveau texte seul : remplacée directement")
    @MainActor
    func rangeWithText() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/notes.md\",\"lines\":\"4-6\",\"new\":\"- Trois en un\"}}\n```",
        ])
        let run = notesRun(llm)
        await run.run()
        #expect(run.draft("site/notes.md") == expected("- Trois en un"))
    }

    @Test("plage hors du fichier : erreur claire avec le nombre de lignes")
    @MainActor
    func rangeOutside() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/notes.md\",\"start_line\":404,\"end_line\":420}}\n```",
        ])
        let run = notesRun(llm)
        await run.run()
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("site/notes.md a 30 lignes, la ligne 404 n'existe pas"))
        #expect(run.draft("site/notes.md") == nil)
    }

    @Test("l'ancien passage donné reste la référence, même avec une plage")
    @MainActor
    func oldWins() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"site/notes.md\",\"line_start\":1,\"line_end\":2,\"old\":\"- Point numéro 9\\n\",\"new\":\"- Neuf\\n\"}}\n```",
        ])
        let run = notesRun(llm)
        await run.run()
        #expect(run.draft("site/notes.md") == Self.notes.replacingOccurrences(of: "- Point numéro 9\n", with: "- Neuf\n") + "\n")
    }

    // Ajout à la fin (port de Flutter 2.2.89) : « at_end » sans texte, ou la ligne
    // juste après la dernière.
    static let code = "int a() => 1;\nint b() => 2;\nint c() => 3;\n"
    static let added = "int d() => 4;"

    @MainActor
    func codeRun(_ llm: ScriptLLM) -> AgentRun {
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(["lib/diff.dart": Self.code]), task: "Ajoute d dans diff.dart", checks: false)
        run.specs.append("déjà compris")
        return run
    }

    @Test("at_end sans texte : le texte suivant est ajouté à la fin")
    @MainActor
    func atEndThenText() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"lib/diff.dart\",\"at_end\":true}}\n```",
            "```dart\n\(Self.added)\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("EN ATTENTE du texte à AJOUTER à la fin de lib/diff.dart"))
        #expect(!second.contains("il manque le texte"))
        #expect(run.draft("lib/diff.dart")?.hasPrefix(Self.code) == true)
        #expect(run.draft("lib/diff.dart")?.contains(Self.added) == true)
    }

    @Test("la ligne juste après la dernière, avec le texte : ajout à la fin")
    @MainActor
    func nextLineWithText() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"lib/diff.dart\",\"line_start\":4,\"line_end\":4,\"new\":\"\(Self.added)\"}}\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        #expect(run.draft("lib/diff.dart")?.hasPrefix(Self.code) == true)
        #expect(run.draft("lib/diff.dart")?.contains(Self.added) == true)
    }

    @Test("la ligne juste après la dernière, sans texte : attendu puis ajouté")
    @MainActor
    func nextLineThenText() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"lib/diff.dart\",\"line_start\":4,\"line_end\":4}}\n```",
            "```dart\n\(Self.added)\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("EN ATTENTE du texte à AJOUTER"))
        #expect(!second.contains("n'existe pas"))
        #expect(run.draft("lib/diff.dart")?.hasPrefix(Self.code) == true)
        #expect(run.draft("lib/diff.dart")?.contains(Self.added) == true)
    }

    @Test("une ligne bien au-delà de la fin : toujours une erreur claire")
    @MainActor
    func farBeyondEnd() async {
        let llm = ScriptLLM([
            "```json\n{\"tool\":\"edit_file\",\"args\":{\"path\":\"lib/diff.dart\",\"line_start\":9,\"line_end\":9,\"new\":\"x\"}}\n```",
        ])
        let run = codeRun(llm)
        await run.run()
        let second = llm.messages(1).last?["content"] ?? ""
        #expect(second.contains("lib/diff.dart a 3 lignes, la ligne 9 n'existe pas"))
        #expect(run.draft("lib/diff.dart") == nil)
    }
}
