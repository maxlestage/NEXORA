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

    @Test("messages semblables regroupés, marqueurs d'actions et téléchargements retirés")
    func folding() {
        let msg = "   info • 'material.dart' is deprecated • "
        var raw = ["##[start-action display=Cache;id=x]", "Received 10 of 100 (10.0%), 5 MBs/sec",
                   "Received 100 of 100 (100.0%), 5 MBs/sec", "##[end-action id=x;outcome=success]",
                   "Analyzing app..."]
        raw += (1...6).map { msg + "lib/f\($0).dart:\($0):1 • deprecated_member_use" }
        raw += ["lib/a.swift:3:1: error: x", "lib/b.swift:4:1: error: x",
                "   error • autre • lib/g.dart:2:1 • rule", "6 issues found."]
        let out = CILog.clean(raw.joined(separator: "\n"))
        #expect(out == [
            "Received 100 of 100 (100.0%), 5 MBs/sec",
            "Analyzing app...",
            msg + "lib/f1.dart:1:1 • deprecated_member_use",
            "  (+5 semblables : lib/f2.dart:2:1, lib/f3.dart:3:1, lib/f4.dart:4:1, lib/f5.dart:5:1, lib/f6.dart:6:1)",
            "lib/a.swift:3:1: error: x", "lib/b.swift:4:1: error: x",
            "   error • autre • lib/g.dart:2:1 • rule", "6 issues found.",
        ])
        // Au-delà de `foldPlaces` emplacements : la liste s'arrête sur « … ».
        let many = (1...40).map { msg + "lib/f\($0).dart:1:1 • r" }.joined(separator: "\n")
        let folded = CILog.clean(many)
        #expect(folded.count == 2)
        #expect(folded[1].hasPrefix("  (+39 semblables : lib/f2.dart:1:1,"))
        #expect(folded[1].hasSuffix("lib/f31.dart:1:1, …)"))
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
    @Test("journal xcodebuild : chemins du dossier de travail du runner retirés")
    func xcodebuildBench() {
        let root = "/Users/runner/work/NEXORA/NEXORA/"
        var l: [String] = ["▸ Run xcodebuild test"]
        for n in 1...120 {
            let f = root + "ios/Nexora/Views/Vue\(n).swift"
            l.append("SwiftCompile normal arm64 Compiling\\ Vue\(n).swift \(f) (in target 'Nexora' from project 'Nexora')")
            l.append("    cd \(root)ios")
            if n % 10 == 0 { l.append("\(f):\(n):5: warning: 'onChange(of:perform:)' was deprecated in iOS 17.0") }
            if n == 90 { l += ["\(f):7:9: error: cannot find 'foo' in scope", "        foo()", "        ^~~"] }
        }
        l += ["** TEST FAILED **", "##[error]Process completed with exit code 65."]
        let raw = l.joined(separator: "\n")
        let after = CILog.condense(raw, lines: 200)
        print("🪙 journal xcodebuild (200 lignes) : \(plainTail(raw, lines: 200).count / 4) → \(after.count / 4) tokens")
        #expect(after.contains("ios/Nexora/Views/Vue90.swift:7:9: error: cannot find 'foo' in scope"))
        #expect(!after.contains(root))
        #expect(after.contains("    cd ios"))
        // Ailleurs qu'au dossier de travail, le chemin reste tel quel.
        #expect(CILog.clean("/Users/runner/Library/x.swift:1:1: error: y") == ["/Users/runner/Library/x.swift:1:1: error: y"])
        #expect(CILog.clean("/home/runner/work/site/site/lib/a.dart:3:1: error: z") == ["lib/a.dart:3:1: error: z"])
        #expect(CILog.clean("cd /__w/site/site && make") == ["cd . && make"])
    }
    @Test("journal xcodebuild : commandes complètes du compilateur raccourcies")
    func xcodebuildCommandsBench() {
        let dd = "/Users/runner/Library/Developer/Xcode/DerivedData/Nexora-bxkqzjwlmcfoyhdzrtpq/Build/Intermediates.noindex/Nexora.build/Debug-iphonesimulator/Nexora.build"
        let tool = "/Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend"
        var l: [String] = ["▸ Run xcodebuild test"]
        for n in 1...40 {
            let f = "/Users/runner/work/NEXORA/NEXORA/ios/Nexora/Views/Vue\(n).swift"
            l.append("SwiftCompile normal arm64 \(f) (in target 'Nexora' from project 'Nexora')")
            l.append("    cd /Users/runner/work/NEXORA/NEXORA/ios")
            // La commande complète (≈ 4 000 car.), comme xcodebuild l'affiche.
            let flags = (1...30).map { " -I \(dd)/Objects-normal/arm64/m\($0) -Xcc -fmodule-map-file=\(dd)/m\($0).modulemap" }.joined()
            l.append("    builtin-swiftTaskExecution -- \(tool) -frontend -c -primary-file \(f)\(flags) -o \(dd)/Objects-normal/arm64/Vue\(n).o")
            if n == 30 { l += ["\(f):7:9: error: cannot find 'foo' in scope", "        foo()", "        ^~~"] }
        }
        l += ["** TEST FAILED **", "##[error]Process completed with exit code 65."]
        let raw = l.joined(separator: "\n")
        let after = CILog.condense(raw, lines: 200)
        let kept = CILog.clean(raw).filter { $0.contains("builtin-swiftTaskExecution") }
        print("🪙 journal xcodebuild avec commandes (200 lignes) : \(plainTail(raw, lines: 200).count / 4) → \(after.count / 4) tokens")
        #expect(after.contains("ios/Nexora/Views/Vue30.swift:7:9: error: cannot find 'foo' in scope"))
        #expect(after.contains("##[error]Process completed with exit code 65."))
        #expect(kept.count == 40)
        #expect(kept.allSatisfy { $0.count < CILog.longKeep + 30 && $0.hasSuffix(" car.)") })
        #expect(after.count < plainTail(raw, lines: 200).count / 5)
        // Une ligne d'erreur longue est gardée bien plus loin ; une ligne courte, telle quelle.
        let longError = "a.swift:1:1: error: " + String(repeating: "x", count: 1500)
        #expect(CILog.shorten(longError) == longError)
        #expect(CILog.shorten("court") == "court")
    }
}

