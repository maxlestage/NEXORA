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

/// Journal simulé d'un projet JavaScript en échec : `npm ci` (45 avertissements de paquets
/// dépréciés), `docker build` (8 couches téléchargées, 1 étape en erreur), puis
/// `vite build` (70 fichiers produits) suivi d'une erreur TypeScript.
func sampleJSLog() -> String {
    var l = ["##[group]Run npm ci", "npm ci", "##[endgroup]"]
    for n in 1...45 {
        l.append("npm warn deprecated paquet-\(n)@\(n % 9).\(n % 4).0: This version is no longer supported. Please upgrade to paquet-\(n)@\(n % 9 + 1) or see https://exemple.dev/paquet-\(n)/migration")
    }
    l += ["added 1423 packages, and audited 1424 packages in 38s",
          "##[group]Run docker build -t nexora .", "docker build -t nexora .", "##[endgroup]",
          "#1 [internal] load build definition from Dockerfile", "#1 transferring dockerfile: 512B done", "#1 DONE 0.0s",
          "#4 [1/6] FROM docker.io/library/node:22@sha256:0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0",
          "#4 resolve docker.io/library/node:22@sha256:0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0 done"]
    for couche in 1...8 {
        let h = String(repeating: "\(couche)a", count: 32)
        for pas in 1...12 { l.append("#4 sha256:\(h) \(pas * 4).19MB / 48.23MB \(pas).\(couche)s") }
        l += ["#4 sha256:\(h) 48.23MB / 48.23MB 1.\(couche)s done", "#4 extracting sha256:\(h) 0.\(couche)s done"]
    }
    l += ["#4 DONE 14.2s", "#5 [2/6] WORKDIR /app", "#5 DONE 0.1s", "#6 [3/6] COPY package.json .", "#6 DONE 0.0s",
          "#7 [4/6] RUN npm run lint", "#7 0.412 > nexora@1.0.0 lint", "#7 0.412 > eslint src",
          "#7 2.108 /app/src/total.ts", "#7 2.108   12:7  error  'total' is assigned a value but never used  no-unused-vars",
          "#7 ERROR: process \"/bin/sh -c npm run lint\" did not complete successfully: exit code: 1",
          "##[error]Process completed with exit code 1.",
          "##[group]Run npm run build", "npm run build", "##[endgroup]",
          "vite v6.0.1 building for production...", "✓ 812 modules transformed."]
    for n in 1...70 {
        l.append("dist/assets/morceau-\(n)-a1b2c3d\(n % 10).js    \(n + 3).\(n % 100) kB │ gzip: \(n / 3 + 1).\(n % 10)0 kB")
    }
    l += ["✓ built in 6.41s",
          "##[group]Run npx tsc --noEmit", "npx tsc --noEmit", "##[endgroup]",
          "src/total.ts(14,9): error TS2322: Type 'string' is not assignable to type 'number'.",
          "##[error]Process completed with exit code 2."]
    return l.map { "2026-11-20T08:00:00.0000000Z \($0)" }.joined(separator: "\n")
}

