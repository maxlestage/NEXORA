import Foundation

// Des outils de texte qui se comportent comme ceux de Dart (l'app Flutter, la
// référence) : positions en unités UTF-16, « \r\n » qui reste deux caractères
// (une `String` Swift en fait un seul), expressions régulières où `\w`, `\d` et
// `\b` ne valent que pour l'ASCII. Sans eux, les découpages par ligne, les
// positions des blocs de code et les remplacements ne donneraient pas les mêmes
// résultats que l'app Flutter.

extension String {
    /// La longueur en unités UTF-16 (comme `String.length` en Dart).
    var len: Int { utf16.count }

    /// Le texte entre deux positions UTF-16 (`substring` de Dart).
    func sub(_ from: Int, _ to: Int? = nil) -> String {
        let u = utf16
        let end = to ?? u.count
        let a = u.index(u.startIndex, offsetBy: max(0, min(from, u.count)))
        let b = u.index(u.startIndex, offsetBy: max(0, min(end, u.count)))
        if a >= b { return "" }
        return String(decoding: Array(u[a..<b]), as: UTF16.self)
    }

    /// Le caractère (unité UTF-16) à cette position (`s[i]` en Dart).
    func at(_ i: Int) -> String { sub(i, i + 1) }

    /// Première position de `needle` à partir de `from`, ou -1.
    func indexOf(_ needle: String, _ from: Int = 0) -> Int {
        U16(self).indexOf(needle, from)
    }

    /// Dernière position de `needle` qui commence au plus à `start`, ou -1.
    func lastIndexOf(_ needle: String, _ start: Int? = nil) -> Int {
        U16(self).lastIndexOf(needle, start)
    }

    /// `startsWith(p, at)` de Dart.
    func startsWith(_ p: String, at i: Int = 0) -> Bool {
        let a = Array(utf16)
        let b = Array(p.utf16)
        if i < 0 || i + b.count > a.count { return false }
        return Array(a[i..<i + b.count]) == b
    }

    /// `endsWith` de Dart (« x\r\n » finit bien par « \n »).
    func endsWith(_ p: String) -> Bool {
        let a = Array(utf16)
        let b = Array(p.utf16)
        if b.count > a.count { return false }
        return Array(a[(a.count - b.count)...]) == b
    }

    /// `split` de Dart avec un séparateur littéral (« \r\n » est coupé sur « \n »).
    func dsplit(_ sep: String) -> [String] {
        let t = U16(self)
        if sep.isEmpty { return t.u.map { String(decoding: [$0], as: UTF16.self) } }
        var out: [String] = []
        var pos = 0
        while true {
            let i = t.indexOf(sep, pos)
            if i < 0 {
                out.append(t.sub(pos, t.count))
                return out
            }
            out.append(t.sub(pos, i))
            pos = i + sep.len
        }
    }

    /// Les lignes (découpées sur « \n » seul, comme `split('\n')` en Dart).
    var lines: [String] { dsplit("\n") }

