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
    @AppStorage("onboardingStep") private var step = 0
    @State private var purpose = "recall"
    @State private var busy = false
    @State private var practiceStarted = false
    @State private var selectedPermission = "screen"
    @State private var showHelp = false
    @AppStorage("onboardingMusicEnabled") private var musicEnabled = true
    @StateObject private var music = OnboardingMusic()
    @AppStorage("onboardingIntroductionCompleted") private var introductionCompleted = false
    @AppStorage("onboardingPreferredName") private var preferredName = ""
    @State private var introScene = 0
    @FocusState private var nameFocused: Bool
    private let steps = ["Welcome", "Permissions", "Local model", "First moment"]
    private let headlines = ["A little less lost context.", "Enable core features", "Intelligence. On your Mac.", "See your first moment."]
    private let descriptions = ["Keep the useful details from your day, without stopping to write them down.", "Two permissions help Constant Watch turn visible text into a private, searchable journal.", "A small local model makes sense of your screen text. Your notes stay here with you.", "Open a practice note. Watch it become a searchable part of your day."]

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.94, green: 0.95, blue: 0.96))
                    Capsule().fill(LinearGradient(colors: [setupBlue, Color(red: 0.38, green: 0.71, blue: 0.98), Color(red: 0.77, green: 0.88, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * (introductionCompleted ? Double(step + 1) / 4 : 0.06))
                }
            }.frame(height: 6).accessibilityLabel(introductionCompleted ? "Setup step \(step + 1) of 4" : "Welcome")
                .padding(.horizontal, 24).padding(.top, 18)
            HStack {
                HStack(spacing: 7) {
                    ConstantMark().frame(width: 25, height: 25)
                    Text("constant").font(.system(size: 15, weight: .medium))
                }
                Spacer()
                if introductionCompleted {
                    Button("Replay orb intro") { model.replayOrbIntro() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.ash)
                }
                Text(introductionCompleted ? "\(step + 1) of 4  ·  \(steps[step])" : "A little room to remember").font(.system(size: 11)).foregroundStyle(Ink.ash)
                Button(model.status?.settings.onboardingComplete == true ? "Close guide" : "Explore first") {
                    if model.status?.settings.onboardingComplete == true { model.showOnboarding = false }
                    else { Task { await model.finishOnboarding(purpose: purpose, start: false) } }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.ash).padding(.leading, 22).disabled(!model.connected)
            }.padding(.horizontal, 40).padding(.top, 24)
            if !introductionCompleted {
                introduction.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
            GeometryReader { geometry in
                ScrollView {
                    HStack(alignment: .center, spacing: 56) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(headlines[step]).font(.system(size: 27, weight: .medium)).tracking(-0.7).fixedSize(horizontal: false, vertical: true)
                            Text(descriptions[step]).font(.system(size: 13)).foregroundStyle(Ink.ash).lineSpacing(4).fixedSize(horizontal: false, vertical: true).padding(.top, 12).padding(.bottom, 26)
                            Group {
                                switch step {
                                case 0: welcome
                                case 1: permissions
                                case 2: intelligence
                                default: firstMoment
                                }
                            }
                            if let error = model.error {
                                HStack {
                                    Text(error).font(.system(size: 11)).foregroundStyle(Ink.ash).fixedSize(horizontal: false, vertical: true)
                                    if !model.connected { Button("Retry") { model.startBackend(); Task { await model.refresh() } }.buttonStyle(SetupButton()) }
                                }.padding(.top, 12)
                            }
                            HStack(spacing: 20) {
                                Button(step == 0 ? "Get started" : step == 3 ? "Open my daily flow" : "Continue") {
                                    if step < 3 { step += 1 }
                                    else { Task { await model.finishOnboarding(purpose: purpose, start: true) } }
                                }.buttonStyle(SetupButton(primary: true)).disabled(!canContinue)
                                if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Ink.ash) }
                            }.padding(.top, 26)
                            Text(footer).font(.system(size: 10)).foregroundStyle(Ink.ash).fixedSize(horizontal: false, vertical: true).padding(.top, 15)
                        }.frame(maxWidth: 430, alignment: .leading).id(step).transition(.opacity.combined(with: .offset(y: 12)))
                        SetupIllustration(step: step, permission: $selectedPermission).environmentObject(model)
                            .frame(maxWidth: 450).id(step).transition(.opacity.combined(with: .offset(y: 18)))
                    }.frame(maxWidth: 1060).padding(.horizontal, 56).padding(.vertical, 38)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }
            }
            HStack {
                Label("Private by default. Yours to pause.", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(Ink.ash)
                Spacer()
                Button {
                    musicEnabled.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: musicEnabled && !music.unavailable ? "speaker.wave.2" : "speaker.slash")
                        Text(music.unavailable ? "Music unavailable" : musicEnabled ? "Music on" : "Music off")
                    }.font(.system(size: 11)).foregroundStyle(Ink.ash).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(music.unavailable)
                    .accessibilityLabel(musicEnabled ? "Turn off onboarding music" : "Turn on onboarding music")
                    .help("Original ambient soundtrack · Plays only during onboarding")
            }.padding(.horizontal, 40).padding(.bottom, 24)
        }
        .background { LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.78), .init(color: Color(red: 0.91, green: 0.96, blue: 1), location: 1)], startPoint: .top, endPoint: .bottom) }
        .foregroundStyle(Ink.ivory).tint(setupBlue)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: step)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: introductionCompleted)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: introScene)
        .onAppear { step = min(3, max(0, step)); purpose = model.status?.settings.purpose ?? "recall"; if musicEnabled { music.play() } }
        .onChange(of: musicEnabled) { _, enabled in if enabled { music.play() } else { music.stop() } }
        .onDisappear { music.stop() }
    }

    private var introduction: some View {
        ZStack {
            Circle().fill(Color(red: 0.83, green: 0.92, blue: 1).opacity(0.38))
                .frame(width: 360, height: 360).blur(radius: 90).offset(y: 140).accessibilityHidden(true)
            VStack(spacing: 25) {
                if introScene == 0 {
                    DesktopRevealHost { introScene = 1 }
                } else if introScene == 1 {
                    Button("Replay orb intro") { introScene = 0 }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.ash)
                    Text("Hi. I’m Constant.").font(.system(size: 38, weight: .medium)).tracking(-1).modifier(WelcomeReveal(delay: 0))
                    Text("A quiet memory for the work you do.\nWhat should I call you?").font(.system(size: 17)).foregroundStyle(Ink.ash).lineSpacing(7).multilineTextAlignment(.center).modifier(WelcomeReveal(delay: 0.18))
                    TextField("Your first name (optional)", text: $preferredName).textFieldStyle(.plain)
                        .font(.system(size: 17)).multilineTextAlignment(.center).padding(16).frame(width: 310)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(setupBlue.opacity(0.18)))
                        .focused($nameFocused).onSubmit { introScene = 2 }
                        .onChange(of: preferredName) { _, name in if name.count > 40 { preferredName = String(name.prefix(40)) } }
                        .modifier(WelcomeReveal(delay: 0.32))
                    HStack(spacing: 24) {
                        Button("Continue") { introScene = 2 }.buttonStyle(SetupButton(primary: true))
                        Button("Skip for now") { preferredName = ""; introScene = 2 }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Ink.ash)
                    }.modifier(WelcomeReveal(delay: 0.45))
                    Text("Just for your welcome. Saved only on this Mac.").font(.system(size: 10)).foregroundStyle(Ink.ash).modifier(WelcomeReveal(delay: 0.55))
                } else {
                    ConstantMark().frame(width: 70, height: 70).modifier(WelcomeReveal(delay: 0))
                    Text(preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "A little less lost context." : "Nice to meet you, \(preferredName.trimmingCharacters(in: .whitespacesAndNewlines)).")
                        .font(.system(size: 35, weight: .medium)).tracking(-0.8).multilineTextAlignment(.center).modifier(WelcomeReveal(delay: 0.15))
                    Text("The useful details. The unfinished thoughts.\nLet’s give them a place to stay.").font(.system(size: 17)).foregroundStyle(Ink.ash).lineSpacing(7).multilineTextAlignment(.center).modifier(WelcomeReveal(delay: 0.35))
                    Button("Make it mine") { preferredName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines); step = 0; introductionCompleted = true }.buttonStyle(SetupButton(primary: true)).padding(.top, 13).modifier(WelcomeReveal(delay: 0.55))
                }
            }.id(introScene).padding(40).frame(maxWidth: 720)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity.combined(with: .offset(y: -8))))
        }
    }

    private var canContinue: Bool {
        guard model.connected, !busy else { return false }
        if step == 1 { return !model.permissionNeeded }
        if step >= 2 { return model.status?.model.available == true && !model.permissionNeeded }
        return true
    }
    private var footer: String {
        switch step {
        case 0: return "No account. No subscription to get started."
        case 1: return !model.connected ? "Checking access…" : model.permissionNeeded ? "Enable both permissions to continue. We’ll check automatically." : "You’re all set. Both permissions are enabled."
        case 2: return "Summaries are generated locally. Source text stays available."
        default: return "Closing the window keeps capture running. Quit to stop."
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.black.opacity(0.055), lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 2, y: 2)
    }
    private var welcome: some View {
        VStack(spacing: 11) {
            purposeCard("recall", title: "Pick up where I left off", detail: "Find the detail you remember seeing.", icon: "arrow.uturn.backward")
            purposeCard("review", title: "Make sense of my day", detail: "One continuous story across your apps.", icon: "text.alignleft")
            purposeCard("assistant", title: "Give my assistant context", detail: "Connect your local journal with MCP.", icon: "link")
        }
    }
    private func purposeCard(_ value: String, title: String, detail: String, icon: String) -> some View {
        Button { purpose = value } label: {
            card {
                HStack(spacing: 13) {
                    Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundStyle(setupBlue).frame(width: 22)
                    VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(Ink.ash).fixedSize(horizontal: false, vertical: true) }
                    Spacer(minLength: 0)
                    Image(systemName: purpose == value ? "checkmark.circle.fill" : "circle").foregroundStyle(purpose == value ? setupBlue : Ink.control).font(.system(size: 18))
                }
            }.overlay(RoundedRectangle(cornerRadius: 15).stroke(purpose == value ? setupBlue.opacity(0.25) : .clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 13) {
            permissionCard("Accessibility", detail: "Read text from the app you’re using.", granted: model.status?.permissions.accessibility == true, kind: "accessibility")
            permissionCard("Screen Recording", detail: "Read visible text with OCR. Images aren’t saved.", granted: model.status?.permissions.screenRecording == true, kind: "screen")
            HStack(spacing: 16) {
                Button("Check again") { Task { await model.refresh() } }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(setupBlue)
                Button(showHelp ? "Hide setup help" : "Need help?") { showHelp.toggle() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Ink.ash)
            }.padding(.top, 5)
            if showHelp {
                Text("In System Settings, enable Constant Watch. If access already looks enabled but isn’t detected, remove the old entry and add the installed app again. Quit and reopen if macOS asks.").font(.system(size: 11)).foregroundStyle(Ink.ash).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                Button("Show installed app in Finder ↗") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(setupBlue)
            }
        }
    }
    private func permissionCard(_ title: String, detail: String, granted: Bool, kind: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 10) {
                    Text(granted ? "\(title) permission granted." : "Enable \(title.lowercased())").font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle").font(.system(size: 23)).foregroundStyle(granted ? setupBlue : Ink.control).accessibilityLabel(granted ? "Granted" : "Not enabled")
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Ink.ash).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button(busy ? "Opening settings…" : "Open System Settings ↗") {
                        selectedPermission = kind; busy = true
                        Task { await model.requestPermissions(kind); busy = false }
                    }.buttonStyle(.plain).foregroundStyle(setupBlue).font(.system(size: 12, weight: .medium)).disabled(busy || !model.connected)
                }
            }
        }
    }
    private var intelligence: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text(model.modelTitle).font(.system(size: 18, weight: .medium)); Spacer(); Image(systemName: model.status?.model.available == true ? "checkmark.circle.fill" : "arrow.down.circle").font(.system(size: 22)).foregroundStyle(setupBlue) }
                    HStack(spacing: 24) { metric(model.modelParameters, label: "parameters"); metric(model.modelDownloadSize, label: "download"); metric("On-device", label: "summaries") }
                    Text(model.status?.model.available == true ? "Ready on this Mac." : "Download once. Then use it locally.").font(.system(size: 12)).foregroundStyle(Ink.ash)
                    if model.status?.model.available != true {
                        if let download = model.status?.download { ProgressView(value: download.fraction); Text(download.status).font(.caption).foregroundStyle(Ink.ash) }
                        Button("Prepare local model") { Task { await model.prepareModel() } }.buttonStyle(SetupButton()).disabled(model.status?.download?.running == true)
                        Button("Open Ollama ↗") { model.openOllama() }.buttonStyle(.plain).font(.caption).foregroundStyle(setupBlue)
                    }
                }
            }
            Label("No API key. No cloud processing.", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(Ink.ash)
        }
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 12, weight: .medium)); Text(label).font(.system(size: 10)).foregroundStyle(Ink.ash) }
    }
    private var firstMoment: some View {
        VStack(alignment: .leading, spacing: 16) {
            card {
                VStack(alignment: .leading, spacing: 13) {
                    if let observation = model.practiceObservation {
                        Label("Your first moment is here", systemImage: "checkmark.circle.fill").foregroundStyle(setupBlue).font(.system(size: 14, weight: .medium))
                        Text(observation.summary.isEmpty ? "Your note was captured. Its local summary is on the way." : observation.summary).font(.system(size: 12)).foregroundStyle(Ink.ash).lineSpacing(4).lineLimit(6)
                        Text("Search for “Atlas” in your journal.").font(.system(size: 12))
                    } else {
                        Text(practiceStarted ? "Keep the note visible for about 15 seconds, then come back. Your captured moment will appear here." : "We’ll open a short note in TextEdit. Leave it visible for about 15 seconds, then come back to see the result.").font(.system(size: 12)).foregroundStyle(Ink.ash).lineSpacing(4)
                    }
                    Button(practiceStarted || model.practiceObservation != nil ? "Open practice note again ↗" : "Open a practice note ↗") { practiceStarted = true; Task { await model.openPractice() } }.buttonStyle(SetupButton())
                }
            }
            Label("Pause anytime from your menu bar.", systemImage: "menubar.rectangle").font(.system(size: 11)).foregroundStyle(Ink.ash)
            if purpose == "assistant" { Button("Copy MCP configuration") { model.copyMCP() }.buttonStyle(.plain).font(.caption).foregroundStyle(setupBlue) }
        }
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
