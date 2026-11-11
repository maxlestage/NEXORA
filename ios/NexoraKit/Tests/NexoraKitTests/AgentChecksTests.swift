import Foundation
import Testing
@testable import NexoraKit

/// Les garde-fous : tests et CI obligatoires, relecture, code Dart qui ne compile
/// pas, tests Rust mal placés, notes de progression, suivi de la CI.
@Suite("Agent : garde-fous")
@MainActor
struct AgentChecksTests {
    // MARK: - Tests et CI obligatoires

    @Test("du code sans test : l'agent est renvoyé écrire le workflow, les tests, puis relit")
    func mandatory() async {
        let llm = ScriptLLM([
            act("write_file", ["path": "lib/somme.dart"], "int somme(a, b) => a + b;"),
            act("finish", ["summary": "Fait"]),
            act("write_file", ["path": ".github/workflows/ci.yml"], "on: [push, pull_request]"),
            act("finish", ["summary": "Fait, avec CI"]),
            act("write_file", ["path": "test/somme_test.dart"], "void main() { expect(somme(1, 2), 3); }"),
            act("finish", ["summary": "Fait, avec tests"]),
            act("finish", ["summary": "Fait, avec tests, relu"]),
        ])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Ajoute une fonction somme")
        await run.run()
        #expect(run.summary == "Fait, avec tests, relu")
        #expect(run.changes.keys.contains("test/somme_test.dart"))
        #expect(run.changes.keys.contains(".github/workflows/ci.yml"))
        #expect(llm.last(2).contains("Aucun workflow GitHub"))
        #expect(llm.last(4).contains("sans écrire de test"))
        #expect(llm.last(6).contains("relis TOUTES tes modifications"))
        #expect(llm.last(6).contains("### lib/somme.dart"))
        #expect(llm.last(6).contains("+1: int somme(a, b) => a + b;"))
    }

    @Test("fichiers de tests reconnus")
    func testFiles() {
        for p in ["test/a_test.dart", "src/a.test.ts", "tests/test_a.py", "e2e/largeur.spec.js", "crates/x/tests/it.rs"] {
            #expect(AgentRun.isTestFile(p), "\(p)")
        }
        #expect(!AgentRun.isTestFile("src/main.rs"))
        #expect(!AgentRun.isTestFile("site/style.css"))
        #expect(!AgentRun.isTestFile(".github/workflows/ci.yml"))
    }

    @Test("un résumé qui annonce du travail non fait est refusé une fois")
    func excuse() async {
        let llm = ScriptLLM([
            act("write_file", ["path": "README.md"], "# Titre"),
            act("finish", ["summary": "Fait. Je pourrais aussi ajouter une section."]),
            act("finish", ["summary": "Fait ✅"]),
        ])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Écris le README", checks: false)
        await run.run()
        #expect(llm.last(2).contains("Ton résumé annonce du travail non fait (« Je pourrais »)"))
        #expect(run.summary == "Fait ✅")
    }

    @Test("terminer sans rien faire pour la demande est refusé une fois")
    func nudge() async {
        let llm = ScriptLLM([act("finish", ["summary": "rien"]), act("finish", ["summary": "C'est une question : réponse."])])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Que fait ce dépôt ?")
        await run.run()
        #expect(llm.last(1).contains("Tu termines sans avoir rien fait pour la dernière demande"))
        #expect(run.summary == "C'est une question : réponse.")
    }

    // MARK: - Dart qui ne compile pas

    static let written = #"""

    String formatDuree(Duration d) {
      final int hours = d.inHours;
      final int minutes = d.inMinutes % 60;
      if (hours > 0) {
        return '${hours} h ${minutes.toString().padLeft(2, \'0\')}';
      }
      return '${d.inSeconds} s';
    }

    """#

    static let fixed = #"""

    String formatDuree(Duration d) {
      final int hours = d.inHours;
      final int minutes = d.inMinutes % 60;
      if (hours > 0) {
        return '$hours h ${minutes.toString().padLeft(2, '0')}';
      }
      return '${d.inSeconds} s';
    }