    private static let spaces = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))

    func trim() -> String {
        trimLeft().trimRight()
    }

    func trimLeft() -> String {
        var s = unicodeScalars[...]
        while let f = s.first, Self.spaces.contains(f) { s = s.dropFirst() }
        return String(String.UnicodeScalarView(s))
    }

    func trimRight() -> String {
        var s = unicodeScalars[...]
        while let l = s.last, Self.spaces.contains(l) { s = s.dropLast() }
        return String(String.UnicodeScalarView(s))
    }

    /// Remplace toutes les occurrences littérales.
    func replaceAll(_ a: String, _ b: String) -> String {
        if a.isEmpty { return self }
        let t = U16(self)
        var out: [UInt16] = []
        var pos = 0
        let bu = Array(b.utf16)
        while true {
            let i = t.indexOf(a, pos)
            if i < 0 {
                out += t.u[pos...]
                break
            }
            out += t.u[pos..<i]
            out += bu
            pos = i + a.len
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// Remplace la première occurrence littérale.
    func replaceFirst(_ a: String, _ b: String) -> String {
        let i = indexOf(a)
        if i < 0 { return self }
        return sub(0, i) + b + sub(i + a.len)
    }

    /// Remplace les caractères entre deux positions (`replaceRange` de Dart).
    func replaceRange(_ from: Int, _ to: Int, _ with: String) -> String {
        sub(0, from) + with + sub(to)
    }

    /// Le nombre d'occurrences littérales (sans chevauchement).
    func occurrences(_ needle: String) -> Int {
        if needle.isEmpty { return 0 }
        let t = U16(self)
        var n = 0
        var pos = 0
        while true {
            let i = t.indexOf(needle, pos)
            if i < 0 { return n }
            n += 1
            pos = i + needle.len
        }
    }

    /// Les `n` premières unités UTF-16 (sans couper au-delà).
    func head(_ n: Int) -> String { len <= n ? self : sub(0, n) }
}

/// Un texte vu comme ses unités UTF-16 : positions et découpes en temps constant,
/// pour les boucles qui parcourent un long texte.
struct U16 {
    let u: [UInt16]

    init(_ s: String) {
        u = Array(s.utf16)
    }

    var count: Int { u.count }

    func sub(_ from: Int, _ to: Int? = nil) -> String {
        let a = max(0, min(from, u.count))
        let b = max(a, min(to ?? u.count, u.count))
        return String(decoding: u[a..<b], as: UTF16.self)
    }

    func at(_ i: Int) -> UInt16? { i >= 0 && i < u.count ? u[i] : nil }

    func indexOf(_ needle: String, _ from: Int = 0) -> Int {
        let n = Array(needle.utf16)
        if from > u.count { return -1 }
        let start = max(0, from)
        if n.isEmpty { return start }
        if n.count > u.count { return -1 }
        let first = n[0]
        var i = start
        let last = u.count - n.count
        while i <= last {
            if u[i] == first {
                var ok = true
                var k = 1
                while k < n.count {
                    if u[i + k] != n[k] { ok = false; break }
                    k += 1
                }
                if ok { return i }
            }
            i += 1
        }
        return -1
    }

    func lastIndexOf(_ needle: String, _ start: Int? = nil) -> Int {
        let n = Array(needle.utf16)
        var i = min(start ?? (u.count - n.count), u.count - n.count)
        if i < 0 { return -1 }
        if n.isEmpty { return i }
        while i >= 0 {
            var ok = true
            for k in 0..<n.count where u[i + k] != n[k] {
                ok = false
                break
            }
            if ok { return i }
            i -= 1
        }
        return -1
    }

    func startsWith(_ p: String, at i: Int) -> Bool {
        let b = Array(p.utf16)
        if i < 0 || i + b.count > u.count { return false }
        for k in 0..<b.count where u[i + k] != b[k] { return false }
        return true
    }
}

/// Une correspondance d'expression régulière, positions en UTF-16.
struct DMatch {
    let start: Int
    let end: Int
    let groups: [String?]

    subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }

    /// Le texte trouvé.
    var text: String { groups[0] ?? "" }
}

/// Une expression régulière qui suit les règles de Dart (JavaScript) : `\w`, `\W`,
/// `\d`, `\D` et `\b` ne concernent que l'ASCII ; `\p{L}` reste Unicode.
final class DRegex: @unchecked Sendable {
    let re: NSRegularExpression

    /// Rend `nil` si l'expression est invalide.
    init?(try pattern: String, caseSensitive: Bool = true) {
        guard let r = DRegex.compiled(pattern, caseSensitive: caseSensitive) else { return nil }
        re = r
    }

    /// Les expressions déjà compilées. Compiler coûte bien plus que chercher, et la
    /// plupart des expressions sont écrites dans le code et reviennent sans cesse
    /// (à chaque ligne du journal affichée, à chaque fichier vérifié…). Une
    /// `NSRegularExpression` ne change plus une fois créée : elle se partage entre
    /// fils. Le cache est vidé s'il grossit trop (expressions tirées de recherches).
    private static let cache = Locked<[String: NSRegularExpression]>([:])
    static let cacheLimit = 512

    private static func compiled(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        let key = (caseSensitive ? "s:" : "i:") + pattern
        if let r = cache.update({ $0[key] }) { return r }
        guard let r = try? NSRegularExpression(
            pattern: ascii(pattern),
            options: caseSensitive ? [] : [.caseInsensitive]
        ) else { return nil }
        cache.update { entries in
            if entries.count >= cacheLimit { entries.removeAll(keepingCapacity: true) }
            entries[key] = r
        }
        return r
    }

    /// Une expression écrite dans le code (forcément valide).
    convenience init(_ pattern: String, caseSensitive: Bool = true) {
        self.init(try: pattern, caseSensitive: caseSensitive)!
    }

