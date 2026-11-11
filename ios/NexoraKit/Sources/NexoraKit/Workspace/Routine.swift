import Foundation

// # Les routines (port de `app/lib/models/routine.dart`)
//
// Une mission confiée à l'agent, relancée à intervalle régulier : sur le téléphone
// (une session de l'agent NEXORA), ou sur GitHub Actions (un workflow planifié).

/// Où tourne une routine.
public enum RoutineRunner: String, Sendable, Codable, CaseIterable {
    /// Sur le téléphone : une session de l'agent NEXORA, quand l'app tourne
    /// (ouverte ou en arrière-plan). Un passage manqué est rattrapé au retour.
    case app

    /// Sur GitHub Actions : un workflow planifié dans le dépôt, qui tourne 24 h/24
    /// même téléphone éteint (avec un agent cloud et sa clé en secret).
    case github
}

/// Une routine : une mission confiée à l'agent, relancée à intervalle régulier.
public struct Routine: Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String

    /// Ce que l'agent doit faire à chaque passage.
    public var task: String

    /// Les dépôts : « owner/nom@branche ».
    public var repos: [String]

    /// Le modèle (« fournisseur::modèle ») et l'effort ; vides = ceux par défaut.
    public var model: String?
    public var level: String?

    public var enabled: Bool

    /// Toutes les combien de minutes (30, 60, 120… 1440).
    public var everyMinutes: Int

    /// Heure du premier passage de la journée, en minutes depuis minuit (heure du
    /// téléphone).
    public var startMinute: Int

    /// Fin de la plage horaire (minutes depuis minuit), ou `nil` : toute la
    /// journée (24 h/24).
    public var endMinute: Int?

    public var runner: RoutineRunner

    /// L'agent cloud utilisé sur GitHub (voir `Catalog.cloudAgents`).
    public var cloudAgent: String

    /// Sur le téléphone : faire passer la CI GitHub, puis fusionner quand elle
    /// est verte.
    public var autoCi: Bool
    public var autoMerge: Bool

    public var lastRun: Date?

    /// La dernière session lancée par la routine.
    public var lastSession: String?

    public let createdAt: Date

    public init(
        id: String, name: String, task: String, repos: [String], model: String? = nil, level: String? = nil,
        enabled: Bool = true, everyMinutes: Int = 60, startMinute: Int = 9 * 60, endMinute: Int? = nil,
        runner: RoutineRunner = .app, cloudAgent: String = "gemini-cli", autoCi: Bool = true,
        autoMerge: Bool = true, lastRun: Date? = nil, lastSession: String? = nil, createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.task = task
        self.repos = repos
        self.model = model
        self.level = level
        self.enabled = enabled
        self.everyMinutes = everyMinutes
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.runner = runner
        self.cloudAgent = cloudAgent
        self.autoCi = autoCi
        self.autoMerge = autoMerge
        self.lastRun = lastRun
        self.lastSession = lastSession
        self.createdAt = createdAt ?? Date()
    }

    public static let intervals = [30, 60, 120, 180, 360, 720, 1440]

    static let day = 24 * 60

    /// Le reste toujours positif (le `%` de Dart).
    static func mod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

    /// Les heures de passage dans une journée (minutes depuis minuit), triées.
    public var times: [Int] {
        var out = Set<Int>()
        // Avec une plage : de son début à sa fin (qui peut passer minuit).
        let span = endMinute.map { Self.mod($0 - startMinute, Self.day) } ?? Self.day
        let every = min(max(everyMinutes, 30), Self.day)
        let limit = endMinute == nil ? span : span + 1
        var t = 0
        while t < limit {
            out.insert((startMinute + t) % Self.day)
            t += every
        }
        return out.sorted()
    }

    /// Le prochain passage strictement après `after` (heure du téléphone).
    public func nextAfter(_ after: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: after)
        let times = times
        for d in 0..<3 {
            guard let base = calendar.date(byAdding: .day, value: d, to: day) else { continue }
            let c = calendar.dateComponents([.year, .month, .day], from: base)
            for m in times {
                var dc = DateComponents()
                dc.year = c.year
                dc.month = c.month
                dc.day = c.day
                dc.hour = m / 60
                dc.minute = m % 60
                if let at = calendar.date(from: dc), at > after { return at }
            }
        }
        return day.addingTimeInterval(24 * 3600)
    }

    /// Le prochain passage prévu.
    public func nextRun(calendar: Calendar = .current) -> Date { nextAfter(lastRun ?? createdAt, calendar: calendar) }

    /// Un passage est dû (ceux manqués ne sont rattrapés qu'une fois).
    public func isDue(_ now: Date, calendar: Calendar = .current) -> Bool {
        enabled && !(nextRun(calendar: calendar) > now)
    }

    /// « 09:05 ».
    public static func hm(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// « Toutes les 30 min, de 11:00 à 23:00 », « Tous les jours à 9:00 »…
    public var scheduleLabel: String {
        let every = everyMinutes >= 1440
            ? "Tous les jours à \(Self.hm(startMinute))"
            : everyMinutes % 60 == 0
                ? "Toutes les \(everyMinutes / 60 == 1 ? "heures" : "\(everyMinutes / 60) h")"
                : "Toutes les \(everyMinutes) min"
        if everyMinutes >= 1440 { return every }
        if let end = endMinute { return "\(every), de \(Self.hm(startMinute)) à \(Self.hm(end))" }
        return "\(every), à partir de \(Self.hm(startMinute)), 24 h/24"
    }

    /// Le planning pour GitHub Actions (cron en UTC) ; `utcOffset` : le décalage
    /// du téléphone avec UTC, en minutes. Une ligne par groupe d'heures partageant
    /// les mêmes minutes : un cron seul mélangerait minutes et heures (11:30 et
    /// 12:00 donneraient aussi 11:00 et 12:30).
    public func crons(utcOffset: Int) -> [String] {
        var minuteOrder: [Int] = []
        var byMinute: [Int: Set<Int>] = [:]
        for m in times {
            let u = Self.mod(m - utcOffset, Self.day)
            if byMinute[u % 60] == nil {
                minuteOrder.append(u % 60)
                byMinute[u % 60] = []
            }
            byMinute[u % 60]!.insert(u / 60)
        }
        // Les minutes qui ont exactement les mêmes heures sont regroupées.
        var hoursOrder: [String] = []
        var byHours: [String: [Int]] = [:]
        for minute in minuteOrder {
            let hours = byMinute[minute]!.sorted()
            let h = hours.count == 24 ? "*" : hours.map(String.init).joined(separator: ",")
            if byHours[h] == nil {
                hoursOrder.append(h)
                byHours[h] = []
            }
            byHours[h]!.append(minute)
        }
        return hoursOrder.map { h in
            "\(byHours[h]!.sorted().map(String.init).joined(separator: ",")) \(h) * * *"
        }.sorted()
    }

    /// Le planning en une ligne (la première si plusieurs sont nécessaires).
    public func cron(utcOffset: Int) -> String { crons(utcOffset: utcOffset)[0] }

    /// Le fichier du workflow sur GitHub.
    public var workflowFile: String { "nexora-routine-\(Self.slug(id)).yml" }

    public static func slug(_ s: String) -> String {
        DRegex("[^a-z0-9]+").replaceAll(s.lowercased(), "-")
    }

    /// Le workflow GitHub Actions de la routine : celui de l'agent cloud choisi,
    /// planifié, avec la mission en instruction par défaut.
    public func workflowYaml(utcOffset: Int) -> String {
        let agents = Catalog.cloudAgents
        let agent = agents.first { $0.id == cloudAgent } ?? agents.first
        // Pas d'expression GitHub dans la mission (elle serait évaluée).
        let mission = dartJSONString(task.replacingOccurrences(of: "${{", with: "$ {{"))
        var y = (agent?.yaml ?? "").replacingOccurrences(
            of: "${{ github.event.inputs.instruction }}",
            with: "${{ github.event.inputs.instruction || env.NEXORA_TASK }}"
        )
        y = DRegex("(?m)^name:.*$").replaceFirst(y, "name: \(dartJSONString("NEXORA · Routine · \(name)"))")
        let schedule = crons(utcOffset: utcOffset).map { "    - cron: '\($0)'" }.joined(separator: "\n")
        y = DRegex("(?m)^on:\\s*$").replaceFirst(y, "on:\n  schedule:\n\(schedule)")
        // Lancé par le planning, l'instruction n'est pas obligatoire.
        y = DRegex("(instruction:\\s*\\n(?:\\s+description:.*\\n)?\\s+)required: true")
            .replaceAllMapped(y) { m in (m[1] ?? "") + "required: false" }
        y = DRegex("(?m)^jobs:").replaceFirst(y, "env:\n  NEXORA_TASK: \(mission)\n\njobs:")
        return "# Routine NEXORA « \(name) » : \(scheduleLabel.lowercased()) "
            + "(heure du téléphone).\n# Modifiez-la depuis l'app NEXORA.\n\(y)"
    }

    /// Les dépôts de la routine (« owner/nom@branche », branche « main » par défaut).
    public var targets: [RepoTarget] {
        repos.compactMap { s in
            guard s.contains("/") else { return nil }
            let parts = s.components(separatedBy: "/")
            let name = parts[1].components(separatedBy: "@")[0]
            let branch = s.contains("@") ? s.components(separatedBy: "@").last! : "main"
            return RepoTarget(parts[0], name, branch)
        }
    }

    // MARK: - Enregistrement (même JSON que l'app Flutter)

    public func toJSON() -> [String: Any] {
        func nullable(_ v: Any?) -> Any { v ?? NSNull() }
        return [
            "id": id,
            "name": name,
            "task": task,
            "repos": repos,
            "model": nullable(model),
            "level": nullable(level),
            "enabled": enabled,
            "every": everyMinutes,
            "start": startMinute,
            "end": nullable(endMinute),
            "runner": runner.rawValue,
            "cloudAgent": cloudAgent,
            "autoCi": autoCi,
            "autoMerge": autoMerge,
            "lastRun": nullable(lastRun.map(ISO8601.string)),
            "lastSession": nullable(lastSession),
            "createdAt": ISO8601.string(createdAt),
        ]
    }

    public static func fromJSON(_ j: [String: Any]) -> Routine? {
        guard let id = j["id"] as? String else { return nil }
        func bool(_ k: String, _ fallback: Bool) -> Bool {
            guard let v = jv(j[k]), isJSONBool(v) else { return fallback }
            return (v as? Bool) ?? fallback
        }
        return Routine(
            id: id,
            name: jv(j["name"]) as? String ?? "Routine",
            task: jv(j["task"]) as? String ?? "",
            repos: (jv(j["repos"]) as? [Any] ?? []).compactMap { $0 as? String },
            model: jv(j["model"]) as? String,
            level: jv(j["level"]) as? String,
            enabled: bool("enabled", true),
            everyMinutes: asInt(j["every"]) ?? 60,
            startMinute: asInt(j["start"]) ?? 9 * 60,
            endMinute: asInt(j["end"]),
            runner: RoutineRunner(rawValue: jv(j["runner"]) as? String ?? "") ?? .app,
            cloudAgent: jv(j["cloudAgent"]) as? String ?? "gemini-cli",
            autoCi: bool("autoCi", true),
            autoMerge: bool("autoMerge", true),
            lastRun: ISO8601.parse(jv(j["lastRun"]) as? String),
            lastSession: jv(j["lastSession"]) as? String,
            createdAt: ISO8601.parse(jv(j["createdAt"]) as? String)
        )
    }

    /// Une liste de routines enregistrée (texte JSON, clé `routines`).
    public static func decodeList(_ raw: String?) -> [Routine] {
        guard let raw, let list = LooseJSON.object(raw) as? [Any] else { return [] }
        return list.compactMap { ($0 as? [String: Any]).flatMap(fromJSON) }
    }

    public static func encodeList(_ list: [Routine]) -> String {
        let arr = list.map { $0.toJSON() }
        guard let d = try? JSONSerialization.data(withJSONObject: arr, options: [.withoutEscapingSlashes]) else { return "[]" }
        return String(decoding: d, as: UTF8.self)
    }
}

/// `jsonEncode(s)` de Dart pour un texte : guillemets, barres obliques inverses et
/// caractères de contrôle échappés, le reste tel quel.
public func dartJSONString(_ s: String) -> String {
    var out = "\""
    for u in s.unicodeScalars {
        switch u {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\u{8}": out += "\\b"
        case "\u{C}": out += "\\f"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if u.value < 0x20 {
                out += String(format: "\\u%04x", u.value)
            } else {
                out.unicodeScalars.append(u)
            }
        }
    }
    return out + "\""
}
