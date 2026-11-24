import Foundation

// Les tournures que `cargo clippy -- -D warnings` refuse et que le modèle écrit
// souvent. Port de Flutter 2.2.102.

/// Un nombre entier non signé écrit dans le code (`199`, `1_000`, `8usize`).
private let clippyUintLit = #"(\d[\d_]*)(?:u(?:8|16|32|64|128|size))?(?![\w.])"#

/// Une valeur : `mots`, `self.total`, `v.len()`, `t.split_whitespace().count()`.
private let clippyOperand = #"([A-Za-z_]\w*(?:\.\w+(?:\(\))?)*)"#

/// Un nombre (entier ou décimal, négatif ou non) écrit dans le code.
private let clippyNumLit = #"(-?\d[\d_]*(?:\.\d[\d_]*)?(?:[uif](?:8|16|32|64|128|size))?)(?![\w.])"#

/// Avant la parenthèse ouvrante : ni un appel (« f( »), ni une macro (« m!( »), ni
/// « * » ou « / » qui changeraient l'ordre des calculs. (ICU veut un regard arrière
/// borné : 40 espaces au plus, comme « \s* » en pratique.)
private let clippyOpen = #"(?<![\w!\])>])(?<![*/%]\s{0,40})\(\s*"#
private let clippyAfter = #"(?![\w.(])"#
private let clippyVar = #"(?<![\w.])([A-Za-z_]\w*)(?![\w.(])"#

