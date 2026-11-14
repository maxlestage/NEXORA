import Foundation
import Testing
@testable import NexoraKit

@Suite("Connexion à GitHub et nouveau dépôt")
struct GitHubSignInDisplayTests {
    @Test func codeLuParVoiceOver() {
        #expect(GitHubSignInDisplay.spokenCode("ABCD-1234") == "A B C D, 1 2 3 4")
        #expect(GitHubSignInDisplay.spokenCode("WDJB") == "W D J B")
        #expect(GitHubSignInDisplay.intro.count < 90)
    }

    @Test func conseilJeton() {
        #expect(GitHubSignInDisplay.tokenHint("") == nil)
        #expect(GitHubSignInDisplay.tokenHint("  ghp_abc123\n") == nil)
        #expect(GitHubSignInDisplay.tokenHint("github_pat_11AA") == nil)
        #expect(GitHubSignInDisplay.tokenHint(String(repeating: "a1", count: 20)) == nil)
        #expect(GitHubSignInDisplay.tokenHint("ghp_abc def")?.contains("espace") == true)
        #expect(GitHubSignInDisplay.tokenHint("motdepasse")?.contains("ghp_") == true)
    }

    @Test func nomDuDepot() {
        #expect(ReposDisplay.repoName("Mon Projet été !") == "Mon-Projet-ete")
        #expect(ReposDisplay.repoName("nexora_app.v2") == "nexora_app.v2")
        #expect(ReposDisplay.repoName("  a -- b  ") == "a-b")
        #expect(ReposDisplay.repoNameProblem("") == "Indiquez un nom.")
        #expect(ReposDisplay.repoNameProblem("!!!") != nil)
        #expect(ReposDisplay.repoNameProblem("..") != nil)
        #expect(ReposDisplay.repoNameProblem(String(repeating: "a", count: 101)) != nil)
        #expect(ReposDisplay.repoNameProblem("site") == nil)
        #expect(ReposDisplay.repoNameNote("site") == nil)
        #expect(ReposDisplay.repoNameNote("Mon site") == "Sera créé sous le nom « Mon-site ».")
    }
}
