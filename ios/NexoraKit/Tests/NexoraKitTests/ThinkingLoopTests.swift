import Foundation
import Testing
@testable import NexoraKit

/// Port de Flutter 2.2.86 : une réflexion qui radote est coupée tout de suite.
@MainActor
@Suite("Réflexion qui tourne en rond")
struct ThinkingLoopTests {
    static let normal =
        "We added util file and test. Need to ensure import path correct: "
        + "package name is nexora. In test, import "
        + "'package:nexora/utils/string_utils.dart'; correct. Need to ensure utils "
        + "folder exists. We created file. Need to add to pubspec? Not needed.\n\n"
        + "Edge case: keep calculation: (max-3)/2 floor. For max=10, keep=3. So "
        + "start 3 chars, end 3 chars. Result length 3+1+3=7 <=10. Good.\n"
        + "For max=4, keep=0. So start empty, end empty, result one char.\n"
        + "Now ensure the test file compiles. It uses expect and equals.\n"
        + "Then call finish with a short summary of what was done."

    @Test("un motif répété des centaines de fois est repéré")
    func pattern() {
        // Vu en essai réel avec GPT-OSS.
        let loop = "Also test expects '………' for 3? Should be '…' repeated 3: "
            + Array(repeating: "'…' '…' '…' =>", count: 60).joined(separator: " ")
        #expect(thinkingLoops(loop))
        #expect(thinkingLoops(Self.normal + "\n" + String(repeating: "abc ", count: 120)))
    }

    @Test("la même phrase ligne après ligne est repérée")
    func sameLine() {
        let line = "Now ensure that the test file uses 'const s = 'very long string';' Good."
        #expect(thinkingLoops(Self.normal + "\n\n" + String(repeating: line + "\n\n", count: 8) + "Now ensure"))
        // Quelques répétitions seulement : rien.
        #expect(!thinkingLoops(Self.normal + "\n\n" + String(repeating: line + "\n\n", count: 3) + "Then"))
    }

    @Test("une réflexion normale, du code ou un texte court passent")
    func normalPasses() {
        #expect(!thinkingLoops(Self.normal))
        #expect(!thinkingLoops("..."))
        let code = "String truncateMiddle(String s, int max) {\n"
            + "  if (max <= 0) {\n    return '';\n  }\n"
            + "  if (s.length <= max) {\n    return s;\n  }\n"
            + "  final half = (max - 1) ~/ 2;\n"
            + "  final start = s.substring(0, half);\n"
            + "  final end = s.substring(s.length - (max - 1 - half));\n"
            + "  return '$start…$end';\n}\n"
        #expect(!thinkingLoops(Self.normal + "\n" + code + code))
        // Une ligne de séparation courte ne compte pas.
        #expect(!thinkingLoops(Self.normal + "\n" + String(repeating: "---\n", count: 12) + "fin"))
    }

    @Test("sans effet sur les fichiers Swift du dépôt (pris comme réflexion)")
    func realFiles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(files.count > 50)
        for f in files {
            let s = try String(contentsOf: f, encoding: .utf8)
            // Lu comme en flux : vérifié tous les 400 caractères, comme pendant la réponse.
            let u = Array(s.utf16)
            var at = 400
            while at <= u.count {
                let flagged = thinkingLoops(String(decoding: u[..<at], as: UTF16.self))
                #expect(!flagged, "\(f.lastPathComponent) à \(at)")
                if flagged { break }
                at += 400
            }
        }
    }

    @Test("la réponse est coupée sans attendre la suite du flux")
    func clientCuts() async throws {
        let p = Catalog.providers.first { $0.id == "groq" }!
        let llm = ScriptLLM(replies: [.think([Self.normal] + Array(repeating: " '…' '…' '…' =>", count: 400), "trop tard")])
        let out = try await LLMClient(transport: llm).complete(provider: p, apiKey: "k", model: "m", messages: [LLMMessage("user", "Ajoute une fonction")])
        #expect(out.text.isEmpty)
        #expect(!isCutStop("loop"))
        // Une réponse qui suit une réflexion normale est gardée.
        let ok = ScriptLLM(replies: [.think((0..<20).map { String(Self.normal.prefix(40 + $0)) + "\n" }, "Voici")])
        #expect(try await LLMClient(transport: ok).complete(provider: p, apiKey: "k", model: "m", messages: [LLMMessage("user", "Bonjour")]).text == "Voici")
    }

    @Test("l'agent relance aussitôt avec une réflexion courte")
    func agentRetries() async {
        let done = NexoraKitTests.act(["tool": "finish", "args": ["summary": "Fait"]])
        let wrong = NexoraKitTests.act(["tool": "finish", "args": ["summary": "Trop tard"]])
        let loop = Reply.think([Self.normal] + Array(repeating: " '…' '…' '…' =>", count: 400), wrong)
        let llm = ScriptLLM(replies: [loop, .text(done), .text(done)])
        let run = makeRun(llm, hub: Routes { _ in (200, #"{"tree":[]}"#) }, task: "Dis bonjour", checks: false)
        await run.run()
        // La réponse venue après la boucle n'est pas prise : relance « calme ».
        #expect(run.summary == "Fait")
        #expect(llm.body(1)["temperature"] as? Double == 0.7)
    }
}
