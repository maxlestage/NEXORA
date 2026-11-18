import Foundation

/// Les textes et les règles d'affichage du chat, sans interface (mêmes textes que
/// l'app Flutter, `ui/chat/chat_screen.dart` et `conversations_screen.dart`).
public enum ChatDisplay {
    /// Un nombre de tokens court : « 540 », « 1,2k », « 15k », « 1,5M ».
    public static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1f", Double(n) / 1_000_000).replacingOccurrences(of: ".", with: ",") + "M" }
        if n >= 10000 { return "\(Int((Double(n) / 1000).rounded()))k" }
        if n >= 1000 { return String(format: "%.1f", Double(n) / 1000).replacingOccurrences(of: ".", with: ",") + "k" }
        return "\(n)"
    }

    /// Un montant en dollars : « 0,0123 $ », « 0,512 $ », « 3,20 $ ».
    public static func cost(_ v: Double) -> String {
        if v == 0 { return "0 $" }
        if v < 0.0001 { return "< 0,0001 $" }
        let digits = v < 0.01 ? 4 : v < 1 ? 3 : 2
        return String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",") + " $"
    }

    /// Sous une réponse : « ≈ 1,2k → 540 tokens · ≈ 0,012 $ » (ou « gratuit »).
    /// `free` : fournisseur local, ou gratuit sans clé.
    public static func costLine(_ m: ChatMessage, free: Bool) -> String {
        let price = m.cost.map { "≈ \(cost($0))" } ?? (free ? "gratuit" : nil)
        return "\(m.estimated ? "≈ " : "")\(compact(m.tokensIn)) → \(compact(m.tokensOut)) tokens\(price.map { " · \($0)" } ?? "")"
    }

    /// Un fournisseur dont les réponses ne coûtent rien.
    public static func isFree(_ p: ProviderDef?) -> Bool {
        guard let p else { return false }
        return p.local || (p.free && !p.needsKey)
    }

    /// En haut d'une conversation : ce qu'elle a coûté.
    public static func spendLine(_ c: Conversation) -> String {
        let tokens = c.tokens
        if tokens == 0 { return "Aucune dépense" }
        return "\(c.cost > 0 ? "≈ \(cost(c.cost)) · " : "")\(compact(tokens)) tokens"
    }

    /// Les premiers messages laissés de côté (mémoire limitée).
    public static func trimmedNote(_ n: Int) -> String {
        "Mémoire : les \(n) premiers messages ne sont plus envoyés au modèle (réglable dans Personnaliser)."
    }

    /// La mémoire réglée, en clair.
    public static func memoryCaption(_ tokens: Int) -> String {
        tokens == 0
            ? "Toute la conversation (peut devenir lent et cher)."
            : "≈ \(tokens / 1000)k tokens · ≈ \(Int((Double(tokens) * 4 / 1000).rounded()))k caractères"
    }

    /// Un message plus long s'affiche coupé, avec « Afficher tout ».
    public static let longMessage = 4000

    /// Le texte affiché d'un message de l'utilisateur.
    public static func shown(_ text: String) -> String {
        let ns = text as NSString
        return ns.length > longMessage ? ns.substring(to: longMessage) + "…" : text
    }

    public static func isLong(_ text: String) -> Bool { (text as NSString).length > longMessage }

    /// Des idées pour commencer une conversation vide, adaptées au métier de l'agent
    /// (avant : un « Rédacteur » proposait d'écrire une app Flutter).
    public static func ideas(agent: Agent?) -> [String] {
        guard let agent else {
            // Les mêmes départs rapides que l'accueil : ils restent à portée quand
            // l'accueil les range (voir `showStarters`).
            return starters.prefix(4).map(\.text)
        }
        if let byCategory = categoryIdeas[agent.category] { return byCategory }
        if !agent.tools.isEmpty { return categoryIdeas["Code"] ?? [] }
        return starters.prefix(4).map(\.text)
    }

    /// Trois idées par catégorie d'agent (celles du catalogue).
    static let categoryIdeas: [String: [String]] = [
        "Code": [
            "Relis ce code et propose des améliorations",
            "Écris les tests de cette fonction",
            "Explique cette erreur de compilation",
        ],
        "Données": [
            "Écris la requête SQL pour ce besoin",
            "Analyse ces chiffres et dis-moi ce qui ressort",
            "Propose un schéma de base de données pour mon app",
        ],
        "Qualité": [
            "Trouve la cause de ce bug",
            "Relis ce code et liste les risques",
            "Comment rendre cet écran plus rapide ?",
        ],
        "Conception": [
            "Découpe ce projet en étapes réalistes",
            "Propose une API pour gérer des comptes",
            "Quelles questions se poser avant de commencer ?",
        ],
        "Ops": [
            "Écris un workflow GitHub Actions qui teste et déploie",
            "Pourquoi ma CI échoue-t-elle ?",
            "Écris un Dockerfile léger pour ce projet",
        ],
        "IA": [
            "Améliore cette consigne pour une IA",
            "Écris la consigne d'un agent de revue de code",
            "Pourquoi l'IA ne suit-elle pas ma consigne ?",
        ],
        "Général": [
            "Écris un e-mail clair et poli",
            "Résume ce texte en 5 points",
            "Rends ce paragraphe plus simple à lire",
        ],
    ]

    /// Au-delà de ce nombre de conversations, l'accueil range les départs rapides :
    /// la liste remonte (on les retrouve dans un nouveau chat vide).
    public static let startersUntil = 5

    /// Faut-il montrer les départs rapides sur l'accueil ?
    public static func showStarters(conversations: Int) -> Bool {
        conversations < startersUntil
    }

    /// Le bouton flottant « Nouveau chat » : caché quand la liste est vide hors
    /// recherche (le bouton est alors dans le contenu et ne cache rien).
    public static func showsFloatingNewChat(isEmpty: Bool, searching: Bool) -> Bool {
        !(isEmpty && !searching)
    }

    /// La barre du haut ne double plus « Nouveau chat » (bouton flottant) : elle
    /// garde seulement le départ avec un agent, aussi offert par appui long.
    public static let agentChatLabel = "Nouveau chat avec un agent"
    public static let newChatHint = "Appui long : choisir un agent"

    /// Le temps laissé pour annuler la suppression d'une conversation : l'avis
    /// « Annuler » reste affiché, et rien n'est effacé avant.
    public static let undoSeconds = 5

    /// L'avis après une suppression : « « Idées de vacances » supprimée », le titre
    /// coupé au-delà de 28 caractères (l'avis tient sur une ligne avec « Annuler »).
    public static func deletedToast(title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Conversation supprimée" }
        let short = t.count > 28 ? String(t.prefix(27)) + "…" : t
        return "« \(short) » supprimée"
    }

    /// La liste sans les conversations en attente de suppression (cachées tout de
    /// suite, effacées après `undoSeconds`).
    public static func hiding(_ list: [ConversationStore.Meta], _ ids: Set<String>) -> [ConversationStore.Meta] {
        ids.isEmpty ? list : list.filter { !ids.contains($0.id) }
    }

    /// La ligne sous le titre de l'accueil : « 🌸 Pollinations · 3 fournisseurs prêts »,
    /// au singulier pour un seul, et une invitation claire quand aucun n'est prêt.
    public static func homeSubtitle(emoji: String, model: String, ready: Int) -> String {
        let head = emoji.isEmpty ? model : "\(emoji) \(model)"
        switch ready {
        case ..<1: return "\(head) · ajoutez un fournisseur dans Modèles"
        case 1: return "\(head) · 1 fournisseur prêt"
        default: return "\(head) · \(ready) fournisseurs prêts"
        }
    }

    /// Le titre et le texte d'une conversation vide.
    public static func emptyTitle(agent: Agent?) -> String {
        agent.map { "\($0.emoji) \($0.name)" } ?? "Posez votre question"
    }

    public static func emptyText(agent: Agent?) -> String {
        agent?.description ?? "Texte, code, traduction, idées… Changez de modèle à tout moment."
    }

    /// Les départs rapides de l'onglet Chat.
    public static let starters: [(emoji: String, text: String)] = [
        ("🧑‍💻", "Écris une app Flutter de liste de tâches avec persistance"),
        ("🦀", "Explique-moi l'ownership en Rust avec un exemple"),
        ("🐛", "Comment déboguer une fuite mémoire dans une app mobile ?"),
        ("🚀", "Écris un workflow GitHub Actions qui teste et déploie"),
        ("🌍", "Traduis en anglais : « Le futur se code dans la poche »"),
        ("💡", "Donne-moi 5 idées d'apps à créer ce week-end"),
    ]

    /// Un modèle choisi à la main : un agent qui impose son modèle est retiré
    /// (sinon le modèle choisi ne serait pas utilisé). Rend l'agent à garder.
    public static func agentKept(afterChoosingModel agent: Agent?) -> Agent? {
        agent?.model == nil ? agent : nil
    }

    /// La conversation copiée en Markdown (« Copier en Markdown »).
    public static func export(_ c: Conversation) -> String {
        var b = "# \(c.title)\n\n"
        for m in c.messages {
            b += m.role == .user ? "**Vous**\n" : "**NEXORA** (\(m.model ?? ""))\n"
            b += "\n\(m.content)\n\n"
        }
        return b
    }
}

extension ChatLogic {
    /// Faut-il lire la réponse à voix haute ? Le message a été dicté, le réglage
    /// « Lire toutes les réponses » est actif, ou l'utilisateur le demande.
    public static func speaks(voice: Bool, speakReplies: Bool, text: String) -> Bool {
        voice || speakReplies || SpeechText.asksForVoice(text)
    }

    /// Le texte d'une réponse terminée sans rien.
    public static func emptyAnswer(model: String, provider: String) -> String {
        "Réponse vide. Le modèle « \(model) » est peut-être indisponible chez \(provider) : essayez-en un autre."
    }
}