/// Un journal de tests en échec : `swift test` (350 tests, chacun « lancé » puis
/// « réussi », 2 échecs au milieu), puis `flutter test` (200 tests, 1 échec).
func sampleTestLog() -> String {
    var l: [String] = ["##[group]Run swift test --package-path NexoraKit", "swift test", "##[endgroup]",
                       "Build complete! (42.10s)", "◇ Test run started.", "◇ Suite ChatTests started."]
    for n in 1...350 {
        l.append("◇ Test essai\(n)() started.")
        if n == 120 || n == 121 {
            l.append("✘ Test essai\(n)() recorded an issue at ChatTests.swift:\(n):9: Expectation failed: (titre → \"a\") == \"b\"")
            l.append("✘ Test essai\(n)() failed after 0.002 seconds with 1 issue.")
        } else {
            l.append("✔ Test essai\(n)() passed after 0.001 seconds.")
        }
    }
    l += ["✘ Suite ChatTests failed after 1.204 seconds with 2 issues.",
          "✘ Test run with 350 tests in 1 suite failed after 1.210 seconds with 2 issues.",
          "##[error]Process completed with exit code 1.",
          "##[group]Run flutter test", "flutter test", "##[endgroup]"]
    for n in 1...200 {
        let failed = n > 90 ? " -1" : ""
        l.append("00:\(String(format: "%02d", n / 10)) +\(n > 90 ? n - 1 : n)\(failed): test/widget\(n % 9)_test.dart: cas numéro \(n)")
        if n == 90 {
            l += ["══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞══", "Expected: <3>", "  Actual: <4>",
                  "00:09 +89 -1: test/widget0_test.dart: cas numéro 90 [E]", "  Test failed. See exception logs above."]
        }
    }
    l += ["00:20 +199 -1: Some tests failed.", "##[error]Process completed with exit code 1."]
    return l.map { "2026-11-20T08:00:00.0000000Z \($0)" }.joined(separator: "\n")
}

