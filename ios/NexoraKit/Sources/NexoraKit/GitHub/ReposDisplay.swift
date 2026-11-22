import Foundation

/// Logique d'affichage de la liste des dépôts (onglet Code › Dépôts), testable sous Linux.
public enum ReposDisplay {
    /// Les dépôts qui correspondent à la recherche : nom complet, description ou langage,
    /// sans tenir compte des majuscules ni des accents. L'ordre reçu est gardé.
    public static func filter(_ repos: [Repo], query: String) -> [Repo] {
        repos.filter {
            AgentsDisplay.matches(query, $0.fullName, $0.description ?? "", $0.language ?? "")
        }
    }

    /// La ligne de détails sous le nom : « Swift · ★ 12 · il y a 3 j ».
    /// Les étoiles ne s'affichent que s'il y en a ; rien de vide.
    public static func meta(_ repo: Repo, now: Date = Date()) -> String {
        var parts: [String] = []
        if let l = repo.language, !l.isEmpty { parts.append(l) }
        if let s = repo.stars, s > 0 { parts.append("★ \(s)") }
        if let p = repo.pushedAt, let d = parseDate(p) { parts.append(WorkspaceText.ago(d, now: now)) }
        return parts.joined(separator: " · ")
    }

    /// Le nom affiché : « nexora » pour vos propres dépôts (votre nom devant ne dit rien),
    /// « autre/nexora » pour ceux d'un autre compte ou d'une organisation.
    public static func title(_ repo: Repo, login: String?) -> String {
        guard let login, repo.owner.login.caseInsensitiveCompare(login) == .orderedSame else { return repo.fullName }
        return repo.name
    }

    /// Le bouton du balayage vers la droite : lancer l'agent sur ce dépôt.
    public static let agentAction = "Agent"

    /// Le libellé complet (appui long, VoiceOver) : « Lancer l'agent sur nexora ».
    public static func agentLabel(_ repo: Repo, login: String?) -> String {
        "Lancer l'agent sur \(title(repo, login: login))"
    }

    /// L'avis après « Copier le lien » (avant : une vibration seule).
    public static let linkCopied = "Lien copié"

    /// L'avis après la création d'un dépôt : « Dépôt nexora créé ».
    public static func createdToast(_ repo: Repo, login: String?) -> String {
        "Dépôt \(title(repo, login: login)) créé"
    }

    /// Le bouton de cet avis : l'étape suivante la plus probable, sans chercher le dépôt.
    public static let createdAction = "Lancer l'agent"

    /// Ce que la feuille « Dépôt » (choix d'un dépôt pour l'agent, une routine) montre à la
    /// place de la liste quand elle est vide ; avant, elle restait blanche sans explication.
    public enum PickerNote: Equatable, Sendable {
        /// Les dépôts arrivent.
        case loading
        /// Le chargement a échoué : le message, avec « Réessayer ».
        case failed(String)
        /// Le compte n'a aucun dépôt.
        case empty
        /// La recherche ne trouve rien : le titre, avec « Effacer la recherche ».
        case noMatch(String)
    }

    /// `nil` : il y a des dépôts à montrer. Une erreur ne cache jamais une liste déjà chargée.
    public static func pickerNote(shown: Int, total: Int, loading: Bool, error: String?,
                                  query: String) -> PickerNote? {
        if shown > 0 { return nil }
        if total > 0 {
            return .noMatch("Aucun dépôt pour « \(query.trimmingCharacters(in: .whitespacesAndNewlines)) »")
        }
        if loading { return .loading }
        if let error, !error.isEmpty { return .failed(error) }
        return .empty
    }

    /// Le texte quand le compte n'a aucun dépôt.
    public static let pickerEmptyText = "Aucun dépôt sur ce compte. Créez-en un ci-dessus."

    /// L'en-tête de la liste : « 12 dépôts », « 1 dépôt », ou « 3 sur 12 » pendant une recherche.
    public static func header(shown: Int, total: Int) -> String {
        if shown < total { return "\(shown) sur \(total)" }
        return total == 1 ? "1 dépôt" : "\(total) dépôts"
    }

    /// Ce que VoiceOver lit pour un dépôt : nom, « privé », description puis détails.
    public static func accessibility(_ repo: Repo, login: String?, now: Date = Date()) -> String {
        var parts = [title(repo, login: login)]
        if repo.isPrivate { parts.append("privé") }
        if let d = repo.description, !d.isEmpty { parts.append(d) }
        let m = meta(repo, now: now).replacingOccurrences(of: "★ ", with: "étoiles ")
        if !m.isEmpty { parts.append(m.replacingOccurrences(of: " · ", with: ", ")) }
        return parts.joined(separator: ", ")
    }

