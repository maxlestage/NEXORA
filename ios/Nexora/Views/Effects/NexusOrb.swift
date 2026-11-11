import SwiftUI

/// Le logo vivant de NEXORA : un icosaèdre en 3D (projection perspective réelle),
/// une coque de points, des anneaux et des nœuds en orbite reliés au cœur. On le
/// fait tourner du doigt. Respecte le réglage d'animations (toutes, douces, aucune)
/// et « Réduire les animations » d'iOS (`ui/widgets/nexus_orb.dart`).
struct NexusOrb: View {
    var size: CGFloat = 220
    var satellites: Int = 14
    var interactive: Bool = true
    var speed: Double = 1
    /// Pulsation plus forte (pendant qu'un modèle répond).
    var pulse: Bool = false

    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sim = OrbSimulation()

    var body: some View {
        let motion = Motion(rawValue: settings.animations) ?? .full
        // Le mouvement : la vitesse réglée, très ralentie si iOS demande moins de
        // mouvement ; animations coupées : une image fixe.
        let rate = speed * motion.speed * (reduceMotion ? 0.15 : 1)
        let colors = palette
        let sats = OrbSimulation.satellites(satellites)
        let strong = pulse
        let model = sim
        let canvas = TimelineView(.animation(paused: motion.isOff)) { timeline in
            let now = timeline.date
            Canvas { context, canvasSize in
                model.step(now: now, speed: rate)
                OrbPainter(t: model.t, yaw: model.yaw, pitch: model.pitch, sats: sats, pulse: strong, pal: colors)
                    .paint(&context, size: canvasSize)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Logo NEXORA")
        .accessibilityAddTraits(.isImage)

        if interactive {
            canvas
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { v in sim.drag(to: v.translation) }
                        .onEnded { v in sim.release(velocity: v.velocity) }
                )
        } else {
            canvas
        }
    }

    /// Jeu de couleurs (0 principale, 1 et 2 dégradé) puis vert et ambre.
    private var palette: [Color] {
        let p = Theme.palette(settings.accent).colors
        return [p[0], p[1], p[2], Theme.green, Theme.amber]
    }
}

/// L'état du mouvement de l'orbe : temps, rotation et élan du doigt. Mis à jour à
/// chaque image, sur le fil principal (le dessin et les gestes de SwiftUI), sans
/// redessiner la vue autour.
final class OrbSimulation: @unchecked Sendable {
    private(set) var t: Double = 0
    private(set) var yaw: Double = 0
    private(set) var pitch: Double = -0.35
    private var vyaw: Double = 0
    private var vpitch: Double = 0
    private var last: Date?
    private var lastDrag: CGSize = .zero

    func step(now: Date, speed: Double) {
        let dt = min(max(last.map { now.timeIntervalSince($0) } ?? 0, 0), 0.05)
        last = now
        t += dt * speed
        yaw += 0.25 * speed * dt + vyaw * dt
        pitch = min(max(pitch + vpitch * dt, -1.2), 1.2)
        vyaw *= pow(0.04, dt)
        vpitch *= pow(0.04, dt)
    }

    func drag(to translation: CGSize) {
        let dx = translation.width - lastDrag.width
        let dy = translation.height - lastDrag.height
        lastDrag = translation
        yaw += dx * 0.012
        pitch = min(max(pitch + dy * 0.012, -1.2), 1.2)
    }

    func release(velocity: CGSize) {
        lastDrag = .zero
        vyaw = velocity.width * 0.006
        vpitch = velocity.height * 0.006
    }

    /// Les nœuds en orbite, toujours les mêmes pour un nombre donné.
    static func satellites(_ n: Int) -> [OrbSatellite] {
        var rng = SeededRandom(seed: 7)
        return (0..<n).map { i in
            let radius = 1.55 + rng.next() * 0.85
            let speed = (0.25 + rng.next() * 0.6) * (rng.next() < 0.5 ? 1 : -1)
            let tilt = (rng.next() - 0.5) * 1.6
            let phase = rng.next() * .pi * 2
            let size = 2.5 + rng.next() * 3
            return OrbSatellite(radius: radius, speed: speed, tilt: tilt, phase: phase, slot: i % 5, size: size)
        }
    }
}

/// Un nœud qui orbite autour du cœur.
struct OrbSatellite {
    let radius, speed, tilt, phase: Double
    /// Place dans la palette : 0 à 2 jeu de couleurs, 3 vert, 4 ambre.
    let slot: Int
    let size: Double
}

/// Un générateur pseudo-aléatoire reproductible (SplitMix64).
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// Un nombre dans [0, 1[.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// Un point en 3D.
struct V3 {
    var x, y, z: Double

    func rotY(_ a: Double) -> V3 { V3(x: x * cos(a) + z * sin(a), y: y, z: -x * sin(a) + z * cos(a)) }
    func rotX(_ a: Double) -> V3 { V3(x: x, y: y * cos(a) - z * sin(a), z: y * sin(a) + z * cos(a)) }
    static func * (v: V3, k: Double) -> V3 { V3(x: v.x * k, y: v.y * k, z: v.z * k) }
}

/// Le dessin d'une image de l'orbe.
struct OrbPainter {
    let t, yaw, pitch: Double
    let sats: [OrbSatellite]
    let pulse: Bool
    let pal: [Color]

    static let ico: [V3] = {
        let p = (1 + sqrt(5.0)) / 2
        let v = [
            V3(x: -1, y: p, z: 0), V3(x: 1, y: p, z: 0), V3(x: -1, y: -p, z: 0), V3(x: 1, y: -p, z: 0),
            V3(x: 0, y: -1, z: p), V3(x: 0, y: 1, z: p), V3(x: 0, y: -1, z: -p), V3(x: 0, y: 1, z: -p),
            V3(x: p, y: 0, z: -1), V3(x: p, y: 0, z: 1), V3(x: -p, y: 0, z: -1), V3(x: -p, y: 0, z: 1),
        ]
        let n = sqrt(1 + p * p)
        return v.map { $0 * (1 / n) }
    }()

