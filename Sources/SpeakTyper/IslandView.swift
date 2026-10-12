import SwiftUI

/// The dynamic island, styled as a sci-fi HUD: a black shape that grows out of the notch,
/// with status readouts beside the notch and a voice orb + spectrum analyzer below it.
struct IslandView: View {
    @ObservedObject var model: IslandModel

    private let earWidth: CGFloat = 136
    private let flare: CGFloat = 9
    private var n: NotchMetrics { model.notch }
    private var isOpen: Bool { model.phase != .hidden }
    private var level: Float { model.levels.first ?? 0 }

    private var bodyHeight: CGFloat {
        switch model.phase {
        case .hidden: return 0
        case .message: return 64
        default: return 86
        }
    }

    private var size: CGSize {
        guard isOpen else {
            return n.hasNotch
                ? CGSize(width: n.width + flare * 2, height: n.height)
                : CGSize(width: n.width * 0.6, height: n.height * 0.6)
        }
        return CGSize(width: max(n.width + earWidth * 2, 480), height: n.height + bodyHeight)
    }

    var body: some View {
        let shape = IslandShape(bottomRadius: isOpen ? 34 : (n.hasNotch ? 10 : 14), flare: flare)
        ZStack(alignment: .top) {
            shape.fill(Color.black)

            if isOpen {
                Scanlines()
                    .transition(.opacity)
                // Light pooling under the HUD, brighter when you speak.
                Ellipse()
                    .fill(Color.white.opacity(0.05 + 0.07 * Double(level)))
                    .frame(width: size.width * 0.75, height: 70)
                    .blur(radius: 30)
                    .offset(y: size.height - 40)
                    .animation(.easeOut(duration: 0.2), value: level)
                    .transition(.opacity)

                content
                    .padding(.horizontal, flare)
                    .transition(.opacity)

                RimLight(shape: shape, level: level)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(isOpen ? 0.6 : 0), radius: 22, y: 10)
        .opacity(!isOpen && !n.hasNotch ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Layout

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leadingEar
                    .id("L-" + phaseKey)
                    .transition(.blurReplace)
                    .padding(.leading, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: n.hasNotch ? n.width : 40)
                trailingEar
                    .id("R-" + phaseKey)
                    .transition(.blurReplace)
                    .padding(.trailing, 24)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: n.height)

            HStack(spacing: 16) {
                VoiceOrb(mode: orbMode, level: level)
                    .frame(width: 58, height: 58)
                panel
                    .id("P-" + phaseKey)
                    .transition(.blurReplace)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: bodyHeight - 12)
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
        }
    }

    private var phaseKey: String {
        switch model.phase {
        case .hidden: return "hidden"
        case .loading: return "loading"
        case .listening: return "listening"
        case .processing: return "processing"
        case .done: return "done"
        case .message(let text, _): return "message-\(text)"
        }
    }

    private var orbMode: VoiceOrb.Mode {
        switch model.phase {
        case .listening: return .listening
        case .processing: return .processing
        case .done: return .done
        case .loading(let progress, _): return .loading(progress)
        case .message(_, let symbol): return .idle(symbol)
        case .hidden: return .idle("")
        }
    }