    /// Date ISO 8601 de l'API GitHub (« 2026-11-12T17:49:05Z »).
    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

/// Logique d'affichage des fichiers d'un dépôt (fiche d'un dépôt), testable sous Linux.
public enum FilesDisplay {
    /// Dossiers d'abord, puis fichiers ; dans chaque groupe, ordre naturel sans casse
    /// (« fichier2 » avant « fichier10 »).
    public static func sorted(_ items: [ContentItem]) -> [ContentItem] {
        items.sorted { a, b in
            if a.isDir != b.isDir { return a.isDir }
            let r = a.name.compare(b.name, options: [.caseInsensitive, .numeric])
            return r == .orderedSame ? a.name < b.name : r == .orderedAscending
        }
    }

    /// Le résumé d'un dossier, lu aussi par VoiceOver : « 2 dossiers · 1 fichier ».
    /// Vide si le dossier est vide.
    public static func summary(_ items: [ContentItem]) -> String {
        let dirs = items.filter(\.isDir).count
        let files = items.count - dirs
        var parts: [String] = []
        if dirs > 0 { parts.append(dirs == 1 ? "1 dossier" : "\(dirs) dossiers") }
        if files > 0 { parts.append(files == 1 ? "1 fichier" : "\(files) fichiers") }
        return parts.joined(separator: " · ")
    }

    /// Les éléments d'un dossier dont le nom correspond à la recherche (sans majuscules
    /// ni accents). L'ordre reçu est gardé.
    public static func filter(_ items: [ContentItem], query: String) -> [ContentItem] {
        items.filter { AgentsDisplay.matches(query, $0.name) }
    }

    /// L'invite de la recherche dans un dossier d'un dépôt (fiche du dépôt, pièce jointe).
    public static let searchPrompt = "Chercher dans ce dossier"

    /// La ligne sous la liste : le résumé du dossier, ou pendant une recherche ce qu'elle
    /// garde (« 3 résultats sur 42 »). Vide si rien à dire.
    public static func footer(shown: [ContentItem], total: Int, query: String) -> String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return summary(shown) }
        if shown.isEmpty { return "" }
        return (shown.count == 1 ? "1 résultat" : "\(shown.count) résultats") + " sur \(total)"
    }

    /// Vrai si le fichier `path` est directement dans le dossier `folder` (« » = racine) :
    /// il apparaît alors dans la liste affichée.
    public static func isDirectChild(_ path: String, of folder: String) -> Bool {
        let parts = path.split(separator: "/")
        guard !parts.isEmpty else { return false }
        return parts.dropLast().joined(separator: "/") == folder.split(separator: "/").joined(separator: "/")
    }

    /// L'avis après la création d'un fichier : son nom s'il est dans le dossier affiché,
    /// son chemin entier s'il a été créé ailleurs (il n'apparaît alors pas dans la liste).
    public static func createdToast(path: String, folder: String, branch: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        let shown = isDirectChild(path, of: folder) ? name : path
        return "« \(shown) » créé sur \(branch)"
    }

    /// Une taille de fichier à la française : « 840 o », « 1,2 Ko », « 3 Mo ».
    public static func size(_ bytes: Int) -> String {
        if bytes < 1_000 { return "\(max(0, bytes)) o" }
        if bytes < 1_000_000 { return FileEditorDisplay.decimal(Double(bytes) / 1_000) + " Ko" }
        return FileEditorDisplay.decimal(Double(bytes) / 1_000_000) + " Mo"
    }
}

