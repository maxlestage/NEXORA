import ImageIO
import NexoraKit
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Préparation des images (hors du fil principal)

/// Une image CoreGraphics passée d'une tâche à l'autre (elle n'est jamais modifiée).
struct CGImageBox: @unchecked Sendable {
    let image: CGImage
}

/// Réduire, convertir et lire les images avec ImageIO (sûr hors du fil principal).
enum ImagePrep {
    /// L'image réduite (côté le plus long : `maxSide`) et recompressée en JPEG,
    /// orientation appliquée. `nil` si les octets ne sont pas une image.
    static func jpeg(_ data: Data, maxSide: Int = ChatImages.maxSide, quality: Double = ChatImages.jpegQuality) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = downscaled(src, maxSide: maxSide) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// Une vignette d'un fichier image.
    static func thumbnail(_ url: URL, maxSide: Int) -> CGImageBox? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = downscaled(src, maxSide: maxSide) else { return nil }
        return CGImageBox(image: cg)
    }

    /// Une vignette d'octets d'image.
    static func thumbnail(_ data: Data, maxSide: Int) -> CGImageBox? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = downscaled(src, maxSide: maxSide) else { return nil }
        return CGImageBox(image: cg)
    }

    private static func downscaled(_ src: CGImageSource, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}

/// Une photo prête à joindre au prochain message (réduite, en JPEG).
struct ChatPhotoDraft: Identifiable {
    let id = UUID()
    let data: Data
    let preview: UIImage

    /// Réduit la photo (côté max ~1568 px, JPEG ~0,8) hors du fil principal.
    @MainActor
    static func make(_ raw: Data) async -> ChatPhotoDraft? {
        let prepared: (Data, CGImageBox)? = await Task.detached(priority: .userInitiated) { () -> (Data, CGImageBox)? in
            guard let jpeg = ImagePrep.jpeg(raw), let thumb = ImagePrep.thumbnail(jpeg, maxSide: 240) else { return nil }
            return (jpeg, thumb)
        }.value
        guard let prepared else { return nil }
        return ChatPhotoDraft(data: prepared.0, preview: UIImage(cgImage: prepared.1.image))
    }
}

// MARK: - Appareil photo

/// L'appareil photo (UIImagePickerController) : rend la photo prise, en JPEG.
struct NexoraCameraPicker: UIViewControllerRepresentable {
    var onPick: (Data) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (Data) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                onPick(data)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

// MARK: - Photos jointes (barre de saisie)

/// Les photos jointes au prochain message : vignettes retirables.
struct PhotoDraftStrip: View {
    @Binding var photos: [ChatPhotoDraft]
    var loading = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos) { p in
                    Image(uiImage: p.preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) { photos.removeAll { $0.id == p.id } }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("Retirer la photo")
                        }
                        .padding(.top, 5)
                        .padding(.trailing, 5)
                }
                if loading {
                    ProgressView()
                        .frame(width: 58, height: 58)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                }
            }
        }
    }
}

/// Un bouton « Photo » (photothèque) qui ajoute des photos réduites à `photos`
/// (4 au plus) : pour les instructions de l'agent autonome.
struct PhotoAttachButton: View {
    @Binding var photos: [ChatPhotoDraft]
    @Binding var loading: Bool

    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $items,
            maxSelectionCount: max(1, ChatImages.maxPerMessage - photos.count),
            matching: .images,
            preferredItemEncoding: .compatible
        ) {
            Image(systemName: "photo.badge.plus")
                .font(.title3)
                .frame(width: 34, height: 34)
        }
        .disabled(photos.count >= ChatImages.maxPerMessage || loading)
        .accessibilityLabel("Joindre des photos")
        .onChange(of: items) { _, picked in
            guard !picked.isEmpty else { return }
            items = []
            Task { await add(picked) }
        }
    }

    private func add(_ picked: [PhotosPickerItem]) async {
        loading = true
        for item in picked {
            guard photos.count < ChatImages.maxPerMessage else { break }
            if let raw = try? await item.loadTransferable(type: Data.self), let draft = await ChatPhotoDraft.make(raw) {
                photos.append(draft)
            }
        }
        loading = false
    }
}

// MARK: - Images enregistrées

/// Une image de la conversation (fichier sur l'appareil), chargée en vignette.
struct ChatImageThumb: View {
    let name: String
    var maxSide = 600
    /// Toute l'image visible (plein écran), sinon recadrée pour remplir.
    var fit = false

