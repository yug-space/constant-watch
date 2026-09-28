import SwiftUI
import AppKit

// A procedural glass orb releases Constant's seven-point mark. No video or remote assets.
struct LogoReveal: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var origin = Date()
    var desktopOnly = false
    let continueAction: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 8.0 : timeline.date.timeIntervalSince(origin)
            let arrive = smooth(time / 2.2)
            let release = smooth((time - 3.3) / 1.8)
            let title = smooth((time - 4.2) / 1.6)
            VStack(spacing: 0) {
                if !desktopOnly { Text("A LITTLE ROOM TO REMEMBER").font(.system(size: 9, weight: .medium)).tracking(3.4)
                    .foregroundStyle(Color(red: 0.53, green: 0.65, blue: 0.83)).opacity(arrive)
                    .padding(.bottom, 25) }
                ZStack {
                    Ellipse().fill(Color.blue.opacity(0.22)).frame(width: 235, height: 30)
                        .blur(radius: 29).offset(y: 134).opacity(arrive)
                    Circle().fill(Color(red: 0.03, green: 0.24, blue: 1).opacity(0.28))
                        .frame(width: 270, height: 270).blur(radius: 58)
                        .scaleEffect(0.7 + arrive * 0.3 + release * 0.22).opacity(arrive)
                    // A single soft release ripple, never a flashing strobe.
                    Circle().stroke(Color(red: 0.28, green: 0.64, blue: 1).opacity(0.4 * sin(release * .pi)), lineWidth: 1)
                        .frame(width: 205, height: 205).scaleEffect(1 + release * 1.3).blur(radius: 3)
                    GlassOrb(time: time).frame(width: 205, height: 205)
                        .scaleEffect((0.78 + arrive * 0.22) * (1 - release * 0.58))
                        .offset(y: (1 - arrive) * 70).opacity(arrive * (1 - release))
                    glassMark(release: release, time: time).opacity(release)
                }.frame(height: 260).accessibilityHidden(true)
                Text("constant").font(.system(size: 57, weight: .medium)).tracking(-2.4)
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.66, green: 0.79, blue: 0.98)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .blue.opacity(0.35), radius: 22).opacity(title).offset(y: (1 - title) * 12)
                Text("Keep the thread of your day.").font(.system(size: 15)).foregroundStyle(Color(red: 0.6, green: 0.67, blue: 0.79))
                    .padding(.top, 12).opacity(title)
                if !desktopOnly { HStack(spacing: 22) {
                    Button(action: continueAction) {
                        HStack(spacing: 14) { Text("Get started"); Image(systemName: "arrow.right") }
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 23).padding(.vertical, 12)
                            .background(LinearGradient(colors: [Color(red: 0.16, green: 0.3, blue: 0.52), Color(red: 0.07, green: 0.13, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 0.7))
                            .shadow(color: .blue.opacity(0.15), radius: 18, y: 4)
                    }.buttonStyle(.plain)
                    Button { origin = Date() } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)) }
                        .buttonStyle(.plain).accessibilityLabel("Replay logo reveal").help("Replay logo reveal")
                }.padding(.top, 27).opacity(0.45 + title * 0.55) }
            }.padding(.vertical, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func smooth(_ value: Double) -> Double {
        let x = min(1, max(0, value)); return x * x * (3 - 2 * x)
    }
    private func glassMark(release: Double, time: Double) -> some View {
        let points: [CGPoint] = [CGPoint(x: 0, y: 0)] + (0..<6).map { i in
            let angle = Double(i) * .pi / 3
            return CGPoint(x: cos(angle) * 55, y: sin(angle) * 55)
        }
        return ZStack {
            ForEach(0..<7, id: \.self) { index in
                Circle().fill(RadialGradient(stops: [
                    .init(color: .white, location: 0),
                    .init(color: Color(red: 0.74, green: 0.9, blue: 1), location: 0.32),
                    .init(color: Color(red: 0.16, green: 0.49, blue: 0.92), location: 0.72),
                    .init(color: Color(red: 0.025, green: 0.12, blue: 0.4), location: 1)
                ], center: .init(x: 0.34, y: 0.23), startRadius: 0, endRadius: 44))
                    .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.9), .cyan.opacity(0.3), .blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
                    .frame(width: 44, height: 44)
                    .shadow(color: Color.cyan.opacity(0.24), radius: 9)
                    .shadow(color: .blue.opacity(0.45), radius: 23)
                    .offset(x: points[index].x * release, y: points[index].y * release)
            }
        }.rotationEffect(.degrees((1 - release) * -28))
            .scaleEffect(0.72 + release * 0.28)
            .offset(y: reduceMotion ? 0 : sin(time * 0.65) * 3)
    }
}