extension CILogTests {
    @Test("tests réussis ou lancés : une ligne par suite, les échecs et les bilans restent")
    func passedTests() {
        let out = CILog.clean([
            "◇ Test run started.", "◇ Test a() started.", "✔ Test a() passed after 0.001 seconds.",
            "◇ Test b() started.", "✘ Test b() recorded an issue at T.swift:3:9: Expectation failed",
            "✘ Test b() failed after 0.002 seconds with 1 issue.",
            "Test Case 'T.c' started at 2026-11-20 08:00:00.000", "Test Case 'T.c' passed (0.001 seconds).",
            "Test case 'T.d()' passed on 'Clone 1 of iPhone 17 - Nexora (123)' (0.004 seconds)",
            "Test case 'T.e()' failed on 'Clone 1 of iPhone 17 - Nexora (123)' (0.004 seconds)",
            "✔ Test run with 5 tests in 1 suite passed after 0.010 seconds.",
            "00:01 +1: test/a_test.dart: un", "00:01 +2: test/a_test.dart: deux",
            "00:01 +2 -1: test/a_test.dart: deux [E]", "00:02 +3 -1: Some tests failed.",
            "test result: ok. 3 passed; 0 failed", "Tests passed after a retry",
        ].joined(separator: "\n"))
        #expect(out == [
            "◇ Test run started.",
            "◇ Test b() started.  (+2 lignes de tests réussis ou lancés)",
            "✘ Test b() recorded an issue at T.swift:3:9: Expectation failed",
            "✘ Test b() failed after 0.002 seconds with 1 issue.",
            "Test case 'T.d()' passed on 'Clone 1 of iPhone 17 - Nexora (123)' (0.004 seconds)  (+2 lignes de tests réussis ou lancés)",
            "Test case 'T.e()' failed on 'Clone 1 of iPhone 17 - Nexora (123)' (0.004 seconds)",
            "✔ Test run with 5 tests in 1 suite passed after 0.010 seconds.",
            "00:01 +2: test/a_test.dart: deux  (+1 ligne de tests réussis ou lancés)",
            "00:01 +2 -1: test/a_test.dart: deux [E]", "00:02 +3 -1: Some tests failed.",
            "test result: ok. 3 passed; 0 failed", "Tests passed after a retry",
        ])
    }

    @Test("journal de tests en échec : moins de tokens, les échecs et les bilans restent")
    func testLogBench() {
        let raw = sampleTestLog()
        let after = CILog.condense(raw, lines: 200)
        print("🪙 journal de tests (200 lignes) : \(plainTail(raw, lines: 200).count / 4) → \(after.count / 4) tokens")
        #expect(after.count / 4 < 900)
        #expect(after.contains("Test essai120() recorded an issue at ChatTests.swift:120:9"))
        #expect(after.contains("Test essai121() failed after"))
        #expect(after.contains("Test run with 350 tests in 1 suite failed"))
        #expect(after.contains("Actual: <4>"))
        #expect(after.contains("cas numéro 90 [E]"))
        #expect(after.contains("Some tests failed."))
    }
}

/// Journal simulé de trois jobs en échec après une longue installation : `cargo build`
/// (150 dépendances compilées, 1 erreur), Gradle (120 tâches, 1 en échec), puis
/// `pip install` (60 paquets) suivi d'un test pytest en échec.
func sampleInstallLog() -> String {
    var l = ["##[group]Run cargo build --locked", "cargo build --locked", "##[endgroup]"]
    for n in 1...150 { l.append("   Compiling dependance-\(n) v1.\(n % 7).\(n % 13)") }
    l += ["   Compiling nexora v0.1.0 (/home/runner/work/nexora/nexora)",
          "error[E0425]: cannot find value `total` in this scope",
          "  --> src/main.rs:12:20", "   |", "12 |     println!(\"{}\", total);", "   |                    ^^^^^ not found in this scope",
          "error: could not compile `nexora` (bin \"nexora\") due to 1 previous error",
          "##[error]Process completed with exit code 101.",
          "##[group]Run ./gradlew assembleDebug", "./gradlew assembleDebug", "##[endgroup]"]
    let etats = ["", " UP-TO-DATE", " NO-SOURCE", " FROM-CACHE"]
    for n in 1...120 { l.append("> Task :app:etape\(n)Debug\(etats[n % 4])") }
    l += ["> Task :app:compileDebugKotlin FAILED",
          "e: file:///home/runner/work/nexora/nexora/app/src/main/kotlin/Main.kt:12:5 Unresolved reference: total",
          "FAILURE: Build failed with an exception.", "* What went wrong:",
          "Execution failed for task ':app:compileDebugKotlin'.", "BUILD FAILED in 1m 12s",
          "##[error]Process completed with exit code 1.",
          "##[group]Run pip install -r requirements.txt", "pip install -r requirements.txt", "##[endgroup]"]
    for n in 1...60 {
        l += ["Collecting paquet\(n)>=1.\(n % 5) (from -r requirements.txt (line \(n)))",
              "  Downloading paquet\(n)-1.\(n % 5).0-py3-none-any.whl (\(n + 10) kB)",
              "     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ \(n + 10).0/\(n + 10).0 kB 5.1 MB/s eta 0:00:00"]
    }
    l += ["Installing collected packages: paquet1, paquet2, paquet3",
          "Successfully installed paquet1-1.1.0 paquet2-1.2.0 paquet3-1.3.0",
          "##[group]Run pytest", "pytest", "##[endgroup]",
          "tests/test_total.py F                                                    [100%]",
          "E       assert 3 == 4", "tests/test_total.py:8: AssertionError",
          "FAILED tests/test_total.py::test_total - assert 3 == 4",
          "##[error]Process completed with exit code 1."]
    return l.map { "2026-11-20T08:00:00.0000000Z \($0)" }.joined(separator: "\n")
}

