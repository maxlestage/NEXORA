import Foundation
import Testing
@testable import NexoraKit

/// La version de l'app iOS est la même partout : projet Xcode, réglages, nouveautés.
@Suite("Version de l'app iOS")
struct IOSVersionTests {
    /// Le dossier ios/ (ce fichier est dans ios/NexoraKit/Tests/NexoraKitTests).
    static let ios = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func read(_ path: String) throws -> String {
        try String(contentsOf: ios.appendingPathComponent(path), encoding: .utf8)
    }

    static func first(_ text: String, _ pattern: String) -> String? {
        guard let r = text.range(of: pattern, options: .regularExpression) else { return nil }
        return text[r].components(separatedBy: "\"").dropFirst().first
    }

    @Test("project.yml, SettingsStore.appVersion et la première nouveauté iOS concordent")
    func sameVersion() throws {
        let project = try Self.read("project.yml")
        let settings = try Self.read("Nexora/State/SettingsStore.swift")
        let notes = try Self.read("Nexora/Resources/nouveautes-ios.md")
        let marketing = try #require(Self.first(project, #"MARKETING_VERSION: "[0-9.]+""#))
        let app = try #require(Self.first(settings, #"static let appVersion = "[0-9.]+""#))
        let release = try #require(Changelog.parse(notes).first)
        #expect(marketing == app)
        #expect(release.version == app)
        #expect(!release.points.isEmpty)
        #expect(app.hasPrefix("3."))
    }

    @Test("nouveautés iOS et communes réunies, la plus récente d'abord")
    func merged() {
        let ios = Changelog.parse("## 3.0.0 — 11 novembre 2026 — Natif\n- Nouveau : a\n")
        let common = Changelog.parse("## 2.2.75 — 11 novembre 2026 — X\n- b\n\n## 2.2.74 — 11 novembre 2026 — Y\n- c\n")
        let all = Changelog.merged(common, ios)
        #expect(all.map(\.version) == ["3.0.0", "2.2.75", "2.2.74"])
        #expect(Changelog.since(all, seen: "2.2.74").map(\.version) == ["3.0.0", "2.2.75"])
    }
}