    """#

    @Test("« \\'0\\' » dans une interpolation : repéré, avec la ligne")
    func dartError() {
        let e = dartSyntaxError(Self.written)
        #expect(e?.hasPrefix("ligne 6 ") == true)
        #expect(e?.contains("barre oblique inverse") == true)
        #expect(e?.contains("padLeft(2, '0')") == true)
        #expect(dartSyntaxError(Self.fixed) == nil)
    }

    @Test("le Dart valide n'est jamais signalé")
    func dartValid() {
        for ok in [
            #"final a = 'l\'eau'; final b = "a \" b";"#,
            #"final r = r'C:\dossier\'; final s = r"\d+";"#,
            "final t = '''\nune 'chaîne' \"longue\"\n''';\n",
            "final u = \"\"\"\n\\\"\"\" ok\n\"\"\";\n",
            #"final v = 'a ${m['k']} ${f('}')} $x';"#,
            #"final w = 'a ${'b ${c("d")}'}';"#,
            "// un commentaire avec ' et \\ et {\nvoid f() {}\n",
            "/* imbriqué /* encore \\ */ fin { */\nvoid g() {}\n",
            "/// doc avec ' et (\nvoid h() => [1, 2].map((e) => {e: e});\n",
            #"final x = '\${pas une interpolation';"#,
            #"final y = "multi" 'ple' r"\";"#,
        ] {
            #expect(dartSyntaxError(ok) == nil, "\(ok)")
        }
    }

    @Test("les erreurs certaines sont repérées")
    func dartErrors() {
        #expect(dartSyntaxError("void f() {\n  print(1);\n")?.contains("jamais fermé") == true)
        #expect(dartSyntaxError("final a = 'oups;\nvoid f() {}\n")?.contains("chaîne jamais fermée") == true)
        #expect(dartSyntaxError("void f() {\n  g(1];\n}\n")?.contains("« ] » ferme « ( » ouvert ligne 2") == true)
        #expect(dartSyntaxError("void f() {}\n}\n")?.hasPrefix("ligne 2 ") == true)
        #expect(dartSyntaxError("final t = '''\nsans fin\n")?.contains("il manque '''") == true)
        #expect(AgentRun.dartSyntaxHint("a.rs", Self.written) == nil)
        #expect(AgentRun.dartSyntaxHint("lib/a.dart", Self.fixed) == nil)
        #expect(AgentRun.dartSyntaxHint("lib/a.dart", Self.written)?.contains("lib/a.dart ne compilera pas, ligne 6") == true)
    }

    func dartRun(_ replies: [String]) -> (AgentRun, ScriptLLM) {
        let llm = ScriptLLM(replies)
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: repoHub(["app/pubspec.yaml": "name: app\n"]), repo: "NEXORA", branch: "master",
                          task: "Ajoute une fonction formatDuree, avec ses tests", checks: false)
        run.specs.append("déjà compris")
        return (run, llm)
    }

    func writeDart(_ content: String) -> String {
        "```json\n" + LooseJSON.string(["tool": "write_file", "args": ["path": "app/lib/utils.dart", "content": content]]) + "\n```"
    }

    @Test("write_file d'un Dart qui ne compile pas : prévenu, et finish refusé (deux fois au plus)")
    func dartInSession() async {
        let (r1, l1) = dartRun([writeDart(Self.written)])
        await r1.run()
        #expect(l1.last(1).contains("enregistré en brouillon"))
        #expect(l1.last(1).contains("app/lib/utils.dart ne compilera pas"))

        let finish = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fait\"}}\n```"
        let (r2, l2) = dartRun([writeDart(Self.written), finish, writeDart(Self.fixed), "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"corrigé\"}}\n```"])
        await r2.run()
        #expect(l2.last(2).contains("Tu ne peux pas terminer"))
        #expect(l2.last(2).contains("ligne 6"))
        #expect(r2.summary == "corrigé")
        #expect(r2.draft("app/lib/utils.dart") == Self.fixed)

        let (r3, l3) = dartRun([writeDart(Self.written), finish, finish, finish])
        await r3.run()
        #expect((0..<l3.count).filter { l3.last($0).contains("Tu ne peux pas terminer") }.count == 2)
        #expect(r3.summary == "fait")
        #expect(r3.finished)
    }

    // MARK: - Tests Rust

    static let cargo = """