    static func escape(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

    private static let word = "A-Za-z0-9_"

    /// Réécrit `\w`, `\W`, `\d`, `\D`, `\b` en classes ASCII (comme en Dart).
    static func ascii(_ p: String) -> String {
        let c = Array(p)
        var out = ""
        var inClass = false
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch == "\\", i + 1 < c.count {
                let n = c[i + 1]
                switch (n, inClass) {
                case ("w", false): out += "[\(word)]"
                case ("w", true): out += word
                case ("W", false): out += "[^\(word)]"
                case ("d", false): out += "[0-9]"
                case ("d", true): out += "0-9"
                case ("D", false): out += "[^0-9]"
                case ("b", false): out += "(?:(?<=[\(word)])(?![\(word)])|(?<![\(word)])(?=[\(word)]))"
                case ("B", false): out += "(?:(?<=[\(word)])(?=[\(word)])|(?<![\(word)])(?![\(word)]))"
                default: out += "\\" + String(n)
                }
                i += 2
                continue
            }
            if inClass {
                if ch == "]" { inClass = false }
                // ICU lit « [ » dans une classe comme une classe imbriquée.
                if ch == "[" { out += "\\["; i += 1; continue }
            } else if ch == "[" {
                inClass = true
                out.append(ch)
                // « [] » ou « [^] » : le « ] » qui suit est un caractère.
                if i + 1 < c.count, c[i + 1] == "^" { out.append("^"); i += 1 }
                if i + 1 < c.count, c[i + 1] == "]" { out += "\\]"; i += 1 }
                i += 1
                continue
            }
            out.append(ch)
            i += 1
        }
        return out
    }

    private func range(_ s: String) -> NSRange { NSRange(location: 0, length: s.utf16.count) }

    private func match(_ r: NSTextCheckingResult, _ s: NSString) -> DMatch {
        var g: [String?] = []
        for k in 0..<r.numberOfRanges {
            let rr = r.range(at: k)
            g.append(rr.location == NSNotFound ? nil : s.substring(with: rr))
        }
        return DMatch(start: r.range.location, end: r.range.location + r.range.length, groups: g)
    }

    func hasMatch(_ s: String) -> Bool {
        re.firstMatch(in: s, options: [], range: range(s)) != nil
    }

    func firstMatch(_ s: String, from: Int = 0) -> DMatch? {
        let n = s.utf16.count
        if from > n { return nil }
        guard let r = re.firstMatch(in: s, options: [], range: NSRange(location: from, length: n - from)) else { return nil }
        return match(r, s as NSString)
    }

    func allMatches(_ s: String) -> [DMatch] {
        let ns = s as NSString
        return re.matches(in: s, options: [], range: range(s)).map { match($0, ns) }
    }

    /// Remplace chaque correspondance par le texte rendu (`replaceAllMapped`).
    func replaceAllMapped(_ s: String, _ f: (DMatch) -> String) -> String {
        let ns = s as NSString
        let all = re.matches(in: s, options: [], range: range(s))
        if all.isEmpty { return s }
        var out = ""
        var pos = 0
        for r in all {
            out += ns.substring(with: NSRange(location: pos, length: r.range.location - pos))
            out += f(match(r, ns))
            pos = r.range.location + r.range.length
        }
        out += ns.substring(from: pos)
        return out
    }

    /// Remplace chaque correspondance par un texte littéral.
    func replaceAll(_ s: String, _ with: String) -> String { replaceAllMapped(s) { _ in with } }

    /// Remplace la première correspondance par un texte littéral.
    func replaceFirst(_ s: String, _ with: String) -> String {
        guard let m = firstMatch(s) else { return s }
        return s.sub(0, m.start) + with + s.sub(m.end)
    }
}

// MARK: - Valeurs JSON (comme les `Map<String, dynamic>` de Dart)

/// `null` de JSON (`NSNull`) vaut `nil`, comme en Dart.
func jv(_ x: Any?) -> Any? {
    if x is NSNull { return nil }
    return x
}

/// Un booléen JSON (`true`/`false`), pas un nombre : `JSONSerialization` rend des
/// `NSNumber` pour les deux.
func isJSONBool(_ x: Any) -> Bool {
    if type(of: x) == Bool.self { return true }
    guard let n = x as? NSNumber else { return false }
    #if canImport(Darwin)
    return CFGetTypeID(n) == CFBooleanGetTypeID()
    #else
    return String(cString: n.objCType) == "c"
    #endif
}

/// `x.toString()` de Dart pour une valeur JSON (`null` → « null »).
func dstr(_ x: Any?) -> String {
    guard let x = jv(x) else { return "null" }
    if let s = x as? String { return s }
    if isJSONBool(x) { return (x as? Bool) == true ? "true" : "false" }
    if let n = x as? NSNumber {
        let d = n.doubleValue
        let objc = String(cString: n.objCType)
        if objc != "d" && objc != "f" { return "\(n.int64Value)" }
        if d.rounded() == d && abs(d) < 1e15 { return "\(Int64(d)).0" }
        return "\(d)"
    }
    if JSONSerialization.isValidJSONObject(x) { return LooseJSON.string(x) }
    return "\(x)"
}

