import AppKit
import SwiftUI

/// Size of the hardware notch (or a stand-in on screens without one).
struct NotchMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasNotch: Bool

    static func of(_ screen: NSScreen) -> NotchMetrics {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchMetrics(
                width: screen.frame.width - left.width - right.width,
                height: screen.safeAreaInsets.top,
                hasNotch: true)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchMetrics(width: 120, height: max(menuBar, 30), hasNotch: false)
    }
}

enum IslandPhase: Equatable {
    case hidden
    case loading(progress: Double, label: String)
    case listening
    case processing
    case done(words: Int)
    case message(String, symbol: String)
}

@MainActor
final class IslandModel: ObservableObject {
    static let historyLength = 26

    @Published var phase: IslandPhase = .hidden
    @Published var notch = NotchMetrics(width: 200, height: 32, hasNotch: true)
    @Published var startedAt = Date()
    /// Smoothed mic level, newest first. The visualizer ripples it outward from the center.
    @Published var levels = [Float](repeating: 0, count: IslandModel.historyLength)

    func push(level: Float) {
        levels.insert(level, at: 0)
        levels.removeLast()
    }

    func resetLevels() {
        levels = [Float](repeating: 0, count: IslandModel.historyLength)
    }
}

/// Borderless, click-through, non-activating panel pinned to the top-center of the screen.
/// Non-activating matters: the app you're dictating into must keep keyboard focus.
final class IslandPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        // Above the menu bar and other notch utilities while it's showing.
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Allow the window to sit over the menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class IslandController {
    let model = IslandModel()
    private let panel = IslandPanel()
    private var hideWork: DispatchWorkItem?
    private static let canvas = CGSize(width: 780, height: 260)

    private static let open = Animation.spring(response: 0.48, dampingFraction: 0.7)
    private static let morph = Animation.spring(response: 0.4, dampingFraction: 0.8)
    private static let close = Animation.spring(response: 0.4, dampingFraction: 0.92)

    init() {
        let host = NSHostingView(rootView: IslandView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    /// Animate to a phase, growing out of the notch if the island isn't up yet.
    func show(_ phase: IslandPhase) {
        hideWork?.cancel()
        if phase == .listening, model.phase != .listening { model.startedAt = Date() }

        if !panel.isVisible || model.phase == .hidden {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main ?? NSScreen.screens[0]
            model.notch = NotchMetrics.of(screen)
            model.phase = .hidden
            panel.setFrame(
                NSRect(
                    x: screen.frame.midX - Self.canvas.width / 2,
                    y: screen.frame.maxY - Self.canvas.height,
                    width: Self.canvas.width, height: Self.canvas.height),
                display: true)
            panel.orderFrontRegardless()
            // Render one collapsed frame first so the spring plays out of the notch.
            DispatchQueue.main.async { [weak self] in
                withAnimation(Self.open) { self?.model.phase = phase }
            }
        } else {
            withAnimation(Self.morph) { model.phase = phase }
        }
    }

    /// Shows a short message, then folds back into the notch.
    func flash(_ text: String, symbol: String, for seconds: TimeInterval = 1.8) {
        show(.message(text, symbol: symbol))
        hide(after: seconds)
    }

    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(Self.close) { self.model.phase = .hidden }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.model.phase == .hidden else { return }
                self.panel.orderOut(nil)
                self.model.resetLevels()
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