/// Logique d'affichage de « Joindre un fichier » (chat) : ce que coûte un fichier avant
/// de le joindre, et ceux qui ne peuvent pas l'être. Testable sous Linux.
public enum AttachDisplay {
    /// Extensions de fichiers qui ne sont pas du texte (images, archives, polices…).
    static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "ico", "bmp", "tiff", "icns", "pdf",
        "zip", "gz", "tar", "tgz", "7z", "rar", "jar", "xcarchive", "ipa", "apk", "aab",
        "ttf", "otf", "woff", "woff2", "mp3", "wav", "m4a", "aac", "mp4", "mov", "avi",
        "exe", "dll", "so", "dylib", "a", "o", "bin", "dat", "db", "sqlite", "keystore",
        "p12", "mobileprovision", "car", "nib",
    ]

    /// Faux pour un fichier qui n'est sûrement pas du texte : inutile de le télécharger.
    public static func canAttach(_ item: ContentItem) -> Bool {
        guard !item.isDir, let dot = item.name.lastIndex(of: "."), dot != item.name.startIndex else { return !item.isDir }
        return !binaryExtensions.contains(item.name[item.name.index(after: dot)...].lowercased())
    }

    /// Vrai si le fichier dépasse la limite d'une pièce jointe (seul le début partira).
    public static func isCut(_ item: ContentItem) -> Bool {
        (item.size ?? 0) > ChatAttachment.maxChars
    }

    /// La ligne sous le nom d'un fichier : « 12 Ko · ≈ 3k tokens » ; pour un gros fichier,
    /// « 240 Ko · seul le début sera joint (≈ 15k tokens) » ; « Ne peut pas être joint »
    /// pour une image ou une archive. Vide si la taille est inconnue.
    public static func detail(_ item: ContentItem) -> String {
        guard canAttach(item) else { return "Ne peut pas être joint (pas du texte)" }
        guard let bytes = item.size else { return "" }
        if bytes == 0 { return "Fichier vide" }
        if isCut(item) {
            return FilesDisplay.size(bytes) + " · seul le début sera joint (≈ "
                + ChatDisplay.compact(ChatAttachment.maxChars / 4) + " tokens)"
        }
        let tokens = max(1, bytes / 4)
        return FilesDisplay.size(bytes) + " · ≈ " + ChatDisplay.compact(tokens) + (tokens == 1 ? " token" : " tokens")
    }

    /// Ce que lit VoiceOver pour un fichier : nom, puis détail.
    public static func accessibility(_ item: ContentItem) -> String {
        let d = detail(item).replacingOccurrences(of: "≈ ", with: "environ ").replacingOccurrences(of: " · ", with: ", ")
        return d.isEmpty ? item.name : item.name + ", " + d
    }

    /// Le titre de l'état vide : dossier vide ou recherche sans résultat.
    public static func emptyTitle(query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty ? "Dossier vide" : "Aucun résultat pour « \(q) »"
    }

    /// Feuille ouverte sans compte GitHub : la connexion se fait sur place (avant : « dans
    /// l'onglet Code », il fallait fermer la feuille, changer d'onglet, puis revenir).
    public static let signInTitle = "Connectez GitHub"
    public static let signInText = "Pour joindre un fichier d'un de vos dépôts. La connexion se fait ici, sans quitter la conversation."
    public static let signInButton = "Se connecter à GitHub"

    /// Aucun dépôt sur le compte : dire que la liste a bien été chargée.
    public static let noRepoText = "Votre compte GitHub n'a encore aucun dépôt."
}

/// Logique d'affichage de l'éditeur de fichier (fiche d'un dépôt), testable sous Linux.
public enum FileEditorDisplay {
    /// Boutons proposés après un conflit (fichier changé sur GitHub pendant la modification).
    public static let keepMine = "Garder mon texte"
    public static let takeTheirs = "Reprendre celle de GitHub"

    /// Vrai si l'enregistrement a été refusé parce que le fichier a changé sur GitHub depuis
    /// son ouverture : l'écran propose alors de recharger sans quitter (jamais pour un
    /// nouveau fichier, qui n'a pas de version à recharger).
    public static func isConflict(_ error: any Error, isNew: Bool) -> Bool {
        !isNew && (error as? GitHubError)?.status == 409
    }

    /// Ce qu'on affiche quand l'enregistrement échoue, en mots simples pour les refus
    /// courants de GitHub (sinon le message d'origine) : 409, le fichier a changé depuis
    /// son ouverture ; 422 sur un nouveau fichier, le chemin est déjà pris ; 403 et 404,
    /// pas le droit d'écrire (ou branche disparue).
    public static func saveError(_ error: any Error, path: String, branch: String, isNew: Bool) -> String {
        guard let status = (error as? GitHubError)?.status else { return error.localizedDescription }
        let name = path.trimmingCharacters(in: .whitespaces)
        switch status {
        case 409 where isNew:
            return "La branche \(branch) vient de changer sur GitHub. Réessayez."
        case 409:
            return "Ce fichier a changé sur GitHub depuis son ouverture. « \(keepMine) » : votre texte "
                + "sera comparé à la nouvelle version avant d'enregistrer. « \(takeTheirs) » : "
                + "vos modifications sont abandonnées."
        case 422 where isNew:
            return "Un fichier existe déjà à « \(name) » sur \(branch). Choisissez un autre nom."
        case 403, 404:
            return "Enregistrement refusé : vous n'avez pas le droit d'écrire sur \(branch), "
                + "ou cette branche n'existe plus."
        default:
            return error.localizedDescription
        }
    }

    /// Le message de commit proposé (et utilisé si le champ reste vide) :
    /// « Ajoute docs/a.md » ou « Met à jour a.md ».
    public static func defaultMessage(path: String, isNew: Bool) -> String {
        let p = path.trimmingCharacters(in: .whitespaces)
        if isNew { return "Ajoute \(p)" }
        let name = p.split(separator: "/").last.map(String.init) ?? p
        return "Met à jour \(name)"
    }

