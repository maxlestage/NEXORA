import Foundation
import Testing
@testable import NexoraKit

/// Une fermeture oubliée juste avant une autre (port de Flutter 2.2.90).
@Suite struct MismatchedClosersTests {
    @Test func accoladeDeLActionOubliee() {
        // Cas réel : « }]} » au lieu de « }}]} » ; l'écriture était perdue.
        let reply = "```json\n"
            + #"{"actions":[{"tool":"repo_browser.write_file","args":{"path":"#
            + #""app/test/edit_and_resend_test.dart","content":"void main() {\n"#
            + #"  final l = [1, 2];\n  expect(l[0], 1);\n}\n"}]}"# + "\n```"
        let calls = parseToolCalls(reply)
        #expect(calls.count == 1)
        #expect(calls.first?.tool == "write_file")
        #expect(calls.first?.args["path"] as? String == "app/test/edit_and_resend_test.dart")
        #expect(calls.first?.args["content"] as? String == "void main() {\n  final l = [1, 2];\n  expect(l[0], 1);\n}\n")
    }

    @Test func crochetDeLaListeOublie() {
        let reply = "```json\n" + #"{"actions":[{"tool":"read_file","args":{"path":"a.dart"}}}"# + "\n```"
        let calls = parseToolCalls(reply)
        #expect(calls.count == 1)
        #expect(calls.first?.tool == "read_file")
        #expect(calls.first.map { same($0.args, ["path": "a.dart"]) } == true)
    }

    @Test func chainesIntactes() {
        let j = LooseJSON.decodeLoose(#"{"a": [{"b": "x]}y"]}"#)
        #expect(j.map { same($0, ["a": [["b": "x]}y"]]]) } == true)
    }

    @Test func virguleFinale() {
        let j = LooseJSON.decodeLoose(#"{"a": [{"b": 1,]}"#)
        #expect(j.map { same($0, ["a": [["b": 1]]]) } == true)
    }

    @Test func jsonCorrectInchange() {
        let ok = #"{"actions":[{"tool":"read_file","args":{"path":"a"}}]}"#
        #expect(LooseJSON.decodeLoose(ok).map { same($0, ["actions": [["tool": "read_file", "args": ["path": "a"]]]]) } == true)
    }

    @Test func fermetureSansOuverture() {
        #expect(LooseJSON.decodeLoose(#"{"a": 1]"#) == nil)
    }
}