private struct GlassOrb: View {
    let time: Double
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.045, green: 0.22, blue: 0.83), Color(red: 0.005, green: 0.06, blue: 0.36), Color(red: 0.015, green: 0.02, blue: 0.12)], center: .init(x: 0.44, y: 0.36), startRadius: 0, endRadius: size * 0.7))
                OrbWave(phase: time * 0.8, level: 0.6).fill(Color.cyan).blur(radius: 12).offset(y: -4)
                OrbWave(phase: time * 0.8, level: 0.65).fill(LinearGradient(colors: [.white, Color(red: 0.78, green: 0.89, blue: 1), Color(red: 0.27, green: 0.49, blue: 0.88)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .white.opacity(0.9), radius: 6, y: -3)
                Ellipse().fill(.white.opacity(0.18)).frame(width: size * 0.55, height: size * 0.11)
                    .blur(radius: 10).rotationEffect(.degrees(-25)).offset(x: -size * 0.15, y: -size * 0.3)
                Circle().fill(RadialGradient(colors: [.clear, Color(red: 0.015, green: 0.03, blue: 0.16).opacity(0.45)], center: .center, startRadius: size * 0.31, endRadius: size * 0.53))
            }.clipShape(Circle())
                .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.75), .cyan.opacity(0.65), .white.opacity(0.9), .blue.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
                .shadow(color: .cyan.opacity(0.4), radius: 7)
                .shadow(color: .blue.opacity(0.5), radius: 27)
        }
    }
}

private struct OrbWave: Shape {
    let phase: Double
    let level: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        for index in 0...80 {
            let x = Double(index) / 80
            let wave = sin(x * .pi * 2 + phase) * 0.055 + sin(x * .pi + phase * 0.6) * 0.065
            path.addLine(to: CGPoint(x: rect.width * x, y: rect.height * (level + wave)))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// A screen-sized transparent AppKit panel, not a fullscreen Space or an opaque window.
@MainActor private final class DesktopRevealController: ObservableObject {
    private var panel: RevealPanel?
    private weak var journal: NSWindow?
    private var finishTask: Task<Void, Never>?
    private var completion: (() -> Void)?

    func present(completion: @escaping () -> Void) {
        guard panel == nil else { return }
        let journal = NSApp.windows.first { $0.identifier?.rawValue == "journal" || $0.title == "Constant Watch" }
        guard let screen = journal?.screen ?? NSScreen.main else { completion(); return }
        self.journal = journal
        self.completion = completion
        let panel = RevealPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "Constant logo reveal"
        panel.identifier = NSUserInterfaceItemIdentifier("desktop-logo-reveal")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let scale = min(1.6, max(1, screen.frame.height / 700))
        let host = NSHostingView(rootView: LogoReveal(desktopOnly: true, continueAction: {})
            .scaleEffect(scale).frame(width: screen.frame.width, height: screen.frame.height)
            .background(Color.clear).preferredColorScheme(.dark))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.dismiss() }
        self.panel = panel
        journal?.orderOut(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        finishTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(reduced ? 2.3 : 7.2)) } catch { return }
            guard let self, let panel = self.panel else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduced ? 0 : 0.7
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.dismiss() }
            }
        }
    }

    func dismiss(advance: Bool = true) {
        guard let panel else { return }
        finishTask?.cancel(); finishTask = nil
        self.panel = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
        let done = completion; completion = nil
        if advance { done?() }
        journal?.makeKeyAndOrderFront(nil)
        journal = nil
    }
}

private final class RevealPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

struct DesktopRevealHost: View {
    @StateObject private var reveal = DesktopRevealController()
    let completion: () -> Void
    var body: some View {
        Color.clear
            .task { reveal.present(completion: completion) }
            .onDisappear { reveal.dismiss(advance: false) }
    }
}