    @State private var image: UIImage?
    @State private var missing = false

    var body: some View {
        // Déjà décodée (bulle revenue à l'écran) : affichée tout de suite.
        let shown = image ?? ChatThumbCache.image(name, maxSide: maxSide)
        ZStack {
            if let image = shown {
                if fit {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            } else {
                Rectangle().fill(fit ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.fill.tertiary))
                if missing {
                    Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        }
        .task(id: name) {
            let side = maxSide
            if let hit = ChatThumbCache.image(name, maxSide: side) {
                image = hit
                return
            }
            guard let url = ChatImageStore.standard.url(name) else {
                missing = true
                return
            }
            let box = await Task.detached(priority: .userInitiated) { ImagePrep.thumbnail(url, maxSide: side) }.value
            if let box {
                let decoded = UIImage(cgImage: box.image)
                ChatThumbCache.store(decoded, name, maxSide: side)
                image = decoded
            } else {
                missing = true
            }
        }
    }
}

/// Les vignettes déjà décodées, gardées en mémoire : une bulle qui revient à
/// l'écran (défilement, retour dans la conversation) n'est pas relue sur le
/// disque ni redécodée. iOS vide ce cache si la mémoire manque.
@MainActor
enum ChatThumbCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        // Environ 40 Mo de pixels décodés.
        c.totalCostLimit = 40 * 1024 * 1024
        return c
    }()

    /// Les images en plein écran (très grandes) ne sont pas gardées.
    private static let maxCachedSide = 1000

    private static func key(_ name: String, _ side: Int) -> NSString { "\(side)|\(name)" as NSString }

    static func image(_ name: String, maxSide: Int) -> UIImage? {
        guard maxSide <= maxCachedSide else { return nil }
        return cache.object(forKey: key(name, maxSide))
    }

    static func store(_ image: UIImage, _ name: String, maxSide: Int) {
        guard maxSide <= maxCachedSide else { return }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key(name, maxSide), cost: cost)
    }
}

/// Les images à afficher en plein écran (à partir de la `start`-ième).
struct ChatImageViewerItem: Identifiable {
    let names: [String]
    let start: Int
    var id: String { names.joined(separator: ",") + "#\(start)" }
}

/// Les images d'un message : petites vignettes (vos photos) ou grille (images
/// créées). Toucher une image l'ouvre en plein écran.
struct ChatImageGrid: View {
    let names: [String]
    /// Grande grille (images créées) ou vignettes alignées à droite (vos photos).
    var large = false
    var onOpen: (Int) -> Void

    var body: some View {
        if large {
            let columns = names.count > 1 ? [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)] : [GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                    tile(n, i)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .frame(maxWidth: names.count > 1 ? 520 : 360)
        } else {
            HStack(spacing: 6) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                    tile(n, i).frame(width: names.count > 2 ? 72 : 110, height: names.count > 2 ? 72 : 110)
                }
            }
        }
    }

    private func tile(_ name: String, _ i: Int) -> some View {
        Button {
            onOpen(i)
        } label: {
            Color.clear
                .overlay { ChatImageThumb(name: name, maxSide: large ? 900 : 360) }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Image \(i + 1) sur \(names.count)")
        .accessibilityHint("Ouvrir en plein écran")
    }
}

/// Les URL des fichiers d'images existants.
func chatImageURLs(_ names: [String]) -> [URL] {
    names.compactMap { ChatImageStore.standard.url($0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
}

/// Enregistre des images dans la photothèque (ajout seulement).
enum PhotoLibrarySaver {
    /// Rend le message à afficher.
    @MainActor
    static func save(_ urls: [URL]) async -> (text: String, ok: Bool) {
        guard !urls.isEmpty else { return ("Image introuvable sur l'appareil.", false) }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return ("Autorisez NEXORA à ajouter des photos : Réglages → NEXORA → Photos.", false)
        }
        do {
            try await add(urls)
            return (urls.count > 1 ? "\(urls.count) images enregistrées dans Photos" : "Image enregistrée dans Photos", true)
        } catch {
            return ("Impossible d'enregistrer dans Photos : \(error.localizedDescription)", false)
        }
    }

    /// Hors du fil principal : Photos appelle le bloc sur sa propre file.
    nonisolated private static func add(_ urls: [URL]) async throws {
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            for u in urls {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: u, options: nil)
            }
        }
    }
}

