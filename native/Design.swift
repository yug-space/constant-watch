import SwiftUI
import AppKit

enum Ink {
    static let canvas = Color.white
    static let card = Color(red: 245/255, green: 246/255, blue: 249/255)
    static let control = Color(red: 234/255, green: 237/255, blue: 243/255)
    static let ivory = Color(red: 29/255, green: 39/255, blue: 53/255)
    static let ash = Color(red: 98/255, green: 109/255, blue: 124/255)
}

struct QuietButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .regular))
            .padding(.horizontal, 19).padding(.vertical, 11)
            .foregroundStyle(primary ? .white : Ink.ivory)
            .background(primary ? accent : Ink.control, in: Capsule())
            .opacity(!isEnabled ? 0.35 : configuration.isPressed ? 0.7 : 1)
    }
}

struct Wordmark: View {
    var color: Color = Ink.ivory
    var body: some View {
        HStack(spacing: 10) {
            ConstantMark().frame(width: 28, height: 28)
            Text("constant").font(.system(size: 22, weight: .medium)).tracking(0.3)
        }.foregroundStyle(color)
    }
}

struct AlpineImage: View {
    var body: some View {
        GeometryReader { geometry in
            if let path = Bundle.main.url(forResource: "AlpineHero", withExtension: "jpg"), let image = NSImage(contentsOf: path) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else { Ink.card }
        }.accessibilityHidden(true)
    }
}

