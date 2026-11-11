import NexoraKit
import SwiftUI

/// La fiche détaillée du témoin d'un fournisseur : jauge, crédit, solde prépayé,
/// limites de débit, dépense estimée, ce que NEXORA a compté, dernier incident.
struct QuotaSheet: View {
    let providerId: String

    @Environment(SettingsStore.self) private var settings
    @Environment(UsageStore.self) private var usage
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: AmountPrompt?
    @State private var amount = ""

    private enum AmountPrompt {
        case prepaid, budget
    }

    var body: some View {
        NavigationStack {
            Group {
                if let p = settings.provider(providerId) {
                    content(p)
                } else {
                    ContentUnavailableView("Fournisseur introuvable", systemImage: "questionmark.circle")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func content(_ p: ProviderDef) -> some View {
        let u = usage.of(p.id)
        let now = Date()
        let level = u.level(now)
        let priced = ModelPrices.fixed[p.id] != nil
        let canFetch = QuotaService.canFetch(p)
        let freeTier = QuotaHelp.freeTier(p.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(p, level: level, canFetch: canFetch)
                UsageGauge(ratio: u.displayRatio, color: level.color, label: UsageText.summary(p, u, now: now))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                Text(UsageText.source(p, u, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if let b = u.balance {
                    UsageSectionTitle("Crédit")
                    UsageCard {
                        if let r = b.remaining { UsageRow("Restant", b.money(r)) }
                        if let x = b.used { UsageRow("Utilisé", b.money(x)) }
                        if let t = b.total { UsageRow("Total acheté / plafond", b.money(t)) }
                        if let free = b.freeTier { UsageRow("Type de compte", free ? "Offre gratuite" : "Crédit acheté") }
                        if let note = b.note {
                            Text(note).font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                        }
                    }
                }

                if !canFetch && !p.local && (p.needsKey || !p.free) {
                    prepaidSection(p, u, level: level, priced: priced)
                }

                if !u.windows.isEmpty {
                    UsageSectionTitle("Limites de débit")
                    ForEach(Array(u.windows.enumerated()), id: \.offset) { _, w in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(UsageText.windowTitle(w)).fontWeight(.semibold)
                                Spacer()
                                Text(w.label).font(.system(.footnote, design: .monospaced))
                            }
                            ProgressView(value: w.ratio ?? 0)
                                .tint((w.ratio ?? 1) < 0.2 ? Theme.amber : Theme.accent(settings.accent))
                            if let reset = w.reset {
                                Text("Repart dans \(reset)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }

                if priced || u.monthlyBudget != nil {
                    budgetSection(p, u, level: level)
                }

                UsageSectionTitle("Compté par NEXORA")
                UsageCard {
                    UsageRow("Requêtes aujourd'hui", "\(u.requestsToday)")
                    UsageRow(
                        "Tokens aujourd'hui",
                        "\(UsageFormat.compact(u.tokensToday)) (\(UsageFormat.compact(u.tokensInToday)) envoyés · \(UsageFormat.compact(u.tokensOutToday)) reçus)"
                    )
                    UsageRow("Depuis le début", "\(u.requestsTotal) req · \(UsageFormat.compact(u.tokensTotal)) tokens")
                    if u.estimated {
                        Text("≈ Une partie est estimée (environ 4 caractères par token) : ce fournisseur n'indique pas toujours le décompte exact.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                }

                if let status = u.lastErrorStatus, let at = u.lastErrorAt {
                    UsageSectionTitle("Dernier incident")
                    UsageCard(glow: Theme.red) {
                        Text(UsageText.error(status)).fontWeight(.bold)
                        Text("\(u.lastErrorMessage ?? "") · \(UsageText.ago(at, now: now))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let freeTier {
                    UsageSectionTitle("Offre gratuite")
                    Text(freeTier)
                }

                footer(p)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .alert(promptTitle(p), isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField(prompt == .budget ? "$ par mois" : "Ex. : 18.40", text: $amount)
                .keyboardType(.decimalPad)
            Button("Annuler", role: .cancel) { prompt = nil }
            Button("OK") { applyPrompt(p) }
        }
    }

    private func header(_ p: ProviderDef, level: UsageLevel, canFetch: Bool) -> some View {
        HStack(spacing: 12) {
            ProviderBadge(provider: p, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.title2.weight(.heavy))
                Text(UsageText.level(level)).font(.caption).foregroundStyle(level.color)
            }
            Spacer()
            if canFetch {
                if usage.isRefreshing(p.id) {
                    ProgressView()
                } else {
                    Button {
                        Task { await usage.refresh(p, key: settings.key(p.id)) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Actualiser")
                }
            }
        }
    }

    @ViewBuilder
    private func prepaidSection(_ p: ProviderDef, _ u: ProviderUsage, level: UsageLevel, priced: Bool) -> some View {
        UsageSectionTitle("Crédit prépayé")
        UsageCard(glow: u.prepaid == nil ? nil : level.color) {
            if let prepaid = u.prepaid {
                UsageRow("Restant (estimé)", "≈ \(UsageFormat.dollars(u.prepaidLeft ?? 0))")
                UsageRow("Solde indiqué", UsageFormat.dollars(prepaid))
                UsageRow("Dépensé depuis", "≈ \(UsageFormat.dollars(u.prepaidSpent))\(priced ? "" : " (prix inconnus)")")
                    .padding(.bottom, 8)
            }
            Text(
                u.prepaid == nil
                    ? "\(p.name) ne donne pas votre solde par l'API. Recopiez-le une fois depuis sa page de facturation : NEXORA déduit ensuite chaque réponse (chat et agents autonomes)."
                    : "Recalez le solde de temps en temps avec celui de la page de facturation : l'estimation peut dériver (cache, outils, autres appareils)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            UsageFlow {
                Button {
                    amount = u.prepaidLeft.map { String(format: "%.2f", $0) } ?? ""
                    prompt = .prepaid
                } label: {
                    Label(u.prepaid == nil ? "Indiquer mon solde" : "Mettre à jour le solde", systemImage: "wallet.bifold")
                }
                .buttonStyle(.bordered)
                if let url = (UsageLinks.billing[p.id] ?? UsageLinks.usage[p.id]).flatMap(URL.init(string:)) {
                    Link(destination: url) {
                        Label("Voir ma facturation", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }
                if u.prepaid != nil {
                    Button("Retirer") { usage.setPrepaid(p.id, nil) }
                        .buttonStyle(.borderless)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func budgetSection(_ p: ProviderDef, _ u: ProviderUsage, level: UsageLevel) -> some View {
        UsageSectionTitle("Dépense estimée")
        UsageCard(glow: u.monthlyBudget == nil ? nil : level.color) {
            UsageRow("Ce mois-ci", "≈ \(UsageFormat.dollars(u.costMonth))")
            UsageRow("Aujourd'hui", "≈ \(UsageFormat.dollars(u.costToday))")
            if let budget = u.monthlyBudget {
                UsageRow("Crédit restant", "≈ \(UsageFormat.dollars(max(budget - u.costMonth, 0))) sur \(UsageFormat.dollars(budget))")
            }
            Text("Crédit mensuel de votre offre").font(.subheadline.weight(.semibold)).padding(.top, 8)
            UsageFlow {
                ForEach(ModelPrices.monthlyPlans[p.id] ?? [], id: \.name) { plan in
                    let selected = u.monthlyBudget == plan.amount
                    Button("\(plan.name) · \(UsageFormat.dollars(plan.amount))") { usage.setBudget(p.id, plan.amount) }
                        .buttonStyle(.bordered)
                        .tint(selected ? Theme.accent(settings.accent) : .secondary)
                        .fontWeight(selected ? .bold : .regular)
                }
                Button {
                    amount = u.monthlyBudget.map { String(format: "%.0f", $0) } ?? ""
                    prompt = .budget
                } label: {
                    Label("Autre montant", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                if u.monthlyBudget != nil {
                    Button("Aucun") { usage.setBudget(p.id, nil) }
                        .buttonStyle(.bordered)
                }
            }
            Text("Estimation : tokens × prix publics du \(ModelPrices.pricesDate) (tarif de journée). La page « Consommation » de \(p.name) fait foi.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private func footer(_ p: ProviderDef) -> some View {
        UsageFlow {
            if let url = UsageLinks.usage[p.id].flatMap(URL.init(string:)) {
                Link(destination: url) {
                    Label("Consommation chez \(p.name)", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            }
            NavigationLink {
                ProviderDetailView(providerId: p.id)
            } label: {
                Label("Clé et réglages", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            Button("Remettre à zéro", role: .destructive) { usage.reset(p.id) }
                .buttonStyle(.borderless)
        }
        .padding(.top, 18)
    }

    private func promptTitle(_ p: ProviderDef) -> String {
        prompt == .budget ? "Crédit mensuel" : "Solde chez \(p.name)"
    }

    private func applyPrompt(_ p: ProviderDef) {
        let v = UsageText.parseAmount(amount)
        if let current = prompt {
            switch current {
            case .prepaid: usage.setPrepaid(p.id, v > 0 ? v : nil)
            case .budget: usage.setBudget(p.id, v > 0 ? v : nil)
            }
        }
        prompt = nil
    }
}

/// Une jauge circulaire animée : la part restante, du pâle au vif.
struct UsageGauge: View {
    let ratio: Double?
    let color: Color
    let label: String
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            GaugeArc(progress: 1)
                .stroke(color.opacity(0.15), style: StrokeStyle(lineWidth: 12, lineCap: .round))
            if ratio != nil {
                GaugeArc(progress: shown)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
            }
            VStack(spacing: 2) {
                if ratio != nil {
                    Text(verbatim: "\(Int((shown * 100).rounded())) %")
                        .font(.title.weight(.black))
                        .contentTransition(.numericText(value: shown))
                }
                Text(label)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(26)
        }
        .frame(width: 170, height: 170)
        .onAppear { animate(to: ratio) }
        .onChange(of: ratio) { _, new in animate(to: new) }
        .accessibilityElement(children: .combine)
    }

    /// Le dégradé commence au milieu du vide du bas : aucun raccord sur l'arc.
    private var gradient: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: color.opacity(GaugeGeometry.paleOpacity), location: 0),
                .init(color: color.opacity(GaugeGeometry.paleOpacity), location: GaugeGeometry.arcStartLocation),
                .init(color: color, location: GaugeGeometry.arcEndLocation),
                .init(color: color, location: 1),
            ],
            center: .center,
            startAngle: .degrees(GaugeGeometry.gradientStart),
            endAngle: .degrees(GaugeGeometry.gradientStart + 360)
        )
    }

    private func animate(to r: Double?) {
        withAnimation(.easeOut(duration: 0.9)) { shown = r ?? 1 }
    }
}

/// L'arc de la jauge (135° → 405°), tracé jusqu'à `progress`.
struct GaugeArc: Shape {
    var progress: Double

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 10, dy: 10)
        var p = Path()
        p.addArc(
            center: CGPoint(x: r.midX, y: r.midY),
            radius: min(r.width, r.height) / 2,
            startAngle: .degrees(GaugeGeometry.start),
            endAngle: .degrees(GaugeGeometry.start + GaugeGeometry.sweep * max(0, min(progress, 1))),
            clockwise: false
        )
        return p
    }
}

// MARK: - Petits éléments communs

struct UsageSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 14)
    }
}

/// Une carte au fond discret, avec un liseré de couleur au besoin.
struct UsageCard<Content: View>: View {
    var glow: Color?
    let content: Content

    init(glow: Color? = nil, @ViewBuilder content: () -> Content) {
        self.glow = glow
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 16))
        .overlay {
            if let glow {
                RoundedRectangle(cornerRadius: 16).strokeBorder(glow.opacity(0.45))
            }
        }
    }
}

/// Une ligne « libellé … valeur ».
struct UsageRow: View {
    let key: String
    let value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.bold)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

/// Des boutons qui passent à la ligne quand la place manque.
struct UsageFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