// MARK: - Plein écran

/// Les images en plein écran : balayer pour passer de l'une à l'autre, pincer
/// pour zoomer ; partager ou enregistrer dans Photos.
struct ChatImageViewer: View {
    let names: [String]
    @State var index: Int

    @Environment(\.dismiss) private var dismiss
    @State private var toast: Toast?
    @State private var saving = false

    init(names: [String], start: Int) {
        self.names = names
        _index = State(initialValue: min(max(start, 0), max(names.count - 1, 0)))
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(names.enumerated()), id: \.offset) { i, n in
                    ZoomableChatImage(name: n).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: names.count > 1 ? .automatic : .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(names.count > 1 ? "\(index + 1) / \(names.count)" : "Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url = chatImageURLs([names.indices.contains(index) ? names[index] : ""]).first {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Partager")
                        Button {
                            save(url)
                        } label: {
                            Image(systemName: saving ? "hourglass" : "square.and.arrow.down")
                        }
                        .disabled(saving)
                        .accessibilityLabel("Enregistrer dans Photos")
                    }
                }
            }
            .toast($toast)
        }
    }

    private func save(_ url: URL) {
        saving = true
        Task {
            let r = await PhotoLibrarySaver.save([url])
            saving = false
            toast = Toast(text: r.text, error: !r.ok)
        }
    }
}

