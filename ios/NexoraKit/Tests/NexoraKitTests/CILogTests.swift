import Foundation
import Testing
@testable import NexoraKit

/// Un journal GitHub Actions typique d'une compilation qui échoue : préparation
/// (groupes repliés), 400 lignes de compilation avec une erreur au milieu,
/// avertissements, puis nettoyage de fin de job.
func sampleCILog() -> String {
    var l: [String] = ["Current runner version: '2.330.0'", "##[group]Runner Image"]
    l += (0..<8).map { "  Image detail \($0): ubuntu-24.04 20261102.1" }
    l += ["##[endgroup]", "##[group]Run actions/checkout@v4", "with:"]
    l += (0..<14).map { "  option-\($0): valeur par défaut \($0)" }
    l += ["##[endgroup]", "Syncing repository: max/site", "##[group]Getting Git version info"]
    l += (0..<25).map { "  git setting \($0) appliqué au dépôt de travail" }
    l += ["##[endgroup]", "##[group]Run swift build", "swift build", "shell: /usr/bin/bash -e {0}", "env:", "  PATH: /opt/swift/usr/bin", "##[endgroup]"]
    for n in 1...400 {
        l.append("[\(n)/400] Compiling NexoraKit Fichier\(n).swift")
        if n % 40 == 0 { l += ["/w/Sources/Fichier\(n).swift:12:5: warning: variable 'x' was never mutated", ""] }
        if n == 180 {
            l += ["/w/Sources/Fichier180.swift:42:13: error: cannot find 'foo' in scope",
                  "    let y = foo(3)", "            ^~~"]
        }
    }
    l += ["error: emit-module command failed with exit code 1 (use -v to see invocation)",
          "##[error]Process completed with exit code 1.",
          "Post job cleanup.", "##[group]Post Run actions/checkout@v4"]
    l += (0..<20).map { "[command]/usr/bin/git config --local --unset-all http.extraheader \($0)" }
    l += ["##[endgroup]", "Cleaning up orphan processes"]
    return l.map { "2026-11-12T19:00:00.0000000Z \($0)" }.joined(separator: "\n")
}

/// L'ancien raccourci : sans horodatage, les `lines` dernières lignes brutes.
func plainTail(_ raw: String, lines: Int) -> String {
    let stamp = DRegex(#"^\d{4}-\d\d-\d\dT[\d:.]+Z "#)
    let all = raw.dsplit("\n").map { stamp.replaceFirst($0, "") }
    return all.dropFirst(all.count > lines ? all.count - lines : 0).joined(separator: "\n")
}

@Suite("Journaux de CI")
struct CILogTests {
    @Test("nettoyage : horodatage, couleurs, groupes repliés, vides, doublons, fin de job")
    func clean() {
        let raw = """
        2026-11-12T19:00:00.1Z ##[group]Run swift test
        2026-11-12T19:00:00.1Z shell: bash
        2026-11-12T19:00:00.1Z error: dans le groupe
        2026-11-12T19:00:00.1Z ##[endgroup]
        \u{1B}[31mrouge\u{1B}[0m   \r

        même
        même
        ##[error]Process completed with exit code 1.
        Post job cleanup.
        git config --unset
        """
        #expect(CILog.clean(raw) == [
            "▸ Run swift test", "error: dans le groupe", "rouge", "même",
            "##[error]Process completed with exit code 1.",
        ])
        // Fins de ligne Windows ; progression : la dernière ligne de chaque suite.
        let progress = "[1/9] Compiling A\r\n[2/9] Compiling B\r\nerror: B.swift\r\n[3/9] Compiling C\r\n[9/9] Linking"
        #expect(CILog.clean(progress) == ["[2/9] Compiling B", "error: B.swift", "[9/9] Linking"])
    }

    @Test("court : tout le journal nettoyé ; long : erreurs d'avant la fin puis la fin")
    func condense() {
        #expect(CILog.condense("a\nb", lines: 5) == "a\nb")
        let lines = (0..<100).map { $0 == 10 ? "error: la cause" : "ligne \($0)" }
        let out = CILog.condense(lines.joined(separator: "\n"), lines: 20).dsplit("\n")
        #expect(out.prefix(5) == ["…", "ligne 8", "ligne 9", "error: la cause", "ligne 11"])
        #expect(out[5] == "… (72 lignes omises)")
        #expect(out.suffix(16) == lines.suffix(16)[...])
        // Sans erreur plus haut : la fin seule, comme avant.
        let plain = (0..<100).map { "ligne \($0)" }
        #expect(CILog.condense(plain.joined(separator: "\n"), lines: 20) == plain.suffix(20).joined(separator: "\n"))
        // Trop d'erreurs : seulement les premières (la cause), dans leur part du budget.
        let many = (0..<100).map { "error \($0)" }
        let kept = CILog.condense(many.joined(separator: "\n"), lines: 20).dsplit("\n")
        #expect(kept.first == "error 0")
        #expect(kept.count <= 22)
    }

    @Test("journal d'une compilation ratée : moins de tokens, et l'erreur reste")
    func bench() {
        let raw = sampleCILog()
        for lines in [200, 120] {
            let before = plainTail(raw, lines: lines)
            let after = CILog.condense(raw, lines: lines)
            print("🪙 journal CI (\(lines) lignes) : \(before.count / 4) → \(after.count / 4) tokens, "
                + "erreur avant : \(before.contains("cannot find 'foo'")), après : \(after.contains("cannot find 'foo'"))")
            #expect(after.count < before.count * 9 / 10)
            #expect(after.contains("cannot find 'foo' in scope"))
            #expect(after.contains("##[error]Process completed with exit code 1."))
            #expect(!after.contains("git config"))
            #expect(!after.contains("2026-11-12T"))
        }
    }
}
