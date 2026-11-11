import Foundation

/// Une comparaison ligne à ligne, pour relire un brouillon avant de le valider.
public enum DiffKind: String, Sendable {
    case same, added, removed
}

public struct DiffLine: Sendable, Hashable {
    public let kind: DiffKind
    public let text: String
    /// Numéro de la ligne dans l'ancienne et la nouvelle version.
    public let oldNo: Int?
    public let newNo: Int?

    public init(_ kind: DiffKind, _ text: String, oldNo: Int? = nil, newNo: Int? = nil) {
        self.kind = kind
        self.text = text
        self.oldNo = oldNo
        self.newNo = newNo
    }
}

public struct DiffResult: Sendable {
    public let lines: [DiffLine]
    /// Fichiers trop grands : seules les premières différences sont calculées.
    public let truncated: Bool

    public init(_ lines: [DiffLine], truncated: Bool = false) {
        self.lines = lines
        self.truncated = truncated
    }

    public var added: Int { lines.filter { $0.kind == .added }.count }
    public var removed: Int { lines.filter { $0.kind == .removed }.count }
}

/// Compare deux textes ligne à ligne (plus longue sous-suite commune, après avoir
/// retiré le début et la fin identiques).
public func lineDiff(_ before: String?, _ after: String?) -> DiffResult {
    let a = before == nil || before!.isEmpty ? [] : diffLines(before!)
    let b = after == nil || after!.isEmpty ? [] : diffLines(after!)
    var start = 0
    while start < a.count && start < b.count && a[start] == b[start] { start += 1 }
    var endA = a.count, endB = b.count
    while endA > start && endB > start && a[endA - 1] == b[endB - 1] {
        endA -= 1
        endB -= 1
    }
    var out = (0..<start).map { DiffLine(.same, a[$0], oldNo: $0 + 1, newNo: $0 + 1) }
    let midA = Array(a[start..<endA])
    let midB = Array(b[start..<endB])
    var truncated = false
    if midA.count * midB.count > 4_000_000 {
        // Trop grand pour une comparaison fine : tout l'ancien, puis tout le nouveau.
        truncated = true
        for i in 0..<midA.count { out.append(DiffLine(.removed, midA[i], oldNo: start + i + 1)) }
        for j in 0..<midB.count { out.append(DiffLine(.added, midB[j], newNo: start + j + 1)) }
    } else {
        let n = midA.count, m = midB.count
        // lcs[i][j] : longueur de la plus longue sous-suite commune de midA[i:] et midB[j:].
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = midA[i] == midB[j]
                        ? lcs[i + 1][j + 1] + 1
                        : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1])
                }
            }
        }
        var i = 0, j = 0
        while i < n || j < m {
            if i < n && j < m && midA[i] == midB[j] {
                out.append(DiffLine(.same, midA[i], oldNo: start + i + 1, newNo: start + j + 1))
                i += 1
                j += 1
            } else if i < n && (j == m || lcs[i + 1][j] >= lcs[i][j + 1]) {
                // Une ligne remplacée : l'ancienne d'abord, puis la nouvelle.
                out.append(DiffLine(.removed, midA[i], oldNo: start + i + 1))
                i += 1
            } else {
                out.append(DiffLine(.added, midB[j], newNo: start + j + 1))
                j += 1
            }
        }
    }
    for k in 0..<(a.count - endA) {
        out.append(DiffLine(.same, a[endA + k], oldNo: endA + k + 1, newNo: endB + k + 1))
    }
    return DiffResult(out, truncated: truncated)
}

private func diffLines(_ s: String) -> [String] {
    var l = s.replaceAll("\r\n", "\n").dsplit("\n")
    if let last = l.last, last.isEmpty { l.removeLast() }
    return l
}

/// Ne garde que les changements et `context` lignes autour (le reste est replié :
/// `nil` pour « … lignes identiques »).
public func withContext(_ lines: [DiffLine], context: Int = 3) -> [DiffLine?] {
    var keep = [Bool](repeating: false, count: lines.count)
    for i in 0..<lines.count where lines[i].kind != .same {
        for k in (i - context)...(i + context) where k >= 0 && k < lines.count {
            keep[k] = true
        }
    }
    var out: [DiffLine?] = []
    var skipping = false
    for i in 0..<lines.count {
        if keep[i] {
            out.append(lines[i])
            skipping = false
        } else if !skipping {
            out.append(nil)
            skipping = true
        }
    }
    return out
}