struct AppRootView: View {
    @EnvironmentObject var model: WatchModel
    var body: some View {
        Group {
            if model.status == nil {
                VStack(spacing: 18) {
                    Wordmark()
                    ProgressView().controlSize(.small)
                    Text(model.error ?? "Opening your local workspace…").font(.system(size: 12)).foregroundStyle(Ink.ash).multilineTextAlignment(.center).frame(maxWidth: 380)
                    if model.error != nil { Button("Retry") { model.startBackend(); Task { await model.refresh() } }.buttonStyle(QuietButton()) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.showOnboarding || model.status?.settings.onboardingComplete != true {
                OnboardingView().id(model.onboardingReplayID)
            } else { DayWorkspaceView() }
        }.background(Ink.canvas).foregroundStyle(Ink.ivory).tint(accent)
            .frame(minWidth: 920, minHeight: 680)
            .sheet(isPresented: Binding(get: { model.evidenceID != nil }, set: { if !$0 { model.evidenceID = nil } })) {
                if let id = model.evidenceID { RecallEvidenceView(observationID: id).environmentObject(model) }
            }
    }
}

struct DayWorkspaceView: View {
    @EnvironmentObject var model: WatchModel
    @State private var copied = false
    @State private var section = "review"
    @FocusState private var searchFocused: Bool
    var dayLabel: String { model.filterDate.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 224)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("YOUR PRIVATE WORKSPACE").font(.system(size: 9)).tracking(2).foregroundStyle(Ink.ash)
                    Spacer()
                    Circle().fill(Ink.ash).frame(width: 5, height: 5)
                    Text(model.stateLabel).font(.caption).foregroundStyle(Ink.ash)
                    Button { Task { await model.togglePause() } } label: {
                        Label(model.status?.settings.paused == true ? "Resume" : "Pause", systemImage: model.status?.settings.paused == true ? "play" : "pause")
                    }.buttonStyle(QuietButton()).disabled(model.status == nil)
                }.padding(.horizontal, 32).padding(.vertical, 20)
                if let meeting = model.status?.meeting, meeting.active != nil || meeting.candidate != nil {
                    HStack(spacing: 12) {
                        Image(systemName: meeting.active != nil ? "record.circle.fill" : "waveform").foregroundStyle(meeting.active != nil ? Color.red : Color.blue)
                        Text(meeting.active != nil ? "Recording · " + (meeting.active?.title ?? "Meeting") : "Meeting detected · " + (meeting.candidate?.appName ?? "Call")).font(.callout)
                        Spacer()
                        Button(meeting.active != nil ? "Open recording" : "Review & record") { model.meetingsPresented = true }.buttonStyle(QuietButton())
                        if meeting.active == nil {
                            Button("Dismiss") { Task { _ = try? await model.request("/api/meetings/dismiss", method: "POST"); await model.refresh() } }.buttonStyle(QuietButton())
                        }
                    }.padding(.horizontal, 32).padding(.vertical, 10).background(Ink.card)
                }
                if section == "review" {
                    ReviewWorkspace()
                } else if section != "journal" {
                    RecallWorkspace(showTopics: section == "topics").id(section)
                } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(dayLabel).font(.callout).foregroundStyle(Ink.ash)
                                Text(model.selectedApp == nil && model.query.isEmpty ? "Your day, in one thread." : model.title)
                                    .font(.system(size: 32, weight: .medium)).tracking(0.3)
                                Text("The useful details, gathered as you go.").font(.callout).foregroundStyle(Ink.ash)
                            }
                            Spacer()
                            Button { Task { await model.exportMarkdown() } } label: { Label("Export day", systemImage: "arrow.down.to.line") }
                                .buttonStyle(QuietButton())
                                .disabled(!model.useDate || (model.isDailyFlow ? model.sessions.isEmpty : model.observations.isEmpty))
                        }.padding(.top, 16)
                        controls
                        if model.permissionNeeded {
                            HStack(spacing: 16) {
                                Image(systemName: "lock.shield").font(.title2)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("One more step before your day can take shape.").font(.callout)
                                    Text("macOS needs your permission to read the screen.").font(.caption).foregroundStyle(Ink.ash)
                                }
                                Spacer()
                                Button("Finish setup") { model.showOnboarding = true }.buttonStyle(QuietButton(primary: true))
                            }.padding(24).background(Ink.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if let error = model.error {
                            HStack {
                                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Ink.ash)
                                Spacer()
                                Button("Retry") { model.startBackend(); Task { await model.refresh() } }.buttonStyle(QuietButton())
                            }
                        }
                        if model.isDailyFlow { dailyFlow } else { searchResults }
                    }.padding(.horizontal, 32).padding(.bottom, 32)
                }
                }
                HStack {
                    Image(systemName: "internaldrive")
                    Text("Saved on this Mac")
                    Spacer()
                    if let s = model.status { Text("\(s.pendingSummaries) summaries pending · Every \(s.settings.intervalSeconds)s") }
                }.font(.system(size: 10)).foregroundStyle(Ink.ash).padding(.horizontal, 32).padding(.vertical, 16)
            }.frame(maxWidth: .infinity).background(Ink.canvas)
        }
        .background(Ink.canvas)
        .sheet(isPresented: $model.settingsPresented) { CaptureSettingsView().environmentObject(model).preferredColorScheme(.light) }
        .task(id: model.filterKey) {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { await model.loadObservations() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark().padding(.horizontal, 24).padding(.top, 29).padding(.bottom, 42)
            navButton("Review", icon: "sun.horizon", selected: section == "review") { section = "review" }
            navButton("Ask your day", icon: "text.bubble", selected: section == "ask") { section = "ask" }
            navButton("Meetings", icon: "waveform", selected: false) { model.meetingsPresented = true }
            navButton("Topics", icon: "square.stack.3d.up", selected: section == "topics") { section = "topics" }
            navButton("Daily flow", icon: "point.topleft.down.to.point.bottomright.curvepath", selected: section == "journal" && model.selectedApp == nil && model.query.isEmpty) {
                section = "journal"; model.selectedApp = nil; model.query = ""; model.useDate = true
            }
            navButton("Find a moment", icon: "magnifyingglass", selected: section == "journal" && !model.query.isEmpty) { section = "journal"; searchFocused = true }
            Text("APPLICATIONS").font(.system(size: 9)).tracking(1.7).foregroundStyle(Ink.ash).padding(.horizontal, 24).padding(.top, 35).padding(.bottom, 14)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.apps) { app in
                        Button {
                            section = "journal"; model.selectedApp = app.appId; model.query = ""
                        } label: {
                            HStack(spacing: 10) {
                                AppIcon(bundleId: app.appId, size: 19)
                                Text(app.appName).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(app.captures)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.ash)
                            }.padding(12).background(model.selectedApp == app.appId ? Ink.control : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    if model.apps.isEmpty { Text("Your apps will appear here\nas your day unfolds.").font(.caption).foregroundStyle(Ink.ash).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 10) {
                Text("CONTEXT, WHEN YOU NEED IT").font(.system(size: 8)).tracking(1.1).foregroundStyle(Ink.ash)
                Text("Bring your day\nto your assistant.").font(.system(size: 17, weight: .medium)).lineSpacing(4)
                Button(copied ? "Configuration copied ✓" : "Connect with MCP ↗") { model.copyMCP(); copied = true }.buttonStyle(.plain).font(.caption).padding(.top, 4)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Ink.control.opacity(0.65), in: RoundedRectangle(cornerRadius: 12)).padding(16)
            navButton("Preferences", icon: "slider.horizontal.3", selected: false) { model.settingsPresented = true }
            navButton("Replay orb intro", icon: "play.circle", selected: false) { model.replayOrbIntro() }
            navButton("Setup guide", icon: "sparkle", selected: false) { model.showOnboarding = true }
            Text("No account. No cloud archive.").font(.system(size: 10)).foregroundStyle(Ink.ash).padding(24)
        }.background(Ink.card)
    }

    private func navButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) { Image(systemName: icon).frame(width: 17); Text(title); Spacer() }
                .font(.system(size: 12)).padding(12).background(selected ? Ink.control : .clear, in: Capsule())
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 4)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Ink.ash)
                TextField("Find a detail, a project, a thought…", text: $model.query).textFieldStyle(.plain).focused($searchFocused)
                if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            }.font(.system(size: 12)).padding(13).background(Ink.control, in: Capsule())
            Button { model.filterDate = Calendar.current.date(byAdding: .day, value: -1, to: model.filterDate)! } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Previous day")
            DatePicker("Journal date", selection: $model.filterDate, displayedComponents: .date).labelsHidden().fixedSize()
            Button { model.filterDate = Calendar.current.date(byAdding: .day, value: 1, to: model.filterDate)! } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain).accessibilityLabel("Next day")
        }
    }

    private var dailyFlow: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("DAILY FLOW").tracking(1.7)
                Spacer()
                Text("\(model.totalSessions) sessions · Earliest first")
            }.font(.system(size: 10)).foregroundStyle(Ink.ash)
            if model.sessions.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.sessions) { session in
                        DaySessionRow(session: session).background(Ink.card, in: RoundedRectangle(cornerRadius: 12))
                        if session.id != model.sessions.last?.id {
                            HStack(spacing: 10) { Rectangle().fill(Ink.ash.opacity(0.3)).frame(width: 1, height: 30); Text("Then").font(.system(size: 9)).foregroundStyle(Ink.ash) }.padding(.leading, 32)
                        }
                    }
                }
                if model.hasMore { Button("Continue through the day") { Task { await model.loadObservations(append: true) } }.buttonStyle(QuietButton()).frame(maxWidth: .infinity) }
                Text("Times show first and last observations. Summaries are generated locally; expand any session to check the source.").font(.system(size: 10)).foregroundStyle(Ink.ash).lineSpacing(4)
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(model.observations.count) matching moments").font(.caption).foregroundStyle(Ink.ash)
            if model.observations.isEmpty { emptyState }
            ForEach(model.observations) { row in ObservationRow(row: row).background(Ink.card, in: RoundedRectangle(cornerRadius: 12)) }
            if model.hasMore { Button("Load more moments") { Task { await model.loadObservations(append: true) } }.buttonStyle(QuietButton()) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 17) {
            Image(systemName: "text.book.closed").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(Ink.ash)
            Text(model.query.isEmpty ? "A little space for what comes next." : "That moment isn’t here yet.").font(.system(size: 23, weight: .medium))
            Text(model.query.isEmpty ? "Keep working. Your next captured moment will start the thread.\nOr open a practice note and see it happen." : "Try fewer words or another date. Search matches words\nin both your source text and your local summaries.")
                .font(.callout).foregroundStyle(Ink.ash).multilineTextAlignment(.center).lineSpacing(5)
            if model.query.isEmpty {
                Button("Try a practice note") { Task { await model.openPractice() } }.buttonStyle(QuietButton(primary: true)).disabled(model.permissionNeeded)
            }
        }.padding(.vertical, 50).frame(maxWidth: .infinity).background(Ink.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
