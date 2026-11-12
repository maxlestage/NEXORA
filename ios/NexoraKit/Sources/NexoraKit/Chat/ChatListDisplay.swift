import Foundation

/// La liste des conversations, rangée pour s'y retrouver d'un coup d'œil : la date
/// de chaque conversation en clair, et des groupes (épinglées, aujourd'hui, hier…).
extension ChatDisplay {
    /// Un groupe de la liste des conversations.
    public struct ListGroup: Sendable, Identifiable {
        public let title: String
        public let items: [ConversationStore.Meta]
        public var id: String { title }
    }

    /// Le calendrier français, dans le fuseau de l'appareil.
    public static func frenchCalendar(_ zone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = zone
        return c
    }

    /// Les formateurs coûtent cher à créer : un par format, partagés sous verrou.
    private static let formatters = Locked([String: DateFormatter]())

    private static func format(_ d: Date, _ pattern: String, _ cal: Calendar) -> String {
        formatters.update { all in
            let key = "\(pattern)|\(cal.timeZone.identifier)"
            if let f = all[key] { return f.string(from: d) }
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.timeZone = cal.timeZone
            f.dateFormat = pattern
            all[key] = f
            return f.string(from: d)
        }
    }

    /// La date d'une conversation, courte : « à l'instant », « 14:32 », « hier »,
    /// « lundi », « 12 nov. », « 12 nov. 2025 ».
    public static func when(_ d: Date, now: Date = Date(), calendar: Calendar = frenchCalendar()) -> String {
        let cal = calendar
        if now.timeIntervalSince(d) < 60 && now >= d { return "à l'instant" }
        if cal.isDate(d, inSameDayAs: now) { return format(d, "HH:mm", cal) }
        let startToday = cal.startOfDay(for: now)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: startToday).day ?? 0
        if days == 1 { return "hier" }
        if days > 1 && days < 7 { return format(d, "EEEE", cal) }
        if cal.component(.year, from: d) == cal.component(.year, from: now) { return format(d, "d MMM", cal) }
        return format(d, "d MMM yyyy", cal)
    }

    /// Les conversations rangées par groupes, dans l'ordre de la liste : les
    /// épinglées, puis aujourd'hui, hier, les 7 et 30 derniers jours, et plus ancien.
    /// Les groupes vides sont omis.
    public static func groups(
        _ list: [ConversationStore.Meta], now: Date = Date(), calendar: Calendar = frenchCalendar()
    ) -> [ListGroup] {
        let titles = ["Épinglées", "Aujourd'hui", "Hier", "7 derniers jours", "30 derniers jours", "Plus ancien"]
        var buckets = Array(repeating: [ConversationStore.Meta](), count: titles.count)
        let startToday = calendar.startOfDay(for: now)
        for m in list {
            let i: Int
            if m.pinned {
                i = 0
            } else {
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: m.updated), to: startToday).day ?? 0
                i = days <= 0 ? 1 : days == 1 ? 2 : days < 7 ? 3 : days < 30 ? 4 : 5
            }
            buckets[i].append(m)
        }
        return zip(titles, buckets).compactMap { $1.isEmpty ? nil : ListGroup(title: $0, items: $1) }
    }

    /// Le bouton d'envoi sert-il ? (Un texte, ou au moins une photo.)
    public static func canSend(_ text: String, photos: Int) -> Bool {
        photos > 0 || text.contains { !$0.isWhitespace }
    }
}