extension CILogTests {
    @Test("installation et étapes de build : une ligne par suite, les échecs restent")
    func installSteps() {
        let out = CILog.clean([
            "   Compiling serde v1.0.210", "   Compiling tokio v1.40.0", "   Compiling app v0.1.0 (/src/app)",
            "error[E0425]: cannot find value `x` in this scope",
            "> Task :app:preBuild UP-TO-DATE", "> Task :app:merge", "> Task :app:lint",
            "w: Main.kt:3:1 Variable inutilisée", "> Task :app:compileKotlin FAILED",
            "Collecting requests", "  Downloading requests-2.32.3-py3-none-any.whl (64 kB)",
            "Requirement already satisfied: idna in ./venv", "Downloading failure-0.1.whl",
            "Successfully installed requests-2.32.3",
            "+ args 2.6.0", "+ async 2.12.0 (2.13.0 available)", "Changed 2 dependencies!",
            "Fetching https://github.com/a/b.git", "Fetched https://github.com/a/b.git from cache (0.42s)",
            "Computing version for https://github.com/a/b.git", "Build complete!",
            "Installing rake 13.2.1", "Using json 2.7.2", "Installing Alamofire (5.9.1)", "Bundle complete!",
            "+ rm -rf build 1.2.3 autre", "Compiling the project failed",
        ].joined(separator: "\n"))
        #expect(out == [
            "   Compiling app v0.1.0 (/src/app)",
            "error[E0425]: cannot find value `x` in this scope",
            "> Task :app:lint",
            "w: Main.kt:3:1 Variable inutilisée", "> Task :app:compileKotlin FAILED",
            "Requirement already satisfied: idna in ./venv", "Downloading failure-0.1.whl",
            "Successfully installed requests-2.32.3",
            "+ async 2.12.0 (2.13.0 available)", "Changed 2 dependencies!",
            "Computing version for https://github.com/a/b.git", "Build complete!",
            "Installing Alamofire (5.9.1)", "Bundle complete!",
            "+ rm -rf build 1.2.3 autre", "Compiling the project failed",
        ])
    }

    @Test("journal d'installation puis échec : moins de tokens, les erreurs restent")
    func installLogBench() {
        let raw = sampleInstallLog()
        let after = CILog.condense(raw, lines: 200)
        print("🪙 journal d'installation (200 lignes) : \(plainTail(raw, lines: 200).count / 4) → \(after.count / 4) tokens")
        #expect(after.count / 4 < 700)
        #expect(after.contains("error[E0425]: cannot find value `total`"))
        #expect(after.contains("src/main.rs:12:20"))
        #expect(after.contains("> Task :app:compileDebugKotlin FAILED"))
        #expect(after.contains("Main.kt:12:5 Unresolved reference: total"))
        #expect(after.contains("BUILD FAILED in 1m 12s"))
        #expect(after.contains("FAILED tests/test_total.py::test_total - assert 3 == 4"))
    }
}