private enum ClippyRe {
    static let fnHead = DRegex(#"\bfn\s+\w+"#)
    static let constFn = DRegex(#"\bconst\s+(?:unsafe\s+)?fn\b"#)
    static let constItem = DRegex(#"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:const|static)\s+\w+\s*:"#)
    static let ceilLit = [
        DRegex(clippyOpen + clippyOperand + #"\s*\+\s*"# + clippyUintLit + #"\s*\)\s*/\s*"# + clippyUintLit),
        DRegex(clippyOpen + clippyUintLit + #"\s*\+\s*"# + clippyOperand + #"\s*\)\s*/\s*"# + clippyUintLit),
    ]
    static let ceilVar = [
        DRegex(clippyOpen + clippyOperand + #"\s*\+\s*"# + clippyOperand + #"\s*-\s*1\s*\)\s*/\s*"#
            + clippyOperand + clippyAfter),
        DRegex(clippyOpen + clippyOperand + #"\s*\+\s*\(\s*"# + clippyOperand + #"\s*-\s*1\s*\)\s*\)\s*/\s*"#
            + clippyOperand + clippyAfter),
    ]
    static let within: [(DRegex, Int)] = [
        // x >= 1 && x <= 10
        (DRegex(clippyVar + #"\s*>=\s*"# + clippyNumLit + #"\s*&&\s*"# + clippyVar + #"\s*(<=?)\s*"# + clippyNumLit), 0),
        // 1 <= x && x <= 10
        (DRegex(clippyNumLit + #"\s*<=\s*"# + clippyVar + #"\s*&&\s*"# + clippyVar + #"\s*(<=?)\s*"# + clippyNumLit), 1),
        // x <= 10 && x >= 1
        (DRegex(clippyVar + #"\s*(<=?)\s*"# + clippyNumLit + #"\s*&&\s*"# + clippyVar + #"\s*>=\s*"# + clippyNumLit), 2),
    ]
    static let outside = DRegex(clippyVar + #"\s*<\s*"# + clippyNumLit + #"\s*\|\|\s*"# + clippyVar
        + #"\s*(>=?)\s*"# + clippyNumLit)
    static let deniesWarnings = DRegex(#"-D\s*warnings|-D\s*clippy::"#)
}

/// Les tournures que `cargo clippy -- -D warnings` refuse dans les lignes de [code]
/// absentes de [old] (le fichier d'origine n'est jamais visé). Essai réel : pour
/// « ajoute temps_de_lecture() (200 mots par minute, arrondi au supérieur) », le
/// modèle écrivait « (mots + 199) / 200 », que clippy refuse (manual_div_ceil) : la
/// CI du site aurait échoué.
///
/// Prudent, d'après le vrai clippy : l'arrondi au supérieur seulement quand la
/// valeur n'est pas déclarée signée ; l'intervalle seulement avec une variable
/// simple et deux bornes écrites en chiffres, jamais dans une `const fn`, ni quand
/// `&&` ou `||` autour changent le sens. Rend « ligne N : … » pour chaque ligne visée.
public func rustClippyProblems(_ code: String, old: Set<String> = []) -> [String] {
    let bareUnits = rustBareCode(code)
    let bare = String(utf16CodeUnits: bareUnits, count: bareUnits.count)
    let lines = code.dsplit("\n")
    let bareLines = bare.dsplit("\n")
    var out: [String] = []
    var inConstFn = false
    let num = #"[if](?:8|16|32|64|128|size)"#
    func signed(_ operand: String) -> Bool {
        let name = DRegex.escape(operand.dsplit(".").first ?? operand)
        return DRegex(
            #"\b"# + name + #"\s*:\s*&?\s*(?:mut\s+)?"# + num + #"\b|"#
                + #"\b"# + name + #"\s*=[^;\n]*\bas\s+"# + num + #"\b|"#
                + #"\b"# + name + #"\s*=\s*-?\d[\d_.]*(?:"# + num + #")?\s*;"#
        ).hasMatch(bare)
    }
    func int(_ s: String?) -> Int? { Int((s ?? "").replacingOccurrences(of: "_", with: "")) }

    var i = 0
    while i < bareLines.count && i < lines.count {
        defer { i += 1 }
        let b = bareLines[i]
        if ClippyRe.fnHead.hasMatch(b) { inConstFn = ClippyRe.constFn.hasMatch(b) }
        if old.contains(lines[i]) { continue }
        var found: [String] = []
        for (k, re) in ClippyRe.ceilLit.enumerated() {
            for m in re.allMatches(b) {
                let x = (k == 0 ? m[1] : m[2]) ?? ""
                guard let add = int(k == 0 ? m[2] : m[1]), let div = int(m[3]) else { continue }
                if div < 2 || add != div - 1 || signed(x) { continue }
                found.append("« \(m.text.trimmingCharacters(in: .whitespaces)) » arrondit au supérieur à la main "
                    + "(clippy::manual_div_ceil) : écris « \(x).div_ceil(\(div)) »")
            }
        }
        for re in ClippyRe.ceilVar {
            for m in re.allMatches(b) {
                guard let x = m[1], let n = m[2], n == m[3], !signed(x) else { continue }
                found.append("« \(m.text.trimmingCharacters(in: .whitespaces)) » arrondit au supérieur à la main "
                    + "(clippy::manual_div_ceil) : écris « \(x).div_ceil(\(n)) »")
            }
        }
        // contains n'est pas utilisable dans une constante ni une const fn.
        if !inConstFn && !ClippyRe.constItem.hasMatch(b) {
            for (re, form) in ClippyRe.within {
                for m in re.allMatches(b) {
                    let g = (1...5).map { m[$0] ?? "" }
                    let (x, x2, lo, op, hi): (String, String, String, String, String) = switch form {
                    case 0: (g[0], g[2], g[1], g[3], g[4])
                    case 1: (g[1], g[2], g[0], g[3], g[4])
                    default: (g[0], g[3], g[4], g[1], g[2])
                    }
                    if x != x2 { continue }
                    let range = op == "<=" ? "\(lo)..=\(hi)" : "\(lo)..\(hi)"
                    found.append("« \(m.text.trimmingCharacters(in: .whitespaces)) » vérifie un intervalle à la main "
                        + "(clippy::manual_range_contains) : écris « (\(range)).contains(&\(x)) »")
                }
            }
            for m in ClippyRe.outside.allMatches(b) {
                guard let x = m[1], x == m[3] else { continue }
                // « a && x < 1 || x > 9 » ou « x < 1 || x > 9 && a » : clippy ne voit
                // pas d'intervalle (les && sont calculés d'abord).
                if b.sub(0, m.start).trimRight().endsWith("&&") || b.sub(m.end).trimLeft().startsWith("&&") {
                    continue
                }
                let lo = m[2] ?? "", hi = m[5] ?? ""
                let range = m[4] == ">" ? "\(lo)..=\(hi)" : "\(lo)..\(hi)"
                found.append("« \(m.text.trimmingCharacters(in: .whitespaces)) » vérifie un intervalle à la main "
                    + "(clippy::manual_range_contains) : écris « !(\(range)).contains(&\(x)) »")
            }
        }
        for f in found { out.append("ligne \(i + 1) : \(f)") }
    }
    return out
}

extension AgentRun {
    /// Un workflow qui passe clippy en refusant ses avertissements
    /// (`cargo clippy … -- -D warnings`, ou `RUSTFLAGS: -Dwarnings`).
    public nonisolated static func clippyDeniesWarnings(_ workflow: String) -> Bool {
        workflow.contains("cargo clippy") && ClippyRe.deniesWarnings.hasMatch(workflow)
    }

    /// L'avertissement pour les tournures que clippy refusera dans les lignes écrites
    /// par l'agent (celles du fichier d'origine ne comptent pas), ou `nil`. Les
    /// lignes déjà dans [skip] (`chemin:texte`) ne sont pas répétées ; celles
    /// signalées y sont ajoutées.
    public nonisolated static func rustClippyHint(_ path: String, _ text: String, before: String? = nil,
                                                  skip: inout Set<String>) -> String? {
        if !path.hasSuffix(".rs") { return nil }
        let old = Set(before?.dsplit("\n") ?? [])
        var found: [String] = []
        for f in rustClippyProblems(text, old: old) {
            let key = path + ":" + f.sub(f.indexOf(" : ") + 3)
            if skip.insert(key).inserted { found.append(f) }
        }
        if found.isEmpty { return nil }
        return "\n\nATTENTION : la CI de ce dépôt passe « cargo clippy » en refusant ses "
            + "avertissements (-D warnings) et échouera sur \(path) :\n"
            + found.prefix(5).joined(separator: "\n") + "\n"
            + "Corrige maintenant avec edit_file (même résultat, écrit comme clippy le demande)."
    }

    /// Sans mémoire des avertissements déjà donnés (tests, appels isolés).
    public nonisolated static func rustClippyHint(_ path: String, _ text: String, before: String? = nil) -> String? {
        var skip: Set<String> = []
        return rustClippyHint(path, text, before: before, skip: &skip)
    }

    /// Quand la CI du dépôt refuse les avertissements de clippy, les tournures qu'il
    /// refusera dans les lignes écrites par l'agent (une fois chacune).
    func clippyPitfalls(_ p: String, _ text: String) async -> String {
        guard p.hasSuffix(".rs"), await checksClippy(p) else { return "" }
        let before: String? = (try? await original(p)) ?? nil
        return Self.rustClippyHint(p, text, before: before, skip: &clippyWarned) ?? ""
    }

    /// La CI du dépôt de [p] passe-t-elle clippy en refusant ses avertissements ?
    func checksClippy(_ p: String) async -> Bool {
        guard let where_ = resolve(p) else { return false }
        let prefix = multi ? mountOf(where_.0) + "/" : ""
        if let known = clippyChecked[prefix] { return known }
        var found = false
        for f in await files() where f.hasPrefix(prefix + ".github/workflows/")
            && (f.hasSuffix(".yml") || f.hasSuffix(".yaml")) {
            let t: String? = (try? await current(f))?.0 ?? nil
            if let t, Self.clippyDeniesWarnings(t) {
                found = true
                break
            }
        }
        clippyChecked[prefix] = found
        return found
    }
}