    @ViewBuilder private var leadingEar: some View {
        switch model.phase {
        case .listening:
            HStack(spacing: 7) {
                BlinkDot()
                HUDLabel("LISTENING", opacity: 0.75)
            }
        case .processing:
            HUDLabel("TRANSCRIBING", opacity: 0.75)
        case .done:
            HUDLabel("INSERTED", opacity: 0.8)
        case .loading:
            HUDLabel("INITIALIZING", opacity: 0.75)
        case .message:
            HUDLabel("SPEAKTYPER", opacity: 0.5)
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder private var trailingEar: some View {
        switch model.phase {
        case .listening:
            ElapsedTimer(since: model.startedAt)
        case .processing:
            HUDLabel("PARAKEET · ANE", opacity: 0.4)
        case .done(let words):
            HUDLabel("\(words) WORD\(words == 1 ? "" : "S")", opacity: 0.55)
        case .loading(let progress, _):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        case .message, .hidden:
            EmptyView()
        }
    }

    @ViewBuilder private var panel: some View {
        switch model.phase {
        case .listening:
            Spectrum(levels: model.levels)
                .overlay(HUDBrackets().stroke(.white.opacity(0.28), lineWidth: 1))
        case .processing:
            Scanner()
                .overlay(HUDBrackets().stroke(.white.opacity(0.28), lineWidth: 1))
        case .done:
            DoneSweep()
                .overlay(HUDBrackets().stroke(.white.opacity(0.4), lineWidth: 1))
        case .loading(let progress, let label):
            VStack(alignment: .leading, spacing: 10) {
                HUDLabel(label.uppercased(), opacity: 0.6)
                GlowProgress(progress: progress)
            }
            .padding(.horizontal, 6)
        case .message(let text, _):
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .hidden:
            EmptyView()
        }
    }
}

// MARK: - HUD pieces

struct HUDLabel: View {
    var text: String
    var opacity: Double

    init(_ text: String, opacity: Double = 0.6) {
        self.text = text
        self.opacity = opacity
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(1)
            .fixedSize()
    }
}

/// `00:04.2` — counts up while listening.
struct ElapsedTimer: View {
    var since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 0.1)) { context in
            let t = max(0, context.date.timeIntervalSince(since))
            Text(String(format: "%02d:%02d.%d", Int(t) / 60, Int(t) % 60, Int(t * 10) % 10))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .monospacedDigit()
        }
    }
}

struct BlinkDot: View {
    @State private var on = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 5, height: 5)
            .shadow(color: .white.opacity(0.9), radius: 3)
            .opacity(on ? 1 : 0.25)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Little L-shaped corner marks around a panel.
struct HUDBrackets: Shape {
    var length: CGFloat = 7

    func path(in r: CGRect) -> Path {
        let l = length
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// Very faint CRT-style scanlines across the island.
struct Scanlines: View {
    var body: some View {
        Canvas { gc, size in
            var lines = Path()
            var y: CGFloat = 0
            while y < size.height {
                lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.5))
                y += 3
            }
            gc.fill(lines, with: .color(.white.opacity(0.022)))
        }
        .allowsHitTesting(false)
    }
}

/// A static rim plus a beam of light that keeps orbiting the island's edge.
struct RimLight: View {
    var shape: IslandShape
    var level: Float

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let glow = 0.45 + 0.5 * Double(level)
            ZStack {
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.16)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5)
                shape.stroke(
                    AngularGradient(
                        stops: [
                            .init(color: .white.opacity(0), location: 0.0),
                            .init(color: .white.opacity(0), location: 0.40),
                            .init(color: .white.opacity(glow), location: 0.5),
                            .init(color: .white.opacity(0), location: 0.60),
                            .init(color: .white.opacity(0), location: 1.0),
                        ],
                        center: .center,
                        angle: .degrees(t * 75)),
                    lineWidth: 2)
                    .blur(radius: 0.8)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Voice orb

/// An "AI core": a glowing center inside a ring of radial ticks that stretch with your voice,
/// circled by slowly rotating dial arcs.
struct VoiceOrb: View {
    enum Mode: Equatable {
        case listening, processing, done
        case loading(Double)
        case idle(String)
    }