/// Une image en plein écran : pincer pour zoomer, toucher deux fois pour
/// zoomer ou revenir.
private struct ZoomableChatImage: View {
    let name: String
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ChatImageThumb(name: name, maxSide: 2400, fit: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(max(base * v.magnification, 1), 5) }
                    .onEnded { _ in
                        base = scale
                        if scale <= 1 { reset() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset },
                including: scale > 1 ? .all : .subviews
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale > 1 { reset() } else {
                        scale = 2.5
                        base = 2.5
                    }
                }
            }
    }

    private func reset() {
        scale = 1
        base = 1
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Images créées (réponse)

/// Une réponse « images créées » : la grille, puis Enregistrer dans Photos,
/// Partager, Refaire et le coût (« gratuit » avec Pollinations).
struct GeneratedImagesView: View {
    let message: ChatMessage
    let streaming: Bool
    var onRedo: (() -> Void)?

    @State private var viewer: ChatImageViewerItem?
    @State private var toast: Toast?
    @State private var saving = false

    private var urls: [URL] { chatImageURLs(message.images) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.images.isEmpty && streaming {
                placeholder
            } else {
                ChatImageGrid(names: message.images, large: true) { i in
                    viewer = ChatImageViewerItem(names: message.images, start: i)
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                actions
            }
        }
        .padding(.trailing, 24)
        .fullScreenCover(item: $viewer) { v in ChatImageViewer(names: v.names, start: v.start) }
        .toast($toast)
    }

    private var placeholder: some View {
        let n = max(message.imageCount, 1)
        return HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(n > 1 ? "Création de \(n) images…" : "Création de l'image…")
                    .font(.subheadline.weight(.medium))
                Text(message.imagePrompt ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.7), in: .rect(cornerRadius: 18))
    }

    private var costLabel: String {
        if message.model?.hasPrefix("pollinations::") == true { return "gratuit" }
        if let c = message.cost { return "≈ \(ChatDisplay.cost(c))" }
        return ""
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button {
                save()
            } label: {
                Image(systemName: saving ? "hourglass" : "square.and.arrow.down").frame(width: 34, height: 34)
            }
            .disabled(saving || urls.isEmpty)
            .accessibilityLabel("Enregistrer dans Photos")
            if !urls.isEmpty {
                ShareLink(items: urls) {
                    Image(systemName: "square.and.arrow.up").frame(width: 34, height: 34)
                }
                .accessibilityLabel("Partager")
            }
            if let onRedo {
                Button(action: onRedo) {
                    Image(systemName: "arrow.clockwise").frame(width: 34, height: 34)
                }
                .accessibilityLabel("Refaire")
            }
            Text(costLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
    }

    private func save() {
        saving = true
        let list = urls
        Task {
            let r = await PhotoLibrarySaver.save(list)
            saving = false
            toast = Toast(text: r.text, error: !r.ok)
        }
    }
}

// MARK: - Créer une image (feuille)

/// « Créer une image » : la description, le nombre (1 à 4), le format et le
/// moteur utilisé.
struct ImagePromptSheet: View {
    var initial = ""
    /// Le moteur qui sera utilisé (d'après les réglages et la clé OpenAI).
    let engine: ImageGenEngine
    var onCreate: (String, Int) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var count = 1
    @FocusState private var focused: Bool

    /// Le moteur qui sera vraiment utilisé, d'après le choix fait ici.
    private var resolved: ImageGenEngine {
        ImageGenEngine.named(settings.imageEngine).resolved(hasOpenAIKey: settings.hasOwnKey("openai"))
    }

    /// Ce que coûtera la demande, selon le moteur, la qualité, le format et le nombre.
    private var costNote: String {
        if ImageGenEngine.named(settings.imageEngine) == .openai && !settings.hasOwnKey("openai") {
            return "Aucune clé OpenAI enregistrée : ajoutez-la dans Modèles → OpenAI, ou choisissez Pollinations (gratuit)."
        }
        guard resolved == .openai else { return "Pollinations : gratuit, sans clé." }
        let shape = ImageGenShape.named(settings.imageShape)
        let quality = ImageGenQuality.named(settings.imageQuality)
        let images = "\(count) image\(count > 1 ? "s" : "")"
        guard let each = quality.perImage(shape) else {
            return "OpenAI choisit la qualité : jusqu'à ≈ \(ChatDisplay.cost((ImageGenQuality.high.perImage(shape) ?? 0) * Double(count))) pour \(images) (votre clé OpenAI)."
        }
        return "OpenAI, qualité \(quality.label.lowercased()) : ≈ \(ChatDisplay.cost(each * Double(count))) pour \(images) (votre clé OpenAI)."
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    TextField("Un chat astronaute sur la Lune, style aquarelle…", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Astuce : tapez aussi « /image 3 une description » dans le chat.")
                }
                Section("Nombre d'images") {
                    Picker("Nombre", selection: $count) {
                        ForEach(1...ImageGenCommand.maxCount, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Format", selection: $settings.imageShape) {
                        ForEach(ImageGenShape.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Moteur", selection: $settings.imageEngine) {
                        ForEach(ImageGenEngine.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    if resolved == .openai {
                        Picker("Qualité", selection: $settings.imageQuality) {
                            ForEach(ImageGenQuality.allCases, id: \.self) { q in
                                Text(q.priced(ImageGenShape.named(settings.imageShape))).tag(q.rawValue)
                            }
                        }
                    }
                } footer: {
                    Text(costNote)
                }
            }
            .navigationTitle("Créer une image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        onCreate(prompt.trimmingCharacters(in: .whitespacesAndNewlines), count)
                        dismiss()
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if prompt.isEmpty { prompt = initial }
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Réglages

/// Réglages → Images : moteur et format des images créées.
struct ImageSettingsSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        let engine = ImageGenEngine.named(settings.imageEngine)
        Section {
            Picker(selection: $settings.imageEngine) {
                ForEach(ImageGenEngine.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            } label: {
                Label("Moteur", systemImage: "wand.and.stars")
            }
            Picker(selection: $settings.imageShape) {
                ForEach(ImageGenShape.allCases, id: \.self) { s in
                    Text("\(s.label) (\(s.width)×\(s.height))").tag(s.rawValue)
                }
            } label: {
                Label("Format", systemImage: "aspectratio")
            }
            Picker(selection: $settings.imageQuality) {
                ForEach(ImageGenQuality.allCases, id: \.self) { q in
                    Text(q.priced(ImageGenShape.named(settings.imageShape))).tag(q.rawValue)
                }
            } label: {
                Label("Qualité (OpenAI)", systemImage: "sparkles")
            }
        } header: {
            Text("Images")
        } footer: {
            Text(engine.detail + keyNote(engine)
                + " Créez des images avec le trombone → « Créer une image », ou « /image 3 une description ».")
        }
    }

    private func keyNote(_ engine: ImageGenEngine) -> String {
        if settings.hasOwnKey("openai") { return "" }
        switch engine {
        case .auto: return " Aucune clé OpenAI enregistrée : Pollinations sera utilisé."
        case .openai: return " Aucune clé OpenAI enregistrée : ajoutez-la dans Fournisseurs → OpenAI."
        case .pollinations: return ""
        }
    }
}
