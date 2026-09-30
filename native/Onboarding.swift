import SwiftUI
import AppKit

private let setupBlue = Color(red: 0.08, green: 0.43, blue: 0.97)

struct SetupButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 14, weight: .medium))
            .padding(.horizontal, 25).padding(.vertical, 12)
            .foregroundStyle(enabled ? Ink.ivory : Ink.ash)
            .background(LinearGradient(colors: [.white, primary ? Color(red: 0.92, green: 0.96, blue: 1) : .white], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(primary && enabled ? setupBlue.opacity(0.32) : Ink.control, lineWidth: 1))
            .shadow(color: .black.opacity(enabled ? 0.055 : 0), radius: 3, y: 2)
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: WatchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingIntroductionCompleted") private var introductionCompleted = false
    @AppStorage("onboardingMusicEnabled") private var musicEnabled = true
    @StateObject private var music = OnboardingMusic()
    @State private var introFinished = false
    @State private var busy = false
    @State private var prepared = false
    @State private var selectedPermission = "accessibility"

    private var granted: Int {
        (model.status?.permissions.accessibility == true ? 1 : 0) +
        (model.status?.permissions.screenRecording == true ? 1 : 0)
    }
    private var nextAction: String {
        if busy { return "Opening settings…" }
        if model.status?.permissions.accessibility != true { return "Enable accessibility →" }
        if model.status?.permissions.screenRecording != true { return "Enable screen access →" }
        return "Start my journal →"
    }
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.control.opacity(0.5))
                    Capsule().fill(LinearGradient(colors: [setupBlue, Color(red: 0.76, green: 0.88, blue: 1)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * (introductionCompleted ? Double(granted + 1) / 3 : 0.08))
                }
            }.frame(height: 5).padding(.horizontal, 26).padding(.top, 20)
            HStack {
                Wordmark()
                Spacer()
                Button("Replay orb intro") { model.replayOrbIntro() }.buttonStyle(.plain).font(.caption).foregroundStyle(Ink.ash)
                Button(model.status?.settings.onboardingComplete == true ? "Close setup" : "Explore first") {
                    if model.status?.settings.onboardingComplete == true { model.showOnboarding = false }
                    else { Task { await model.finishOnboarding(purpose: "recall", start: false) } }
                }.buttonStyle(.plain).font(.caption).foregroundStyle(Ink.ash).padding(.leading, 20).disabled(!model.connected)
            }.padding(.horizontal, 40).padding(.vertical, 24)
            if !introductionCompleted {
                if !introFinished {
                    DesktopRevealHost { introFinished = true }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 22) {
                        ConstantMark().frame(width: 78, height: 78)
                        Text("Your day. Remembered.").font(.system(size: 40, weight: .medium)).tracking(-1.2)
                        Text("A private journal of your work and conversations.\nSearch the detail. Pick up where you left off.")
                            .font(.system(size: 16)).foregroundStyle(Ink.ash).multilineTextAlignment(.center).lineSpacing(6)
                        Button("Set up Constant →") { introductionCompleted = true }
                            .buttonStyle(SetupButton(primary: true)).padding(.top, 8)
                        Text("No account. One setup screen.").font(.caption).foregroundStyle(Ink.ash)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).modifier(WelcomeReveal(delay: 0.1))
                }
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 48) {
                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(granted == 2 ? "You’re ready." : "A little setup. Then you’re in.")
                                    .font(.system(size: 30, weight: .medium)).tracking(-0.8)
                                Text(granted == 2 ? "Start your journal whenever you’re ready. You stay in control." : "Allow screen access below. We’ll prepare your local model alongside it.")
                                    .font(.system(size: 13)).foregroundStyle(Ink.ash).lineSpacing(4)
                            }
                            VStack(spacing: 12) {
                                accessRow("Accessibility", detail: "Read the text in the app you’re using.", granted: model.status?.permissions.accessibility == true, kind: "accessibility")
                                accessRow("Screen access", detail: "Fill in missing text with OCR. Screenshots aren’t saved.", granted: model.status?.permissions.screenRecording == true, kind: "screen")
                            }
                            if granted < 2 {
                                Text("In System Settings, turn on Constant Watch, then return here. We check automatically.")
                                    .font(.caption).foregroundStyle(Ink.ash).lineSpacing(4)
                            }
                            Button(nextAction) { Task { await advance() } }
                                .buttonStyle(SetupButton(primary: true)).disabled(busy || !model.connected)
                            Text(model.status?.model.available == true ? "Your local model is ready. Nothing leaves this Mac." : "You can start capturing while the model downloads. Summaries will catch up automatically.")
                                .font(.system(size: 11)).foregroundStyle(Ink.ash).lineSpacing(4)
                            if let error = model.error, !model.connected {
                                Text(error).font(.caption).foregroundStyle(.red)
                                Button("Reconnect") { model.startBackend(); Task { await model.refresh() } }.buttonStyle(SetupButton())
                            }
                            DisclosureGroup("Need help with macOS permissions?") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Enable the installed Constant Watch app in Privacy & Security. If macOS asks you to reopen the app, do that and return to this same screen.")
                                    Button("Show Constant Watch in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }.buttonStyle(.plain).foregroundStyle(setupBlue)
                                    Button("Check access again") { Task { await model.refresh() } }.buttonStyle(.plain).foregroundStyle(setupBlue)
                                }.font(.caption).foregroundStyle(Ink.ash).padding(.top, 10)
                            }.font(.caption).foregroundStyle(Ink.ash)
                        }.frame(maxWidth: 460, alignment: .leading)
                        VStack(alignment: .leading, spacing: 24) {
                            localModel
                            VStack(alignment: .leading, spacing: 16) {
                                Label("A continuous day", systemImage: "text.alignleft")
                                Text("Your screen notes stay organized by app and time.").font(.caption).foregroundStyle(Ink.ash)
                                Label("Meetings, when you choose", systemImage: "waveform")
                                Text("We’ll suggest recording when a call is detected. Microphone access and the speech model are set up when you first use Meetings.").font(.caption).foregroundStyle(Ink.ash).lineSpacing(4)
                                Label("Always your choice", systemImage: "pause.circle")
                                Text("Pause from the menu bar. Exclude apps. Keep everything local.").font(.caption).foregroundStyle(Ink.ash)
                            }.font(.system(size: 14, weight: .medium)).padding(25)
                        }.frame(maxWidth: 380)
                    }.padding(.horizontal, 48).padding(.vertical, 24).frame(maxWidth: .infinity)
                }
            }
            HStack {
                Label("Private by default. Yours to pause.", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(Ink.ash)
                Spacer()
                Button { musicEnabled.toggle() } label: {
                    Label(musicEnabled ? "Music on" : "Music off", systemImage: musicEnabled ? "speaker.wave.2" : "speaker.slash")
                }.buttonStyle(.plain).font(.caption).foregroundStyle(Ink.ash).disabled(music.unavailable)
            }.padding(.horizontal, 40).padding(.vertical, 22)
        }
        .background(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.8), .init(color: Color(red: 0.93, green: 0.97, blue: 1), location: 1)], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(Ink.ivory).tint(setupBlue)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: introductionCompleted)
        .onAppear { if musicEnabled { music.play() } }
        .task(id: introductionCompleted) { await prepareIfNeeded() }
        .onChange(of: model.status?.model.runtimeInstalled) { _, installed in
            if installed == true && introductionCompleted && model.status?.model.available != true && model.status?.download?.running != true {
                Task { await model.prepareModel() }
            }
        }
        .onChange(of: musicEnabled) { _, enabled in if enabled { music.play() } else { music.stop() } }
        .onDisappear { music.stop() }
    }

    private func prepareIfNeeded() async {
        guard introductionCompleted, !prepared else { return }
        prepared = true
        if model.status?.model.available != true && model.status?.model.runtimeInstalled != false {
            await model.prepareModel()
        }
    }

    private func advance() async {
        guard !busy else { return }
        if granted == 2 { await model.finishOnboarding(purpose: "recall", start: true); return }
        busy = true
        selectedPermission = model.status?.permissions.accessibility == true ? "screen" : "accessibility"
        await model.requestPermissions(selectedPermission)
        busy = false
    }

    private func accessRow(_ title: String, detail: String, granted: Bool, kind: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").font(.system(size: 24)).foregroundStyle(granted ? setupBlue : Ink.control)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(Ink.ash).lineSpacing(3)
            }
            Spacer(minLength: 0)
            if granted { Text("Ready").font(.caption).foregroundStyle(setupBlue) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.control.opacity(0.65)))
    }

    private var localModel: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: "cpu").font(.title2).foregroundStyle(setupBlue)
                Spacer()
                if model.status?.model.available == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(setupBlue) }
                else if model.status?.download?.running == true { ProgressView().controlSize(.small) }
            }
            Text("Intelligence. On your Mac.").font(.system(size: 20, weight: .medium)).tracking(-0.4)
            Text("Qwen 3.5 · 0.8B · About 1 GB").font(.caption).foregroundStyle(Ink.ash)
            if model.status?.model.available == true {
                Text("Already installed. Ready to go.").font(.callout).foregroundStyle(setupBlue)
            } else if model.status?.model.runtimeInstalled == false {
                Text("Install Ollama, the engine that runs your local model. Return here after installing; we’ll handle the model download.").font(.caption).foregroundStyle(Ink.ash).lineSpacing(4)
                Button("Install local engine ↗") { model.openOllama() }.buttonStyle(SetupButton())
            } else {
                if let download = model.status?.download {
                    if download.running { ProgressView(value: min(1, max(0, download.fraction))) }
                    Text(download.status).font(.caption).foregroundStyle(Ink.ash).lineSpacing(4)
                } else { Text("Checking what’s already on this Mac…").font(.caption).foregroundStyle(Ink.ash) }
                if model.status?.download?.running != true {
                    Button("Retry model setup") { Task { await model.prepareModel() } }.buttonStyle(SetupButton())
                }
            }
            Text(model.status?.model.available == true ? "No further download needed." : "Your journal works while this finishes.").font(.system(size: 11)).foregroundStyle(Ink.ash)
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.white, Color(red: 0.96, green: 0.98, blue: 1)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.blue.opacity(0.1)))
    }
}

private struct WelcomeReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    let delay: Double
    func body(content: Content) -> some View {
        content.opacity(visible || reduceMotion ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 9)
            .blur(radius: visible || reduceMotion ? 0 : 3)
            .onAppear {
                if reduceMotion { visible = true }
                else { withAnimation(.easeOut(duration: 0.85).delay(delay)) { visible = true } }
            }
    }
}
