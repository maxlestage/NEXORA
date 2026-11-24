import Foundation
import Testing
@testable import NexoraKit

/// write_file qui effacerait la plupart du code d'un fichier existant (port de
/// Flutter 2.2.82) : rien n'est écrit, l'agent apprend comment ajouter son code.
@Suite("Agent : write_file n'efface plus le code existant")
@MainActor
struct EraseGuardTests {
    /// Le début réel de app/lib/services/diff.dart.
    static let diff = """
    /// Une comparaison ligne à ligne.
    library;

    enum DiffKind { same, added, removed }

    class DiffLine {
      const DiffLine(this.kind, this.text, {this.oldNo, this.newNo});

      final DiffKind kind;
      final String text;
      final int? oldNo;
      final int? newNo;
    }

    class DiffResult {
      const DiffResult(this.lines, {this.truncated = false});

      final List<DiffLine> lines;
      final bool truncated;
    }

    """

    /// Ce qu'a écrit le modèle en essai réel : seulement la fonction ajoutée.
    static let onlyNew = #"""
    // Added function to compute added and removed lines from a unified diff
    List<int> diffStats(String diff) {
      int added = 0;
      int removed = 0;
      for (final line in diff.split('\n')) {
        if (line.startsWith('+++') || line.startsWith('---')) continue;
        if (line.startsWith('+')) added++;
        if (line.startsWith('-')) removed++;
      }
      return [added, removed];
    }

    """#

    @Test("seulement la fonction ajoutée : presque tout est effacé")
    func onlyAdded() throws {
        let gone = try #require(AgentRun.erasedLines(Self.diff, Self.diff, Self.onlyNew))
        #expect(gone.contains("class DiffResult {"))
        #expect(gone.contains("enum DiffKind { same, added, removed }"))
    }

    @Test("fichier complet, petites retouches, petit fichier, lignes déjà retirées : rien")
    func nothing() {
        #expect(AgentRun.erasedLines(Self.diff, Self.diff, Self.diff + "\n" + Self.onlyNew) == nil)
        let edited = Self.diff
            .replacingOccurrences(of: "  final bool truncated;\n", with: "")
            .replacingOccurrences(of: "final int? oldNo;", with: "final int? oldLine;")
        #expect(AgentRun.erasedLines(Self.diff, Self.diff, edited) == nil)
        #expect(AgentRun.erasedLines("a = 1\nb = 2\n", "a = 1\nb = 2\n", "c = 3") == nil)
        let now = String(Self.diff[..<Self.diff.range(of: "class DiffLine")!.lowerBound])
        #expect(AgentRun.erasedLines(Self.diff, now, now + "\n" + Self.onlyNew) == nil)
    }

    func session(_ writes: [[String: Any]]) async -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM(writes.map { act(["tool": "write_file", "args": $0]) })
        llm.whenEmpty = act(["tool": "finish", "args": ["summary": "fin"]])
        let run = makeRun(llm, hub: repoHub(["lib/diff.dart": Self.diff]), repo: "app",
                          task: "Ajoute une fonction diffStats dans lib/diff.dart", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        return (run, llm)
    }

    @Test("seulement la fonction ajoutée, fichier non lu : refusé, l'agent apprend comment ajouter")
    func refused() async {
        let (run, llm) = await session([["path": "lib/diff.dart", "content": Self.onlyNew]])
        #expect(!run.changes.contains("lib/diff.dart"))
        let r = llm.last(1)
        #expect(r.contains("rien n'est écrit"))
        #expect(r.contains("REMPLACE tout lib/diff.dart"))
        #expect(r.contains("13 des 13 lignes de code existantes"))
        #expect(r.contains("« const DiffLine("))
        #expect(!r.contains("« /// Une comparaison"))
        #expect(r.contains("\"at_end\": true"))
    }

    @Test("refusé, puis l'ajout à la fin : le fichier garde tout son code")
    func thenAppend() async {
        let (run, _) = await session([
            ["path": "lib/diff.dart", "content": Self.onlyNew],
            ["path": "lib/diff.dart", "content": Self.onlyNew, "at_end": true],
        ])
        let d = run.draft("lib/diff.dart") ?? ""
        #expect(d.hasPrefix(Self.diff))
        #expect(d.contains("List<int> diffStats(String diff) {"))
    }

    @Test("contenu complet écrit du premier coup ; \"force\" efface ; nouveau fichier libre")
    func allowed() async {
        let (full, llm) = await session([["path": "lib/diff.dart", "content": Self.diff + "\n" + Self.onlyNew]])
        #expect(full.draft("lib/diff.dart")?.contains("class DiffResult {") == true)
        #expect(llm.last(1).contains("enregistré en brouillon"))
        let (forced, _) = await session([["path": "lib/diff.dart", "content": Self.onlyNew, "force": true]])
        #expect(forced.draft("lib/diff.dart")?.contains("class DiffResult") == false)
        let (fresh, _) = await session([["path": "lib/stats.dart", "content": Self.onlyNew]])
        #expect(fresh.draft("lib/stats.dart")?.contains("diffStats") == true)
    }
}
