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
}