extension CILogTests {
    @Test("npm, Docker, fichiers produits : une ligne par suite, les erreurs restent")
    func jsSteps() {
        let out = CILog.clean([
            "npm warn deprecated glob@7.2.3: Glob versions prior to v9 are no longer supported",
            "npm WARN deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported",
            "npm warn deprecated vieux@1.0.0: fails on Node 22, upgrade",
            " WARN  deprecated eslint@8.57.1: This version is no longer supported.",
            "added 12 packages in 2s",
            "#4 sha256:abcdef0123 4.19MB / 48.23MB 0.2s", "#4 sha256:abcdef0123 48.23MB / 48.23MB 1.1s done",
            "#4 extracting sha256:abcdef0123 0.4s done", "#4 DONE 2.0s",
            "#5 [2/6] RUN npm test", "#5 0.412 > nexora@1.0.0 test", "#5 1.200 2 tests passed",
            "#5 DONE 1.3s", "#6 [3/6] COPY . .", "#6 CACHED", "#7 [4/6] RUN npm run lint",
            "#7 ERROR: process \"/bin/sh -c npm run lint\" did not complete successfully: exit code: 1",
            "dist/index.html                  0.46 kB │ gzip:  0.30 kB",
            "dist/assets/index-a1b2c3d4.css  12.31 kB │ gzip:  3.02 kB",
            "dist/assets/index-e5f6a7b8.js  142.80 kB │ gzip: 45.91 kB",
            "✓ built in 1.20s",
            "Taille du rapport : 12 kB",
        ].joined(separator: "\n"))
        #expect(out == [
            "npm WARN deprecated rimraf@3.0.2: Rimraf versions prior to v4 are no longer supported",
            "npm warn deprecated vieux@1.0.0: fails on Node 22, upgrade",
            " WARN  deprecated eslint@8.57.1: This version is no longer supported.",
            "added 12 packages in 2s",
            "#5 [2/6] RUN npm test", "#5 0.412 > nexora@1.0.0 test", "#5 1.200 2 tests passed",
            "#7 [4/6] RUN npm run lint",
            "#7 ERROR: process \"/bin/sh -c npm run lint\" did not complete successfully: exit code: 1",
            "dist/assets/index-e5f6a7b8.js  142.80 kB │ gzip: 45.91 kB",
            "✓ built in 1.20s",
            "Taille du rapport : 12 kB",
        ])
    }

    @Test("journal JavaScript et Docker en échec : moins de tokens, les erreurs restent")
    func jsLogBench() {
        let raw = sampleJSLog()
        let after = CILog.condense(raw, lines: 200)
        print("🪙 journal JavaScript et Docker (200 lignes) : \(plainTail(raw, lines: 200).count / 4) → \(after.count / 4) tokens")
        #expect(after.count / 4 < 400)
        #expect(after.contains("#7 [4/6] RUN npm run lint"))
        #expect(after.contains("12:7  error  'total' is assigned a value but never used"))
        #expect(after.contains("#7 ERROR: process"))
        #expect(after.contains("added 1423 packages"))
        #expect(after.contains("✓ built in 6.41s"))
        #expect(after.contains("src/total.ts(14,9): error TS2322"))
    }
}

/// Un journal type yarn + Go + Maven + Composer + dotnet : installations bavardes, puis
/// un test Go et une compilation Java en échec.
func samplePolyglotLog() -> String {
    var l = ["##[group]Run yarn install --frozen-lockfile", "yarn install --frozen-lockfile", "##[endgroup]",
             "yarn install v1.22.22", "[1/4] Resolving packages...", "[2/4] Fetching packages..."]
    for n in 1...40 {
        l.append("warning outil-\(n) > ancien-\(n)@\(n % 7).\(n % 3).1: This package is deprecated and no longer maintained. Use nouveau-\(n) instead, see https://exemple.dev/ancien-\(n)")
    }
    l += ["[3/4] Linking dependencies...", "[4/4] Building fresh packages...", "Done in 41.20s.",
          "##[group]Run go test ./...", "go test ./...", "##[endgroup]"]
    for n in 1...40 { l.append("go: downloading github.com/exemple/module-\(n) v1.\(n).\(n % 5)") }
    l += ["--- FAIL: TestTotal (0.00s)", "    total_test.go:14: obtenu 3, attendu 4", "FAIL",
          "FAIL\tgithub.com/exemple/nexora/total\t0.012s", "##[error]Process completed with exit code 1.",
          "##[group]Run mvn -B verify", "mvn -B verify", "##[endgroup]", "[INFO] Scanning for projects..."]
    for n in 1...30 {
        let u = "https://repo.maven.apache.org/maven2/org/exemple/lib-\(n)/2.\(n).0/lib-\(n)-2.\(n).0"
        l += ["Downloading from central: \(u).pom", "Downloaded from central: \(u).pom (\(n + 2).4 kB at \(n * 3) kB/s)",
              "Downloading from central: \(u).jar", "Downloaded from central: \(u).jar (\(n * 12) kB at \(n * 40) kB/s)"]
    }
    l += ["[ERROR] /home/runner/work/nexora/nexora/src/main/java/Total.java:[12,9] incompatible types: String cannot be converted to int",
          "[INFO] BUILD FAILURE", "##[error]Process completed with exit code 1.",
          "##[group]Run composer install", "composer install", "##[endgroup]",
          "Installing dependencies from lock file (including require-dev)"]
    for n in 1...25 { l.append("  - Downloading vendeur/paquet-\(n) (v3.\(n).0)") }
    for n in 1...25 { l.append("  - Installing vendeur/paquet-\(n) (v3.\(n).0): Extracting archive") }
    l += ["Generating autoload files",
          "##[group]Run dotnet restore", "dotnet restore", "##[endgroup]", "  Determining projects to restore..."]
    for n in 1...12 { l.append("  Restored /home/runner/work/nexora/nexora/src/Projet\(n)/Projet\(n).csproj (in \(n * 110) ms).") }
    l += ["Projet3/Total.cs(8,13): error CS0029: Cannot implicitly convert type 'string' to 'int'",
          "##[error]Process completed with exit code 1."]
    return l.map { "2026-11-20T08:00:00.0000000Z \($0)" }.joined(separator: "\n")
}