    var mode: Mode
    var level: Float

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in draw(in: &gc, size: size, t: t) }
        }
        .overlay {
            switch mode {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.black)
                    .transition(.scale.combined(with: .opacity))
            case .idle(let symbol) where !symbol.isEmpty:
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: mode)
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2
        let lv = CGFloat(level)
        let busy = mode == .processing

        // Outer dial arcs — sampled point by point so each is its own clean stroke.
        let arcSpin = -t * (busy ? 3.2 : 0.7)
        for k in 0..<3 {
            let start = arcSpin + Double(k) * 2 * .pi / 3
            gc.stroke(
                arcPath(center: c, radius: R - 1, from: start, sweep: .pi * 50 / 180),
                with: .color(.white.opacity(busy ? 0.5 : 0.3)),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }

        // Thin inner ring.
        gc.stroke(
            Path(ellipseIn: CGRect(x: c.x - R * 0.42, y: c.y - R * 0.42, width: R * 0.84, height: R * 0.84)),
            with: .color(.white.opacity(0.12)), lineWidth: 0.8)

        if case .loading(let progress) = mode {
            let arc = arcPath(center: c, radius: R - 1, from: -.pi / 2, sweep: 2 * .pi * max(0.01, progress))
            gc.stroke(arc, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }

        // Radial tick ring.
        let ticks = 40
        let r0 = R * 0.5
        var tickPath = Path()
        for i in 0..<ticks {
            let a = Double(i) / Double(ticks) * 2 * .pi + t * (busy ? 1.6 : 0.25)
            let len: CGFloat
            switch mode {
            case .listening:
                let wobble = 0.55 + 0.45 * sin(t * 6.5 + Double(i) * 0.95)
                let breathe = 1.5 + 1.5 * (0.5 + 0.5 * sin(t * 2.6 + Double(i) * 0.45))
                len = breathe + R * 0.36 * lv * CGFloat(wobble)
            case .processing:
                len = 1.5 + 4.5 * CGFloat(max(0, sin(t * 8 - Double(i) * 0.5)))
            case .done:
                len = 1.2
            case .loading, .idle:
                len = 1.8
            }
            tickPath.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
            tickPath.addLine(to: CGPoint(x: c.x + cos(a) * (r0 + len), y: c.y + sin(a) * (r0 + len)))
        }
        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.stroke(tickPath, with: .color(.white.opacity(0.4)), lineWidth: 1.8)
        }
        gc.stroke(tickPath, with: .color(Color(white: 0.86).opacity(0.8)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

        // Core.
        let coreR: CGFloat
        switch mode {
        case .done: coreR = R * 0.38
        case .idle: coreR = 0
        case .processing: coreR = R * (0.2 + 0.04 * CGFloat(sin(t * 6)))
        default: coreR = R * (0.18 + 0.16 * lv)
        }
        guard coreR > 0 else { return }
        let halo = coreR * 2.4
        gc.fill(
            Path(ellipseIn: CGRect(x: c.x - halo, y: c.y - halo, width: halo * 2, height: halo * 2)),
            with: .radialGradient(Gradient(colors: [.white.opacity(0.4), .clear]), center: c, startRadius: 0, endRadius: halo))
        gc.fill(
            Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR, width: coreR * 2, height: coreR * 2)),
            with: .radialGradient(Gradient(colors: [.white, Color(white: 0.72)]), center: c, startRadius: 0, endRadius: coreR))
    }
}

private func arcPath(center c: CGPoint, radius r: CGFloat, from start: Double, sweep: Double) -> Path {
    var p = Path()
    let steps = 32
    for i in 0...steps {
        let a = start + sweep * Double(i) / Double(steps)
        let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p
}

// MARK: - Spectrum / scanner / done

private let edgeFade = LinearGradient(
    stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: 0.14),
        .init(color: .black, location: 0.86),
        .init(color: .clear, location: 1),
    ],
    startPoint: .leading, endPoint: .trailing)

/// Faint dot-matrix grid used behind the panels.
private func drawGrid(_ gc: inout GraphicsContext, size: CGSize) {
    var dots = Path()
    let mid = size.height / 2
    var y = mid.truncatingRemainder(dividingBy: 8)
    while y < size.height {
        var x: CGFloat = 4
        while x < size.width {
            dots.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1))
            x += 8
        }
        y += 8
    }
    gc.fill(dots, with: .color(.white.opacity(0.08)))
    gc.fill(Path(CGRect(x: 0, y: mid - 0.25, width: size.width, height: 0.5)), with: .color(.white.opacity(0.12)))
}

/// Translucent grey bars mirrored around the axis. The newest mic level drives the center
/// and older levels ripple outward; a slow breathing wave keeps it alive in silence.
struct Spectrum: View {
    var levels: [Float]
    private let barCount = 49

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                drawGrid(&gc, size: size)

                let mid = size.height / 2
                let half = barCount / 2
                let pitch = size.width / CGFloat(barCount)
                let barWidth = min(3, pitch * 0.5)

