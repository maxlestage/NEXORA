import Testing
@testable import NexoraKit

@Suite struct RepoDisplayTests {
    @Test func branchOptionsDefaultFirstSortedUnique() {
        let list = RepoDisplay.branchOptions(["zeta", "main", "Alpha", "zeta", ""], defaultBranch: "main", current: "main")
        #expect(list == ["main", "Alpha", "zeta"])
        // Liste pas encore chargée : la branche par défaut et celle choisie restent proposées.
        #expect(RepoDisplay.branchOptions([], defaultBranch: "main", current: "feature") == ["main", "feature"])
    }

    @Test func branchNoticeOnlyOffDefault() {
        #expect(RepoDisplay.branchNotice(current: "main", defaultBranch: "main") == nil)
        #expect(RepoDisplay.branchNotice(current: "feature/x", defaultBranch: "main") == "Branche feature/x")
        #expect(RepoDisplay.backLabel(defaultBranch: "main") == "Revenir sur main")
        #expect(RepoDisplay.menuAccessibility(current: "dev") == "Plus d'options, branche dev")
    }
}