extension CILogTests {
    @Test("yarn, Go, Maven, Composer, dotnet : une ligne par suite, les erreurs restent")
    func polyglotSteps() {
        let out = CILog.clean([
            "warning jest > jsdom > abab@2.0.6: Use your platform's native atob() and btoa() methods instead",
            "warning glob@7.2.3: Glob versions prior to v9 are no longer supported",
            "warning \" > a@1.0.0\" has unmet peer dependency \"b@^2.0.0\".",
            "➤ YN0013: │ lodash@npm:4.17.21 can't be found in the cache and will be fetched from the remote registry",
            "➤ YN0013: │ react@npm:19.0.0 can't be found in the cache and will be fetched from the remote registry",
            "➤ YN0000: └ Completed in 4s 120ms",
            "go: downloading github.com/a/b v1.2.3", "go: downloading golang.org/x/sys v0.27.0",
            "go: downloading github.com/a/go-error v1.0.0",
            "ok  \tgithub.com/exemple/nexora\t0.004s",
            "Downloading from central: https://repo.maven.apache.org/maven2/a/1/a-1.pom",
            "Downloaded from central: https://repo.maven.apache.org/maven2/a/1/a-1.pom (2.4 kB at 30 kB/s)",
            "Progress (1): 4.1/12 kB",
            "[INFO] Downloaded from central: https://repo.maven.apache.org/maven2/a/1/a-1.jar (12 kB at 90 kB/s)",
            "[INFO] BUILD SUCCESS",
            "  - Downloading symfony/console (v7.1.0)", "  - Installing symfony/console (v7.1.0): Extracting archive",
            "  - Upgrading psr/log (3.0.0 => 3.0.2): Extracting archive",
            "  - Le point d'une liste (à garder)",
            "  Restored /src/A/A.csproj (in 1.2 sec).", "  Restored /src/B/B.csproj (in 310 ms).",
            "Build succeeded.",
        ].joined(separator: "\n"))
        #expect(out == [
            "warning glob@7.2.3: Glob versions prior to v9 are no longer supported",
            "warning \" > a@1.0.0\" has unmet peer dependency \"b@^2.0.0\".",
            "➤ YN0013: │ react@npm:19.0.0 can't be found in the cache and will be fetched from the remote registry",
            "➤ YN0000: └ Completed in 4s 120ms",
            "go: downloading golang.org/x/sys v0.27.0",
            "go: downloading github.com/a/go-error v1.0.0",
            "ok  \tgithub.com/exemple/nexora\t0.004s",
            "[INFO] Downloaded from central: https://repo.maven.apache.org/maven2/a/1/a-1.jar (12 kB at 90 kB/s)",
            "[INFO] BUILD SUCCESS",
            "  - Upgrading psr/log (3.0.0 => 3.0.2): Extracting archive",
            "  - Le point d'une liste (à garder)",
            "  Restored /src/B/B.csproj (in 310 ms).",
            "Build succeeded.",
        ])
    }

    @Test("journal yarn, Go, Maven, Composer, dotnet en échec : moins de tokens, les erreurs restent")
    func polyglotLogBench() {
        let raw = samplePolyglotLog()
        let after = CILog.condense(raw, lines: 200)
        print("🪙 journal yarn, Go, Maven, Composer, dotnet (200 lignes) : \(plainTail(raw, lines: 200).count / 4) → \(after.count / 4) tokens")
        #expect(after.count / 4 < 500)
        #expect(after.contains("Done in 41.20s."))
        #expect(after.contains("total_test.go:14: obtenu 3, attendu 4"))
        #expect(after.contains("--- FAIL: TestTotal"))
        #expect(after.contains("Total.java:[12,9] incompatible types"))
        #expect(after.contains("[INFO] BUILD FAILURE"))
        #expect(after.contains("Generating autoload files"))
        #expect(after.contains("Total.cs(8,13): error CS0029"))
    }
}