                var bars = Path()
                var tips = Path()
                for i in 0..<barCount {
                    let d = abs(i - half)
                    let norm = Double(d) / Double(half)
                    let envelope = exp(-pow(norm * 1.45, 2))
                    let level = Double(levels[min(d, levels.count - 1)])
                    let shimmer = 0.62 + 0.38 * sin(t * 7.3 + Double(i) * 0.9) * sin(t * 3.1 + Double(d) * 0.5)
                    let breathing = 0.13 + 0.09 * sin(t * 2.8 - Double(d) * 0.42)
                    let amp = envelope * max(breathing, level * shimmer)
                    let h = max(2.4, CGFloat(amp) * (size.height - 8))
                    let x = (CGFloat(i) + 0.5) * pitch - barWidth / 2
                    bars.addRoundedRect(
                        in: CGRect(x: x, y: mid - h / 2, width: barWidth, height: h),
                        cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
                    if h > 10 {  // LED-style caps on the louder bars
                        tips.addEllipse(in: CGRect(x: x, y: mid - h / 2 - 3.5, width: barWidth, height: barWidth * 0.8))
                        tips.addEllipse(in: CGRect(x: x, y: mid + h / 2 + 1.5, width: barWidth, height: barWidth * 0.8))
                    }
                }

                gc.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.fill(bars, with: .color(.white.opacity(0.3)))
                }
                gc.fill(
                    bars,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(white: 0.7).opacity(0.15), location: 0),
                            .init(color: Color(white: 0.9).opacity(0.8), location: 0.5),
                            .init(color: Color(white: 0.7).opacity(0.15), location: 1),
                        ]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                gc.fill(tips, with: .color(.white.opacity(0.7)))
            }
        }
        .mask(edgeFade)
    }
}

/// While Parakeet transcribes: twin beams sweep along the axis.
struct Scanner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                drawGrid(&gc, size: size)
                let mid = size.height / 2
                for (speed, offset, width) in [(2.6, 0.0, 120.0), (2.6, .pi, 60.0)] {
                    let p = (sin(t * speed + offset) + 1) / 2
                    let cx = CGFloat(p) * size.width
                    let rect = CGRect(x: cx - width / 2, y: mid - 1, width: width, height: 2)
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [.clear, .white.opacity(0.95), .clear]),
                        startPoint: CGPoint(x: rect.minX, y: mid), endPoint: CGPoint(x: rect.maxX, y: mid))
                    gc.drawLayer { layer in
                        layer.addFilter(.blur(radius: 8))
                        layer.fill(Path(roundedRect: rect.insetBy(dx: 0, dy: -4), cornerRadius: 5), with: shading)
                    }
                    gc.fill(Path(roundedRect: rect, cornerRadius: 1), with: shading)
                }
            }
        }
        .mask(edgeFade)
    }
}

/// On success: a bright line draws out from the center.
struct DoneSweep: View {
    @State private var drawn = false

    var body: some View {
        ZStack {
            Canvas { gc, size in drawGrid(&gc, size: size) }
            GeometryReader { geo in
                Capsule()
                    .fill(LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: drawn ? geo.size.width : 0, height: 2)
                    .shadow(color: .white.opacity(0.8), radius: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .mask(edgeFade)
        .onAppear { withAnimation(.easeOut(duration: 0.45)) { drawn = true } }
    }
}

struct GlowProgress: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.95)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * progress))
                    .shadow(color: .white.opacity(0.6), radius: 5)
            }
        }
        .frame(height: 2.5)
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

// MARK: - Shape

/// Notch-like silhouette: flat top with small outward flares, rounded bottom corners.
struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var flare: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, e = flare
        let r = max(0, min(bottomRadius, (w - 2 * e) / 2, h - e))
        let k: CGFloat = 0.62  // a bit "squircle-y"
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: e, y: e), control1: CGPoint(x: e * k, y: 0), control2: CGPoint(x: e, y: e * (1 - k)))
        p.addLine(to: CGPoint(x: e, y: h - r))
        p.addCurve(to: CGPoint(x: e + r, y: h), control1: CGPoint(x: e, y: h - r * (1 - k)), control2: CGPoint(x: e + r * (1 - k), y: h))
        p.addLine(to: CGPoint(x: w - e - r, y: h))
        p.addCurve(to: CGPoint(x: w - e, y: h - r), control1: CGPoint(x: w - e - r * (1 - k), y: h), control2: CGPoint(x: w - e, y: h - r * (1 - k)))
        p.addLine(to: CGPoint(x: w - e, y: e))
        p.addCurve(to: CGPoint(x: w, y: 0), control1: CGPoint(x: w - e, y: e * (1 - k)), control2: CGPoint(x: w - e * k, y: 0))
        p.closeSubpath()
        return p
    }
}