    [package]
    name = "nexora-site"
    version = "0.1.0"

    [lib]
    crate-type = ["cdylib", "rlib"]
    name = "nexora_site"

    [[bin]]
    name = "nexora-site"

    """

    static let rustWritten = """

    #[cfg(test)]
    mod tests {
        use crate::slug::title_to_slug;

        #[test]
        fn test_basic() {
            assert_eq!(title_to_slug("Hello World"), "hello-world");
        }
    }

    """

    static let mainRs = """

    fn app() -> App {
        let mut app = App::new();
        app.get("/version", version);
        app
    }

    async fn version(_req: Request) -> String {
        env!("CARGO_PKG_VERSION").to_string()
    }

    #[tokio::main]
    async fn main() {}

    #[cfg(test)]
    mod tests {
        use super::*;
    }

    """

    static let versionTest = """

    use paquets::prelude::*;

    #[tokio::test]
    async fn version_route_returns_version() {
        let client = app().test().await;
        let res = client.get("/version").await;
        assert_eq!(res.status(), 200);
    }

    """

    @Test("crate:: dans un test d'intégration : signalé, avec le bon nom")
    func rustCrate() {
        #expect(AgentRun.rustCrateName(Self.cargo) == "nexora_site")
        #expect(AgentRun.rustCrateName("[package]\nname = \"mon-outil\"\n") == "mon_outil")
        #expect(AgentRun.rustCrateName("[workspace]\n") == nil)
        let hint = AgentRun.rustTestHint("site/tests/slug_test.rs", Self.rustWritten, cargo: Self.cargo)
        #expect(hint?.contains("use crate::slug::title_to_slug;") == true)
        #expect(hint?.contains("« use nexora_site::… »") == true)
        #expect(AgentRun.rustTestHint("tests/slug.rs", "use nexora_site::slug::title_to_slug;\n") == nil)
        #expect(AgentRun.rustTestHint("tests/api.rs", "mod common;\nuse crate::common::serveur;\n") == nil)
        #expect(AgentRun.rustTestHint("src/slug.rs", Self.rustWritten) == nil)
        #expect(AgentRun.rustTestHint("tests/a.rs", "// voir crate::slug\nfn main() {}\n") == nil)
        #expect(AgentRun.rustTestHint("tests/a.py", "crate::slug") == nil)
    }

    @Test("un test de tests/ qui appelle une fonction de main.rs est signalé")
    func rustBin() {
        let hint = AgentRun.rustTestHint("site/tests/version_test.rs", Self.versionTest, cargo: Self.cargo, mainRs: Self.mainRs)
        #expect(hint?.contains("app()") == true)
        #expect(hint?.contains("site/src/main.rs") == true)
        #expect(hint?.contains("#[cfg(test)] mod tests") == true)
        #expect(hint?.contains("delete_file") == true)
        #expect(hint?.contains("version()") == false)
        #expect(AgentRun.rustTestHint("site/tests/a.rs", "use nexora_site::app;\n#[test]\nfn t() { app(); }\n", mainRs: Self.mainRs) == nil)
        #expect(AgentRun.rustTestHint("site/tests/a.rs", "fn app() {}\n#[test]\nfn t() { app(); nexora_site::version(); }\n", mainRs: Self.mainRs) == nil)
        #expect(AgentRun.rustTestHint("site/tests/a.rs", "// app() est dans main.rs\nfn t(c: C) { c.app(); }\n", mainRs: Self.mainRs) == nil)
        #expect(AgentRun.rustTestHint("site/src/a.rs", Self.versionTest, mainRs: Self.mainRs) == nil)
        #expect(AgentRun.rustTestHint("site/tests/a.rs", Self.versionTest) == nil)
    }

    func rustHub(main: String?) -> Routes {
        var files = ["site/Cargo.toml": Self.cargo, "site/src/lib.rs": "pub mod slug;\n"]
        if let main { files["site/src/main.rs"] = main }
        return repoHub(files)
    }

    @Test("write_file d'un test Rust mal placé : le modèle est prévenu tout de suite")
    func rustInSession() async {
        let w1 = "```json\n" + LooseJSON.string(["tool": "write_file", "args": ["path": "site/tests/slug_test.rs", "content": Self.rustWritten]]) + "\n```"
        let llm = ScriptLLM([w1])
        llm.whenEmpty = "```json\n{\"tool\":\"finish\",\"args\":{\"summary\":\"fin\"}}\n```"
        let run = makeRun(llm, hub: rustHub(main: nil), repo: "NEXORA", branch: "master", task: "Ajoute une fonction slug au site, avec ses tests", checks: false)
        run.specs.append("déjà compris")
        await run.run()
        #expect(llm.last(1).contains("enregistré en brouillon"))
        #expect(llm.last(1).contains("test d'intégration Rust"))
        #expect(llm.last(1).contains("use nexora_site::"))

        let w2 = "```json\n" + LooseJSON.string(["tool": "write_file", "args": ["path": "site/tests/version_test.rs", "content": Self.versionTest]]) + "\n```"
        let llm2 = ScriptLLM([w2])
        llm2.whenEmpty = llm.whenEmpty
        let run2 = makeRun(llm2, hub: rustHub(main: Self.mainRs), repo: "NEXORA", branch: "master", task: "Ajoute une route /version au site, avec un test", checks: false)
        run2.specs.append("déjà compris")
        await run2.run()
        #expect(llm2.last(1).contains("enregistré en brouillon"))
        #expect(llm2.last(1).contains("appelle app()"))
        #expect(llm2.last(1).contains("site/src/main.rs"))
    }

    // MARK: - Où en est le travail

    static let tree = ["app/lib/ui/chat/chat_screen.dart", "app/test/chat_stop_test.dart", "site/src/main.rs", "site/tests/pages.rs", "lib/a.py"]

    @Test("où écrire le test d'un fichier")
    func testPath() {
        #expect(AgentRun.testPathFor("app/lib/ui/chat/chat_screen.dart", Self.tree) == "app/test/chat_screen_test.dart")
        #expect(AgentRun.testPathFor("site/src/main.rs", Self.tree) == "site/src/main.rs")
        #expect(AgentRun.testPathFor("src/main.rs", []) == "src/main.rs")
        #expect(AgentRun.testPathFor("site/src/bin/outil.rs", Self.tree + ["site/src/lib.rs"]) == "site/src/bin/outil.rs")
        #expect(AgentRun.testPathFor("site/src/export.rs", Self.tree) == "site/src/export.rs")
        #expect(AgentRun.testPathFor("site/src/contenu.rs", Self.tree + ["site/src/lib.rs"]) == "site/tests/contenu.rs")
        #expect(AgentRun.testPathFor("lib/a.py", Self.tree) == nil)
        #expect(AgentRun.testPathFor("app/lib/x.dart", []) == nil)
    }

    @Test("un agent qui tourne en rond apprend ce qui est fait et qu'il reste le test, et où")
    func circling() async {
        let llm = ScriptLLM()
        llm.dynamic = { n, _, _ in
            if n == 0 {
                return .text(act("write_file", ["path": "app/lib/a.dart", "content": "int a() => 1;\n"]))
            }
            // Puis il cherche sans fin un exemple de test, en alternant.
            return .text(act("search_code", ["query": (n + 1) % 2 == 1 ? "ChatScreen" : "testWidgets", "path": "app/test"]))
        }
        let run = makeRun(llm, hub: repoHub(["app/lib/b.dart": "int b() => 2;\n", "app/test/b_test.dart": "void main() {}\n"]),
                          repo: "nexora", task: "Ajoute la fonction a, avec un test")
        run.specs.append("déjà compris")
        await run.run()
        let circlingNote = (0..<llm.count).map { llm.last($0) }.first { $0.contains("tu tournes en rond") }
        #expect(circlingNote != nil)
        #expect(circlingNote?.contains("OÙ TU EN ES") == true)
        #expect(circlingNote?.contains("app/lib/a.dart") == true)
        #expect(circlingNote?.contains("Il reste le test de app/lib/a.dart") == true)
        #expect(circlingNote?.contains("app/test/a_test.dart") == true)
    }

    @Test("notes de progression : première modification, finish, test Rust dans le module")
    func notes() {
        let run = makeRun(hub: Routes { _ in notFound }, repo: "nexora", task: "x", checks: false)
        #expect(run.progressNote().contains("aucune modification"))
        run.changes.set("a.md", "x")
        #expect(run.progressNote().contains("appelle finish"))

        #expect(AgentRun.addsRustTest("site/src/main.rs", "fn main() {}\n#[cfg(test)]\nmod tests {\n    #[tokio::test]\n    async fn lien() {}\n}\n", "fn main() {}\n"))
        #expect(!AgentRun.addsRustTest("a.rs", "#[test]\nfn t() {}\n", "#[test]\nfn t() {}\n"))
        #expect(!AgentRun.addsRustTest("a.dart", "#[test]", ""))
        #expect(!AgentRun.addsRustTest("a.rs", nil, ""))
        #expect(AgentRun.addsRustTest("n.rs", "#[test] fn t() {}", nil))

        let rust = makeRun(hub: Routes { _ in notFound }, repo: "nexora", task: "x")
        rust.setOriginal("site/src/main.rs", "fn main() {}\n")
        rust.changes.set("site/src/main.rs", "fn main() { lien(); }\n")
        let note = rust.progressNote()
        #expect(note.contains("Il reste le test de site/src/main.rs"))
        #expect(note.contains("avec edit_file dans le module de tests de site/src/main.rs"))
        #expect(!note.contains("site/tests/"))
        rust.changes.set("site/src/main.rs", "fn main() { lien(); }\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn lien() {}\n}\n")
        #expect(rust.progressNote().contains("appelle finish"))
    }

    // MARK: - Suivi de la CI

    @Test("tests GitHub : échec → rapport avec la fin du journal, sans horodatage")
    func ciFailed() async {
        let hub = Routes { c in
            if c.path.hasSuffix("/commits/abc123/check-runs") {
                return (200, LooseJSON.string(["check_runs": [
                    ["id": 7, "name": "tests", "status": "completed", "conclusion": "failure", "html_url": "https://github.com/max/site/actions/runs/1"],
                    ["id": 8, "name": "lint", "status": "completed", "conclusion": "success"],
                ]]))
            }
            if c.path.hasSuffix("/actions/jobs/7/logs") {
                return (200, "2026-11-10T07:00:00.000Z Running tests\n2026-11-10T07:00:01.000Z FAIL somme: expected 3, got 4")
            }
            return (404, "{}")
        }
        let run = makeRun(hub: hub)
        run.commits.append("max/site@abc123")
        let report = await run.watchCi(every: .zero)
        #expect(run.ci["max/site"]?.state == .failed)
        #expect(report?.contains("tests : failure") == true)
        #expect(report?.contains("FAIL somme: expected 3, got 4") == true)
        #expect(report?.contains("2026-11-10T") == false)
    }

    @Test("tests GitHub : tout passe → pas de rapport ; aucun test → signalé")
    func ciPassedOrNone() async {
        let ok = makeRun(hub: Routes { _ in (200, LooseJSON.string(["check_runs": [["id": 1, "name": "tests", "status": "completed", "conclusion": "success"]]])) })
        ok.commits.append("max/site@def456")
        #expect(await ok.watchCi(every: .zero) == nil)
        #expect(ok.ci["max/site"]?.state == .passed)
        #expect(ok.ci["max/site"]?.label.contains("réussis") == true)

        let none = makeRun(hub: Routes { _ in (200, #"{"check_runs":[]}"#) })
        none.commits.append("max/site@0aa")
        #expect(await none.watchCi(every: .zero, noneAfter: .zero) == nil)
        #expect(none.ci["max/site"]?.state == CiState.none)
    }

    @Test("journal d'un job : l'adresse signée est suivie sans le jeton")
    func jobLogRedirect() async {
        let hub = Routes(headers: { c in
            if c.path.hasSuffix("/actions/jobs/5/logs") { return (302, "", ["location": "https://logs.example/signe"]) }
            if c.path == "//logs.example/signe" { return (200, "2026-11-10T07:00:00.000Z ligne 1\nligne 2", [:]) }
            return (404, "{}", [:])
        })
        let log = await GitHubAPI(token: "t", transport: hub).jobLog("max", "site", jobId: 5, lines: 1)
        #expect(log == "ligne 2")
    }

    @Test("boucle CI : envoi sur une branche avec pull request, échec puis vert, fusion")
    func ciLoop() async {
        final class State: @unchecked Sendable {
            var round = 0
            var pushed: [String] = []
            var merged: [String] = []
            var deleted: [String] = []
            var pulls: [String] = []
        }
        let s = State()
        let lock = NSLock()
        let hub = Routes { c in
            lock.withLock { () -> (Int, String) in
                let p = c.path
                if p.contains("/git/ref/heads/") { return (200, #"{"object":{"sha":"p0"}}"#) }
                if p.contains("/git/commits/") && c.method == "GET" { return (200, #"{"tree":{"sha":"t0"}}"#) }
                if p.hasSuffix("/git/trees") { return (201, #"{"sha":"t1"}"#) }
                if p.hasSuffix("/git/commits") {
                    s.round += 1
                    return (201, "{\"sha\":\"c\(s.round)\"}")
                }
                if p.contains("/git/refs/heads/") && c.method == "PATCH" {
                    s.pushed.append(p.components(separatedBy: "/git/refs/heads/").last!)
                    return (200, "{}")
                }
                if p.contains("/git/refs/heads/") && c.method == "DELETE" {
                    s.deleted.append(p.components(separatedBy: "/git/refs/heads/").last!)
                    return (204, "")
                }
                if p.hasSuffix("/pulls/1/merge") && c.method == "PUT" {
                    s.merged.append("\(c.body["merge_method"] ?? ""):\(c.body["commit_title"] ?? "")")
                    return (200, #"{"merged":true}"#)
                }
                if p.hasSuffix("/git/refs") { return (201, LooseJSON.string(["ref": c.body["ref"] ?? ""])) }
                if p.hasSuffix("/pulls") {
                    s.pulls.append(c.body["head"] as? String ?? "")
                    return (201, LooseJSON.string(["id": 1, "number": 1, "title": "t", "html_url": "https://github.com/max/site/pull/1", "state": "open", "user": ["login": "max"]]))
                }
                if p.contains("/check-runs") {
                    let ok = p.contains("/commits/c2/")
                    return (200, LooseJSON.string(["check_runs": [["id": 9, "name": "tests", "status": "completed", "conclusion": ok ? "success" : "failure"]]]))
                }
                if p.hasSuffix("/actions/jobs/9/logs") { return (200, "Error: somme(1, 2) vaut 4") }
                if p.contains("/git/trees/") { return (200, #"{"tree":[]}"#) }
                return notFound
            }
        }
        let run = makeRun(hub: hub, task: "Ajoute une fonction somme")
        run.changes.set("lib/somme.dart", "int somme(a, b) => a + b + 1;\n")
        run.commitMessage = "Somme"
        let report = await run.shipForCi(every: .zero)
        #expect(report?.contains("Error: somme(1, 2) vaut 4") == true)
        #expect(run.ciNote.contains("l'agent corrige"))
        #expect(s.pulls.count == 1)
        let branch = s.pulls.first ?? ""
        #expect(branch.hasPrefix("nexora/"))
        #expect(s.pushed == [branch])

        run.changes.set("lib/somme.dart", "int somme(a, b) => a + b;\n")
        #expect(await run.shipForCi(every: .zero) == nil)
        #expect(s.pushed == [branch, branch])
        #expect(s.pulls.count == 1)
        #expect(run.ciRounds == 2)
        #expect(s.merged == ["squash:Somme"])
        #expect(run.ciNote.contains("fusionné dans main"))
        #expect(run.merged == ["max/site → main"])
        #expect(s.deleted == [branch])
        #expect(run.heads.isEmpty)
        #expect(run.pulls.isEmpty)
    }
}