    static let edges: [(Int, Int)] = {
        var out: [(Int, Int)] = []
        for i in ico.indices {
            for j in (i + 1)..<ico.count {
                let a = ico[i], b = ico[j]
                let d = sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2) + pow(a.z - b.z, 2))
                if d < 1.1 { out.append((i, j)) }
            }
        }
        return out
    }()

    /// Une sphère de points (spirale de Fibonacci).
    static let shell: [V3] = {
        let n = 90
        let g = Double.pi * (3 - sqrt(5.0))
        return (0..<n).map { i in
            let y = 1 - (Double(i) / Double(n - 1)) * 2
            let r = sqrt(1 - y * y)
            return V3(x: cos(g * Double(i)) * r, y: y, z: sin(g * Double(i)) * r)
        }
    }()

    private func alpha(_ c: Color, _ a: Double) -> Color { c.opacity(min(max(a, 0), 1)) }

    private func circle(_ center: CGPoint, _ r: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }

    func paint(_ ctx: inout GraphicsContext, size: CGSize) {
        let side = Double(min(size.width, size.height))
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = side * 0.24
        let cam = 5.0
        let c0 = pal[0], c1 = pal[1], c2 = pal[2]

        func project(_ p: V3) -> (CGPoint, Double) {
            let q = p.rotY(yaw).rotX(pitch)
            let k = cam / (cam - q.z)
            return (CGPoint(x: c.x + q.x * scale * k, y: c.y + q.y * scale * k), q.z)
        }

        // Halo.
        let beat = 1 + sin(t * (pulse ? 6 : 2)) * (pulse ? 0.08 : 0.03)
        ctx.fill(
            circle(c, side * 0.42 * beat),
            with: .radialGradient(
                Gradient(colors: [alpha(c1, 0.35), alpha(c0, 0.08), .clear]),
                center: c, startRadius: 0, endRadius: side * 0.45
            )
        )

        // Anneaux inclinés.
        for r in 0..<2 {
            var path = Path()
            for i in 0...96 {
                let a = Double(i) / 96 * .pi * 2
                let radius = r == 0 ? 2.05 : 2.45
                let p = V3(x: cos(a) * radius, y: 0, z: sin(a) * radius)
                    .rotX(r == 0 ? 1.1 : -0.7).rotY(t * (r == 0 ? 0.3 : -0.2))
                let (o, _) = project(p)
                if i == 0 { path.move(to: o) } else { path.addLine(to: o) }
            }
            ctx.stroke(path, with: .color(alpha(r == 0 ? c2 : c0, 0.45)), lineWidth: 1.2)
        }

        // Coque de points.
        for s in Self.shell {
            let (o, z) = project(s * (1.6 + sin(t * 1.3 + s.y * 3) * 0.04))
            ctx.fill(circle(o, 1.1 + (z + 1.6) * 0.35), with: .color(alpha(.white, 0.12 + (z + 1.6) * 0.12)))
        }

        // Satellites, reliés au cœur.
        var sorted: [(CGPoint, Double, OrbSatellite)] = sats.map { s in
            let a = s.phase + t * s.speed
            let p = V3(x: cos(a) * s.radius, y: sin(t * 0.7 + s.phase) * 0.35, z: sin(a) * s.radius).rotX(s.tilt)
            let (o, z) = project(p)
            return (o, z, s)
        }
        sorted.sort { $0.1 < $1.1 }
        for (o, z, s) in sorted {
            var line = Path()
            line.move(to: c)
            line.addLine(to: o)
            let color = pal[s.slot]
            ctx.stroke(
                line,
                with: .linearGradient(
                    Gradient(colors: [alpha(color, 0), alpha(color, 0.18 + (z + 2.5) * 0.06)]),
                    startPoint: c, endPoint: o
                ),
                lineWidth: 0.8
            )
        }

        // Le cœur : icosaèdre filaire + sommets lumineux.
        let pts = Self.ico.map { project($0 * beat) }
        for (i, j) in Self.edges {
            let depth = ((pts[i].1 + pts[j].1) / 2 + 1) / 2 // 0 (fond) → 1 (devant)
            var edge = Path()
            edge.move(to: pts[i].0)
            edge.addLine(to: pts[j].0)
            let a = 0.35 + depth * 0.6
            ctx.stroke(
                edge,
                with: .linearGradient(
                    Gradient(colors: [
                        alpha(c1.mix(with: c0, by: depth), a),
                        alpha(c2.mix(with: c1, by: depth), a),
                    ]),
                    startPoint: pts[i].0, endPoint: pts[j].0
                ),
                style: StrokeStyle(lineWidth: 0.8 + depth * 1.6, lineCap: .round)
            )
        }
        for (o, z) in pts {
            ctx.fill(circle(o, 1.8 + (z + 1) * 1.2), with: .color(alpha(.white, 0.5 + (z + 1) * 0.25)))
        }
        ctx.fill(
            circle(c, scale * 0.42 * beat),
            with: .radialGradient(Gradient(colors: [.white, c0, c1]), center: c, startRadius: 0, endRadius: scale * 0.42)
        )

        // Les satellites devant le cœur.
        for (o, z, s) in sorted {
            let k = (z + 2.5) / 5
            ctx.fill(circle(o, s.size * (0.8 + k) * 2.2), with: .color(alpha(pal[s.slot], 0.25)))
            ctx.fill(circle(o, s.size * (0.6 + k * 0.8)), with: .color(pal[s.slot]))
        }
    }
}