/// `(x ?? '').toString()` de Dart.
func dstrOr(_ x: Any?, _ fallback: String = "") -> String {
    jv(x) == nil ? fallback : dstr(x)
}

/// `x == true` de Dart.
func isTrue(_ x: Any?) -> Bool {
    guard let x = jv(x), isJSONBool(x) else { return false }
    return (x as? Bool) == true
}

/// Un entier : nombre JSON, ou texte qui en contient un (`int.tryParse`).
func asInt(_ x: Any?) -> Int? {
    guard let x = jv(x) else { return nil }
    if let s = x as? String { return Int(s.trim()) }
    if isJSONBool(x) { return nil }
    if let n = x as? NSNumber {
        let d = n.doubleValue
        if d.isNaN || d.isInfinite { return nil }
        return Int(d)
    }
    return nil
}

/// Un objet JSON strict (`jsonDecode` puis `is Map`).
func tryJSON(_ s: String) -> [String: Any]? {
    let t = s.trim()
    guard let data = t.data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else { return nil }
    return j as? [String: Any]
}

/// Un objet JSON strict, sinon écrit de travers (voir `LooseJSON.decodeLoose`).
func tryLooseJSON(_ s: String) -> [String: Any]? {
    tryJSON(s) ?? LooseJSON.decodeLoose(s)
}

/// `jsonEncode` : du JSON compact et stable (clés triées).
func jsonText(_ x: Any) -> String {
    guard JSONSerialization.isValidJSONObject(x),
          let d = try? JSONSerialization.data(withJSONObject: x, options: [.sortedKeys, .withoutEscapingSlashes])
    else { return "\(x)" }
    return String(decoding: d, as: UTF8.self)
}

/// Un dictionnaire qui garde l'ordre d'insertion de ses clés (comme les `Map` de
/// Dart) : l'ordre des brouillons compte pour l'agent et pour l'interface.
public struct OrderedMap<Value: Sendable>: Sendable {
    public private(set) var keys: [String] = []
    private var dict: [String: Value] = [:]

    public init() {}

    public init(_ pairs: [(String, Value)]) {
        for (k, v) in pairs { set(k, v) }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public func contains(_ k: String) -> Bool { dict[k] != nil }

    /// La valeur gardée, si la clé existe.
    public func get(_ k: String) -> Value? { dict[k] }

    /// Ajoute ou remplace (une clé déjà là garde sa place).
    public mutating func set(_ k: String, _ v: Value) {
        if dict.updateValue(v, forKey: k) == nil { keys.append(k) }
    }

    /// Ajoute seulement si la clé n'existe pas (`putIfAbsent`).
    public mutating func setIfAbsent(_ k: String, _ v: @autoclosure () -> Value) {
        if dict[k] == nil { set(k, v()) }
    }

    @discardableResult
    public mutating func remove(_ k: String) -> Value? {
        guard let v = dict.removeValue(forKey: k) else { return nil }
        keys.removeAll { $0 == k }
        return v
    }

    public mutating func removeWhere(_ f: (String, Value) -> Bool) {
        let gone = keys.filter { f($0, dict[$0]!) }
        if gone.isEmpty { return }
        let set = Set(gone)
        for k in gone { dict.removeValue(forKey: k) }
        keys.removeAll { set.contains($0) }
    }

    public mutating func removeAll() {
        keys = []
        dict = [:]
    }

    /// Les paires, dans l'ordre d'insertion.
    public var entries: [(key: String, value: Value)] { keys.map { ($0, dict[$0]!) } }

    public var values: [Value] { keys.map { dict[$0]! } }
}

/// Du JSON indenté d'un espace (`JsonEncoder.withIndent(' ')` de Dart), clés triées.
func prettyJSON(_ x: Any, _ pad: String = "") -> String {
    let inner = pad + " "
    switch jv(x) {
    case nil:
        return "null"
    case let d as [String: Any]:
        if d.isEmpty { return "{}" }
        let items = d.keys.sorted().map { "\(inner)\(jsonText([$0]).dropFirst().dropLast()): \(prettyJSON(d[$0]!, inner))" }
        return "{\n" + items.joined(separator: ",\n") + "\n\(pad)}"
    case let a as [Any]:
        if a.isEmpty { return "[]" }
        return "[\n" + a.map { inner + prettyJSON($0, inner) }.joined(separator: ",\n") + "\n\(pad)]"
    case let s as String:
        return String(jsonText([s]).dropFirst().dropLast())
    case let v?:
        return dstr(v)
    }
}