    /// Ce qui empêche d'enregistrer un nouveau fichier à ce chemin, en mots simples ;
    /// nil si le chemin convient.
    public static func pathProblem(_ path: String) -> String? {
        let p = path.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return "Indique le nom du fichier." }
        if p.hasPrefix("/") { return "Le chemin ne doit pas commencer par « / »." }
        if p.hasSuffix("/") { return "Ajoute le nom du fichier après « / »." }
        let parts = p.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains(where: { $0.isEmpty }) { return "Le chemin contient « // »." }
        if parts.contains(where: { $0 == "." || $0 == ".." }) { return "Le chemin ne peut pas contenir « . » ou « .. »." }
        return nil
    }

    /// La taille d'un texte, lue aussi par VoiceOver : « 42 lignes · 1,2 Ko ».
    public static func summary(_ text: String) -> String {
        guard !text.isEmpty else { return "Fichier vide" }
        var lines = text.reduce(into: 1) { n, c in if c.isNewline { n += 1 } }
        if text.last?.isNewline == true { lines -= 1 }
        let bytes = text.utf8.count
        return (lines == 1 ? "1 ligne" : "\(lines) lignes") + " · " + FilesDisplay.size(bytes)
    }

    /// Lignes ajoutées et retirées entre le fichier lu et le texte modifié, ou nil
    /// si l'un des deux dépasse `maxLines` lignes (calcul évité à chaque frappe).
    public static func lineChanges(old: String, new: String, maxLines: Int = 3_000) -> (added: Int, removed: Int)? {
        let a = old.split(separator: "\n", omittingEmptySubsequences: false)
        let b = new.split(separator: "\n", omittingEmptySubsequences: false)
        guard a.count <= maxLines, b.count <= maxLines else { return nil }
        var added = 0, removed = 0
        for change in b.difference(from: a) {
            switch change {
            case .insert: added += 1
            case .remove: removed += 1
            }
        }
        return (added, removed)
    }

    /// Ce qui sera enregistré, au-dessus du bouton : « +3 −1 · sur main ».
    /// Sans décompte (fichier trop long) : « Sur main ».
    public static func changeLine(old: String, new: String, branch: String) -> String {
        guard let c = lineChanges(old: old, new: new) else { return "Sur \(branch)" }
        return "+\(c.added) −\(c.removed) · sur \(branch)"
    }

    /// La même chose pour VoiceOver : « 3 lignes ajoutées, 1 retirée, sur main ».
    public static func changeAccessibility(old: String, new: String, branch: String) -> String {
        guard let c = lineChanges(old: old, new: new) else { return "Enregistrement sur \(branch)" }
        let added = c.added == 1 ? "1 ligne ajoutée" : "\(c.added) lignes ajoutées"
        let removed = c.removed == 1 ? "1 retirée" : "\(c.removed) retirées"
        return "\(added), \(removed), sur \(branch)"
    }

    /// Titre de la confirmation avant de quitter sans enregistrer : il nomme le
    /// fichier (« Abandonner les modifications de main.dart ? »). Nouveau fichier :
    /// « Abandonner le nouveau fichier notes.md ? » (sans nom tant qu'il n'en a pas).
    public static func leaveTitle(path: String, isNew: Bool) -> String {
        let name = path.split(separator: "/").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if isNew {
            return name.isEmpty ? "Abandonner ce nouveau fichier ?" : "Abandonner le nouveau fichier \(name) ?"
        }
        return name.isEmpty ? "Abandonner les modifications ?" : "Abandonner les modifications de \(name) ?"
    }

    /// Ce qui sera perdu, sous le titre : « 3 lignes ajoutées, 1 retirée : rien n'est
    /// enregistré, ces changements seront perdus. » Nouveau fichier : le texte écrit.
    public static func leaveMessage(old: String, new: String, isNew: Bool) -> String {
        if isNew {
            return "Ce fichier n'est pas enregistré : le texte écrit (\(summary(new))) sera perdu."
        }
        guard let c = lineChanges(old: old, new: new) else {
            return "Rien n'est enregistré : ces changements seront perdus."
        }
        let added = c.added == 1 ? "1 ligne ajoutée" : "\(c.added) lignes ajoutées"
        let removed = c.removed == 1 ? "1 retirée" : "\(c.removed) retirées"
        return "\(added), \(removed) : rien n'est enregistré, ces changements seront perdus."
    }

    /// Une décimale à la française, sans « ,0 » : 1,2 ; 12.
    static func decimal(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        if r == r.rounded() { return String(Int(r)) }
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }
}
