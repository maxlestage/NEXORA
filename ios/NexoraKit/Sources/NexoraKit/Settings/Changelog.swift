import Foundation

/// Une version publiée et ses changements, lus dans `nouveautes.md` (la même source
/// que la page Nouveautés du site et que l'app Flutter).
public struct Release: Sendable, Hashable, Identifiable {
    public let version: String
    public let date: String
    public let title: String
    public let points: [String]

    public var id: String { version }

    public init(_ version: String, _ date: String, _ title: String, _ points: [String]) {
        self.version = version
        self.date = date
        self.title = title
        self.points = points
    }
}

/// La nature d'un changement, pour l'étiqueter.
public enum ChangeKind: String, Sendable, CaseIterable, Identifiable {
    case nouveau, ameliore, corrige

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .nouveau: "Nouveau"
        case .ameliore: "Amélioré"
        case .corrige: "Corrigé"
        }
    }
}

/// Les nouveautés de chaque version (`data/changelog.dart`).
public enum Changelog {
    /// `## 2.0.0 — 8 novembre 2026 — Résumé` puis des lignes `- point`.
    public static func parse(_ md: String) -> [Release] {
        var out: [Release] = []
        var version: String?
        var date = ""
        var title = ""
        var points: [String] = []
        func push() {
            if let version { out.append(Release(version, date, title, points)) }
        }
        for raw in md.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("## ") {
                push()
                let parts = String(line.dropFirst(3)).components(separatedBy: " — ")
                version = parts[0].trimmingCharacters(in: .whitespaces)
                date = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                title = parts.count > 2 ? parts[2...].joined(separator: " — ").trimmingCharacters(in: .whitespaces) : ""
                points = []
            } else if line.hasPrefix("- "), version != nil {
                points.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        push()
        return out
    }

    /// « Nouveau », « Amélioré » ou « Corrigé », d'après la façon dont le point est
    /// écrit (« Corrigé : … », « Nouveau : … », « … ne déborde plus »…).
    public static func kind(of point: String) -> ChangeKind {
        let p = point.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if p.range(of: "^(corrig|réparé|bug)", options: .regularExpression) != nil { return .corrige }
        if p.range(of: "^(nouveau|nouvelle|ajout|arrivée)", options: .regularExpression) != nil { return .nouveau }
        return .ameliore
    }

    /// Le point sans son étiquette écrite (« Corrigé : », « Nouveau : »).
    public static func withoutTag(_ point: String) -> String {
        var t = point
        if let r = t.range(of: #"^(Corrigé|Corrigés|Nouveau|Nouvelle|Amélioré|Améliorée)\s*:\s*"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        // Une majuscule au début, une fois l'étiquette retirée.
        guard let first = t.first else { return t }
        return first.uppercased() + t.dropFirst()
    }

    /// Compare deux numéros de version (« 2.2.10 » > « 2.2.9 ») : négatif, 0 ou positif.
    public static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ v: String) -> [Int] {
            (v.components(separatedBy: "+").first ?? "").components(separatedBy: ".").map { Int($0) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// Les versions publiées depuis `seen` (la plus récente d'abord) ; au moins la
    /// dernière.
    public static func since(_ all: [Release], seen: String?) -> [Release] {
        guard let first = all.first else { return [] }
        guard let seen else { return [first] }
        let out = all.filter { compare($0.version, seen) > 0 }
        return out.isEmpty ? [first] : out
    }

    /// Le résumé d'une fenêtre « Quoi de neuf » : « 3 versions · 2 nouveaus · 5 corrigés ».
    public static func summary(_ releases: [Release]) -> String {
        var parts: [String] = []
        if releases.count > 1 { parts.append("\(releases.count) versions") }
        let points = releases.flatMap(\.points)
        for k in ChangeKind.allCases {
            let n = points.filter { kind(of: $0) == k }.count
            if n > 0 { parts.append("\(n) \(k.label.lowercased())\(n > 1 ? "s" : "")") }
        }
        return parts.joined(separator: " · ")
    }

    /// Faut-il montrer la fenêtre « Quoi de neuf » ? Pas à la première installation
    /// (accueil pas encore passé), ni deux fois pour la même version.
    public static func shouldShowWhatsNew(seen: String?, current: String, onboarded: Bool) -> Bool {
        if seen == current { return false }
        return !(seen == nil && !onboarded)
    }
}
