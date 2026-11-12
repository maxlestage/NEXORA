import NexoraKit
import SwiftUI

/// « Sélectionner un modèle » : les modèles principaux du fournisseur, un modèle de
/// chaque autre fournisseur prêt, l'effort, et tous les autres modèles
/// (`ui/widgets/model_sheet.dart`).
struct ModelSheet: View {
    let current: ModelRef
    let level: ThinkLevel
    let onModel: (ModelRef) -> Void
    let onLevel: (ThinkLevel) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var effort: ThinkLevel
    @State private var path: [String] = []
    @State private var morePicker = false
    @State private var addModels = false
    @State private var picked = 0

    init(current: ModelRef, level: ThinkLevel, onModel: @escaping (ModelRef) -> Void, onLevel: @escaping (ThinkLevel) -> Void) {
        self.current = current
        self.level = level
        self.onModel = onModel
        self.onLevel = onLevel
        _effort = State(initialValue: level)
    }

    private var provider: ProviderDef? { settings.provider(current.providerId) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(featured, id: \.key) { r in
                        row(title: settings.displayName(r), subtitle: blurb(r), checked: r == current) { pick(r) }
                    }
                }
                // Changer de fournisseur d'un geste : le meilleur modèle de chacun de
                // ceux qui sont prêts.
                if !others.isEmpty {
                    Section {
                        ForEach(others, id: \.key) { r in
                            let p = settings.provider(r.providerId)
                            row(title: "\(p?.emoji ?? "🤖") \(settings.displayName(r))", subtitle: p?.name ?? r.providerId, checked: false) { pick(r) }
                        }
                    }
                }
                if settings.readyProviders.filter({ !$0.local }).count <= 2 {
                    Section {
                        Button {
                            addModels = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Ajouter des modèles").foregroundStyle(.primary)
                                    Text(ModelList.addModelsHint(providerId: current.providerId))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "key.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink(value: "effort") {
                        LabeledContent("Effort", value: effort.label)
                    }
                }
                Section {
                    Button {
                        morePicker = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Plus de modèles").foregroundStyle(.primary)
                                Text("\(provider?.name ?? current.providerId) et tous les autres fournisseurs")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Sélectionner un modèle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { _ in
                EffortPage(current: effort, provider: provider, model: current.model) { l in
                    onLevel(l)
                    effort = l
                    path.removeAll()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: picked) { _, _ in settings.haptics }
        .sheet(isPresented: $morePicker) {
            ModelPickerSheet(selected: current) { r in
                onModel(r)
                dismiss()
            }
        }
        .sheet(isPresented: $addModels) {
            ProvidersView()
        }
        .task {
            // La vraie liste du fournisseur, si elle n'a jamais été chargée.
            if let p = provider, settings.isReady(p), !settings.hasLiveModels(p.id), p.listing != .none {
                _ = try? await settings.refreshModels(p.id)
            }
        }
    }

    private var featured: [ModelRef] {
        ModelList.featured(current: current, catalog: settings.catalog, models: provider.map { settings.models(for: $0) } ?? [])
    }

    private var others: [ModelRef] {
        Array(settings.readyProviders.filter { $0.id != current.providerId }.compactMap { p in
            settings.models(for: p).first.map { ModelRef(p.id, $0.id) }
        }.prefix(6))
    }

    private func blurb(_ r: ModelRef) -> String {
        if let b = ModelList.familyBlurb(r.model) { return b }
        guard let p = settings.provider(r.providerId) else { return r.model }
        return settings.models(for: p).first { $0.id == r.model }.map { $0.detail ?? r.model } ?? r.model
    }

    private func pick(_ r: ModelRef) {
        picked += 1
        onModel(r)
        dismiss()
    }

    private func row(title: String, subtitle: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if checked {
                    Image(systemName: "checkmark").font(.title3.weight(.semibold)).foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// La page « Effort » : Faible → Max, avec la coche sur le choix courant.
struct EffortPage: View {
    let current: ThinkLevel
    var provider: ProviderDef?
    var model: String?
    var title = "Effort"
    let onPicked: (ThinkLevel) -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var tapped = 0

    var body: some View {
        List {
            EffortList(current: current, provider: provider, model: model) { l in
                tapped += 1
                onPicked(l)
            }
        }
        .sensoryFeedback(.selection, trigger: tapped) { _, _ in settings.haptics }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// La liste des efforts (Faible → Max) et la note sur la consommation.
struct EffortList: View {
    let current: ThinkLevel
    var provider: ProviderDef?
    var model: String?
    let onPicked: (ThinkLevel) -> Void

    var body: some View {
        Section {
            ForEach(ThinkLevel.allCases) { l in
                Button {
                    onPicked(l)
                } label: {
                    HStack(spacing: 10) {
                        Text(l.label).foregroundStyle(.primary)
                        EffortBadge(level: l)
                        Spacer()
                        if l == current {
                            Image(systemName: "checkmark").font(.title3.weight(.semibold)).foregroundStyle(.tint)
                        }
                    }
                }
                .accessibilityHint(l.summary)
                .accessibilityAddTraits(l == current ? .isSelected : [])
            }
        } footer: {
            Text(ModelList.effortNote(provider, model: model))
        }
    }
}

/// Un badge : « Recommandé », ou un avertissement de consommation.
struct EffortBadge: View {
    let level: ThinkLevel

    var body: some View {
        if let b = level.badge {
            let warn = level.warning
            HStack(spacing: 4) {
                if warn { Image(systemName: "exclamationmark.triangle").font(.caption) }
                Text(b).font(.footnote.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(warn ? Color(hex: 0x8A5A00) : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(warn ? Color(hex: 0xF6DFA4) : Color.primary.opacity(0.08), in: .capsule)
        }
    }
}

/// Cinq barres, comme un indicateur de réseau : l'effort en un coup d'œil.
struct LevelBars: View {
    let level: ThinkLevel
    var color: Color = .accentColor

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<ThinkLevel.allCases.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= level.index ? color : color.opacity(0.2))
                    .frame(width: 3.5, height: 4 + CGFloat(i) * 2.5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Effort \(level.label)")
    }
}

/// Le bouton du haut de la conversation : « Opus 5.5 · Élevé ⌄ ».
struct ModelEffortButton: View {
    let current: ModelRef
    let level: ThinkLevel
    let onModel: (ModelRef) -> Void
    let onLevel: (ThinkLevel) -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 6) {
                Text(settings.provider(current.providerId)?.emoji ?? "🤖")
                // Le nom rétrécit (avec « … ») plutôt que de déborder de la barre.
                Text("\(settings.displayName(current)) · \(level.label)")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // Une pastille, comme le choix de l'agent à côté.
            .background(.fill.tertiary, in: .capsule)
            // Zone touchable d'au moins 44 pt de haut, sans changer la mise en page.
            .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Modèle \(settings.displayName(current)), effort \(level.label)")
        .accessibilityHint("Changer de modèle ou d'effort")
        .sheet(isPresented: $open) {
            ModelSheet(current: current, level: level, onModel: onModel, onLevel: onLevel)
                .presentationDetents([.medium, .large])
        }
    }
}
