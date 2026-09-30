import SwiftUI
import AppKit
import Combine

struct WatchSettings: Codable {
    var intervalSeconds: Int
    var paused: Bool
    var model: String
    var excludedApps: [String]
    var retentionDays: Int
    var onboardingComplete: Bool
    var purpose: String
}

struct CapturePermissions: Decodable {
    var accessibility: Bool
    var screenRecording: Bool
    var error: String?
}

struct ModelStatus: Decodable {
    var parameterSize: String?
    var downloadBytes: Int?
    var available: Bool
    var runtimeRunning: Bool?
    var runtimeInstalled: Bool?
    var model: String
    var error: String?
}

struct ServiceStatus: Decodable {
    var lastCapture: String?
    var lastApp: String?
    var error: String?
    var modelError: String?
    var captureStatus: String
    var warnings: [String]
    var settings: WatchSettings
    var permissions: CapturePermissions
    var model: ModelStatus
    var pendingSummaries: Int
    var dataDirectory: String
    var download: DownloadStatus?
    var meeting: MeetingState?
}

struct DownloadStatus: Decodable {
    var running: Bool
    var status: String
    var fraction: Double
}

struct CapturedApp: Decodable, Identifiable {
    var id: String { appId }
    var appId: String
    var appName: String
    var captures: Int
    var lastSeen: String
}

struct Observation: Decodable, Identifiable {
    var id: Int
    var capturedAt: String
    var day: String
    var appId: String
    var appName: String
    var windowTitle: String
    var axText: String
    var ocrText: String
    var summary: String
    var summaryStatus: String
    var model: String
    var warnings: String
}

struct DaySession: Decodable, Identifiable {
    var id: Int
    var start: String
    var end: String
    var appId: String
    var appName: String
    var windowTitle: String
    var summary: String
    var pendingSummaries: Int
    var observations: [Observation]
}

struct DayFlow: Decodable {
    var sessions: [DaySession]
    var totalSessions: Int
    var totalObservations: Int
    var nextOffset: Int?
}

enum APIError: LocalizedError {
    case response(Int)
    var errorDescription: String? {
        switch self { case .response(let code): return "The local service returned HTTP \(code)." }
    }
}

@MainActor
final class WatchModel: ObservableObject {
    static let shared = WatchModel()
    @Published var status: ServiceStatus?
    @Published var apps: [CapturedApp] = []
    @Published var observations: [Observation] = []
    @Published var sessions: [DaySession] = []
    @Published var totalSessions = 0
    @Published var selectedApp: String? = nil
    @Published var query = ""
    @Published var filterDate = Date()
    @Published var useDate = true
    @Published var error: String?
    @Published var loading = true
    @Published var hasMore = false
    @Published var settingsPresented = false
    @Published var meetingsPresented = false
    @Published var meetingSelection: String?
    @Published var connected = false
    @Published var showOnboarding = false
    @Published var onboardingReplayID = UUID()

    func replayOrbIntro() {
        UserDefaults.standard.set(false, forKey: "onboardingIntroductionCompleted")
        onboardingReplayID = UUID()
        showOnboarding = true
        NSApp.activate(ignoringOtherApps: true)
    }
    @Published var practiceObservation: Observation?
    @Published var evidenceID: Int?
    var backend: Process?
    var pollTask: Task<Void, Never>?
    var nativeTask: Task<Void, Never>?
    private let nativeToken = UUID().uuidString + UUID().uuidString
    private var refreshInFlight = false
    private var generation = 0
    private var logHandle: FileHandle?
    private let base = URL(string: "http://127.0.0.1:8765")!

    var modelName: String { status?.settings.model ?? "qwen3.5:0.8b" }
    var modelTitle: String { modelName == "qwen3.5:0.8b" ? "Qwen 3.5 · 0.8B" : modelName }
    var modelParameters: String { status?.model.parameterSize ?? (modelName == "qwen3.5:0.8b" ? "0.8B" : "—") }
    var modelDownloadSize: String {
        if let bytes = status?.model.downloadBytes { return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
        return modelName == "qwen3.5:0.8b" ? "~1 GB" : "—"
    }
    var isDailyFlow: Bool { selectedApp == nil && query.isEmpty && useDate }
    var title: String { apps.first { $0.appId == selectedApp }?.appName ?? (query.isEmpty ? "Daily flow" : "Search results") }
    var filterKey: String { "\(selectedApp ?? "")|\(query)|\(day)|\(useDate)" }
    var day: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: filterDate)
    }
    var permissionNeeded: Bool {
        guard let status else { return true }
        return !status.permissions.accessibility || !status.permissions.screenRecording
    }
    var stateLabel: String {
        if status?.meeting?.active != nil { return "Recording meeting" }
        guard connected, let status else { return "Connecting" }
        if status.settings.paused { return "Paused" }
        if permissionNeeded { return "Setup needed" }
        if status.error != nil { return "Needs attention" }
        return "Watching locally"
    }
    var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Constant Watch")
    }

    func start() {
        guard pollTask == nil else { return }
        startBackend()
        startNativeBridge()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func startBackend() {
        guard backend?.isRunning != true else { return }
        let runtime = root.appendingPathComponent("runtime")
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Runtime.app/Contents/MacOS/constant-watch")
        let packaged = FileManager.default.isExecutableFile(atPath: bundled.path)
        let executable = packaged ? bundled : runtime.appendingPathComponent("venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            error = "The app’s local service is missing. Reinstall Constant Watch from its disk image."
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = packaged ? ["serve"] : ["-m", "constant_watch.cli", "serve"]
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        process.currentDirectoryURL = packaged ? root : runtime
        var environment = ProcessInfo.processInfo.environment
        environment["CONSTANT_WATCH_HELPER"] = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Constant Watch Capture.app/Contents/MacOS/capture").path
        environment["CONSTANT_WATCH_DATA"] = root.path
        environment["CONSTANT_WATCH_NATIVE_TOKEN"] = nativeToken
        process.environment = environment
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Constant Watch")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appendingPathComponent("native-service.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            logHandle = handle
            process.standardOutput = handle
            process.standardError = handle
        }
        do { try process.run(); backend = process }
        catch { self.error = "Could not start local service: \(error.localizedDescription)" }
    }

    func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let url = URL(string: path, relativeTo: base)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 25
        request.setValue("local", forHTTPHeaderField: "X-Constant-Watch")
        if path.hasPrefix("/api/native/") { request.setValue(nativeToken, forHTTPHeaderField: "X-Constant-Watch-Native") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.response((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func decoded<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: await request(path))
    }

    func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false; loading = false }
        do {
            async let newStatus = decoded(ServiceStatus.self, path: "/api/status")
            async let newApps = decoded([CapturedApp].self, path: "/api/apps")
            let (s, a) = try await (newStatus, newApps)
            status = s; apps = a; connected = true
            error = s.permissions.error ?? s.error ?? s.modelError
            if isDailyFlow || observations.count <= 50 { await loadObservations() }
            if showOnboarding || !s.settings.onboardingComplete {
                practiceObservation = try? await decoded([Observation].self, path: "/api/observations?q=ConstantWatchFirstMoment&limit=1").first
            }
        } catch {
            connected = false
            self.error = "Waiting for the local service. \(error.localizedDescription)"
        }
    }

    func loadObservations(append: Bool = false) async {
        generation += 1
        let version = generation
        if isDailyFlow {
            do {
                let offset = append ? sessions.count : 0
                let limit = append ? 50 : max(50, sessions.count)
                // Refresh all loaded pages so a completed summary updates in place.
                var collected: [DaySession] = []
                var next: Int? = offset
                var total = 0
                while let cursor = next, collected.count < limit {
                    let page = try await decoded(DayFlow.self, path: "/api/day-flow?day=\(day)&offset=\(cursor)&limit=\(min(200, limit-collected.count))")
                    collected += page.sessions; next = page.nextOffset; total = page.totalSessions
                }
                guard version == generation else { return }
                sessions = append ? sessions + collected : collected
                totalSessions = total; hasMore = next != nil
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            return
        }
        var components = URLComponents()
        components.path = "/api/observations"
        components.queryItems = [URLQueryItem(name: "app_id", value: selectedApp ?? ""),
                                 URLQueryItem(name: "day", value: useDate ? day : ""),
                                 URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "50")]
        if append, let last = observations.last {
            components.queryItems?.append(URLQueryItem(name: "before", value: String(last.id)))
        }
        do {
            let result = try await decoded([Observation].self, path: components.string!)
            guard version == generation else { return }
            observations = append ? observations + result : result
            hasMore = result.count == 50
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func save(_ settings: WatchSettings) async -> Bool {
        do {
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
            _ = try await request("/api/settings", method: "PUT", body: encoder.encode(settings))
            await refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func togglePause() async {
        guard var settings = status?.settings else { return }
        settings.paused.toggle()
        _ = await save(settings)
    }

    func requestPermissions(_ kind: String = "all") async {
        // Request from the same long-lived application that reads the screen.
        _ = await CaptureCore.run(kind == "all" ? "permissions" : "request-\(kind)")
        openPrivacy(kind == "screen" ? "Privacy_ScreenCapture" : "Privacy_Accessibility")
        await refresh()
    }

    private struct NativeCommand: Decodable {
        let id: String?
        let command: String?
        let excluded: [String]?
        let payload: MeetingPayload?
    }

    private struct MeetingPayload: Decodable {
        let meetingId: String?
        let microphone: Bool?
        let systemAudio: Bool?
        var dictionary: [String: Any] {
            var value: [String: Any] = [:]
            value["meeting_id"] = meetingId; value["microphone"] = microphone; value["system_audio"] = systemAudio
            return value
        }
    }

    func startNativeBridge() {
        guard nativeTask == nil else { return }
        nativeTask = Task {
            while !Task.isCancelled {
                do {
                    let job = try await decoded(NativeCommand.self, path: "/api/native/next")
                    guard let id = job.id, let command = job.command else { continue }
                    let result = command.hasPrefix("meeting-")
                        ? await MeetingRecorder.shared.command(command, payload: job.payload?.dictionary ?? [:])
                        : await CaptureCore.run(command, excluded: Set(job.excluded ?? []))
                    let body = try JSONSerialization.data(withJSONObject: result)
                    _ = try await request("/api/native/result/\(id)", method: "POST", body: body)
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

    func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") {
            NSWorkspace.shared.open(url)
        }
    }

    func showNotes() {
        let folder = root.appendingPathComponent("days")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    func exportMarkdown() async {
        guard useDate else { return }
        var c = URLComponents()
        c.path = "/api/markdown"
        c.queryItems = [.init(name: "app_id", value: selectedApp ?? ""), .init(name: "day", value: day)]
        do {
            let data = try await request(c.string!)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(title)-\(day).md"
            panel.title = "Export daily journal"
            if await panel.begin() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
        } catch { self.error = error.localizedDescription }
    }

    func copyMCP() {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Runtime.app/Contents/MacOS/constant-watch")
        let command = FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled.path : root.appendingPathComponent("runtime/venv/bin/constant-watch").path
        let config: [String: Any] = ["mcpServers": ["constant-watch": ["command": command, "args": ["mcp"]]]]
        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func prepareModel() async {
        do { _ = try await request("/api/model/setup", method: "POST"); await refresh() }
        catch { self.error = error.localizedDescription }
    }

    func openOllama() {
        let candidates = [URL(fileURLWithPath: "/Applications/Ollama.app"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ollama.app")]
        if let installed = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.openApplication(at: installed, configuration: .init())
            Task { await prepareModel() }
        } else { NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!) }
    }

    func openPractice() async {
        guard var settings = status?.settings else { return }
        settings.paused = false
        guard await save(settings) else { return }
        let path = root.appendingPathComponent("Your first moment.txt")
        let text = """
        Your first moment with Constant Watch
        ConstantWatchFirstMoment

        Project Atlas — a note worth remembering.

        The launch review is Friday at 10 AM.
        Bring the revised prototype and the three customer interviews.
        The next step is to compare the onboarding concepts.

        This is a practice note created by Constant Watch.
        Leave it on screen for about 15 seconds, then return to the app.
        You will find this moment in your daily flow and by searching Atlas.
        """
        do { try text.write(to: path, atomically: true, encoding: .utf8); NSWorkspace.shared.open(path) }
        catch { self.error = error.localizedDescription }
    }

    func finishOnboarding(purpose: String, start: Bool) async {
        guard var settings = status?.settings else { return }
        settings.onboardingComplete = true; settings.purpose = purpose; settings.paused = !start
        if await save(settings) { showOnboarding = false }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await WatchModel.shared.refresh() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = WatchModel.shared
        Task {
            // Keep the bridge alive until audio files are finalized and their session is saved.
            _ = try? await model.request("/api/meetings/stop", method: "POST")
            _ = await MeetingRecorder.shared.command("meeting-stop", payload: [:])
            model.pollTask?.cancel()
            model.nativeTask?.cancel()
            if let process = model.backend, process.isRunning {
                process.terminate()
                for _ in 0..<50 {
                    if !process.isRunning { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct ConstantWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = WatchModel.shared
    var body: some Scene {
        Window("Constant Watch", id: "journal") {
            AppRootView().environmentObject(model).task { model.start() }
                .preferredColorScheme(.light)
                .sheet(isPresented: $model.meetingsPresented) { MeetingsSheet().preferredColorScheme(.light) }
                .onOpenURL { url in
                    if url.scheme == "constantwatch" {
                        if url.host == "onboarding" { model.showOnboarding = true }
                        if url.host == "replay" { model.replayOrbIntro() }
                        if url.host == "observation", let id = Int(url.lastPathComponent), id > 0 { model.evidenceID = id }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .defaultSize(width: 1120, height: 780)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Meetings…") { model.meetingsPresented = true }
                Button("Capture settings…") { model.settingsPresented = true }.keyboardShortcut(",")
                Button("Show notes in Finder") { model.showNotes() }
                Button("Replay orb intro") { model.replayOrbIntro() }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Setup guide…") { model.showOnboarding = true }
            }
        }
        MenuBarExtra("Constant Watch", systemImage: model.status?.meeting?.active != nil ? "record.circle.fill" : model.status?.settings.paused == true ? "pause.circle" : "eye.circle") {
            WatchMenu().environmentObject(model)
        }
    }
}

struct WatchMenu: View {
    @EnvironmentObject var model: WatchModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(model.stateLabel)
        if let app = model.status?.lastApp { Text(app).font(.caption) }
        Divider()
        if model.status?.meeting?.active != nil {
            Button("Stop meeting recording") { Task { _ = try? await model.request("/api/meetings/stop", method: "POST"); await model.refresh() } }
        }
        Button("Meetings") { openWindow(id: "journal"); model.meetingsPresented = true; NSApp.activate(ignoringOtherApps: true) }
        Button("Open journal") { openWindow(id: "journal"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.status?.settings.paused == true ? "Resume capture" : "Pause capture") { Task { await model.togglePause() } }
            .disabled(model.status == nil)
        Button("Show notes in Finder") { model.showNotes() }
        Button("Copy MCP configuration") { model.copyMCP() }
        Button("Replay orb intro") { openWindow(id: "journal"); model.replayOrbIntro() }
        Button("Setup guide") { model.showOnboarding = true; openWindow(id: "journal"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit Constant Watch") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

let accent = Color(red: 0.322, green: 0.400, blue: 0.922)

struct JournalView: View {
    @EnvironmentObject var model: WatchModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "eye.circle.fill").font(.system(size: 32)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("constant").font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text("LOCAL SCREEN MEMORY").font(.system(size: 8, design: .monospaced)).tracking(1.4).foregroundStyle(.secondary)
                    }
                }.padding(22)
                List(selection: $model.selectedApp) {
                    Label("Daily flow", systemImage: "point.topleft.down.to.point.bottomright.curvepath").tag(Optional<String>.none)
                    Section("Applications") {
                        ForEach(model.apps) { app in
                            HStack(spacing: 8) {
                                AppIcon(bundleId: app.appId, size: 21)
                                Text(app.appName).lineLimit(1)
                                Spacer()
                                Text("\(app.captures)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            }.tag(Optional(app.appId))
                        }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Stored on this Mac", systemImage: "internaldrive").font(.caption).foregroundStyle(.secondary)
                    Button("Capture settings", systemImage: "slider.horizontal.3") { model.settingsPresented = true }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(accent)
                }.padding(22)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 285)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        introduction
                        if model.permissionNeeded { permissionsCard }
                        if let status = model.status, !status.model.available {
                            callout("Local model unavailable", text: status.model.error ?? "Start Ollama to generate summaries.", icon: "cpu")
                        }
                        if let error = model.error {
                            HStack {
                                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                                Spacer()
                                if !model.connected { Button("Retry") { model.startBackend(); Task { await model.refresh() } } }
                            }.padding(14).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        }
                        journal
                    }.padding(30)
                }
                Divider()
                HStack {
                    Text(model.status?.captureStatus ?? "Starting local service")
                    Spacer()
                    if let status = model.status {
                        Text("Every \(status.settings.intervalSeconds)s · \(status.pendingSummaries) pending · \(status.settings.model)")
                    }
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 25).padding(.vertical, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    HStack(spacing: 6) {
                        Circle().fill(model.permissionNeeded || model.status?.settings.paused == true ? Color.orange : Color.green).frame(width: 6, height: 6)
                        Text(model.stateLabel).font(.caption)
                    }.padding(.trailing, 8)
                    Button {
                        Task { await model.togglePause() }
                    } label: { Label(model.status?.settings.paused == true ? "Resume" : "Pause", systemImage: model.status?.settings.paused == true ? "play" : "pause") }
                    .disabled(model.status == nil)
                    Button { model.showNotes() } label: { Label("Notes folder", systemImage: "folder") }
                }
            }
        }
        .tint(accent)
        .frame(minWidth: 800, minHeight: 540)
        .sheet(isPresented: $model.settingsPresented) { CaptureSettingsView().environmentObject(model) }
        .task(id: model.filterKey) {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { await model.loadObservations() }
        }
    }

    private var introduction: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 13) {
                Text("A RECORD OF WHAT’S ON YOUR SCREEN").font(.system(size: 9, design: .monospaced)).tracking(1.3).foregroundStyle(.secondary)
                (Text("A little less\n") + Text("lost context.").foregroundColor(accent))
                    .font(.system(size: 40, weight: .medium, design: .rounded)).tracking(-1.5).lineSpacing(-1)
                Text("One continuous journal of your day, across every app.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            HStack(spacing: 16) {
                pipelineStep("Read", subtitle: "AX + OCR", icon: "viewfinder")
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                pipelineStep("Understand", subtitle: "On-device", icon: "cpu")
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                pipelineStep("Remember", subtitle: "MD + MCP", icon: "text.book.closed")
            }
        }.padding(.vertical, 15)
    }

    func pipelineStep(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(accent).frame(width: 50, height: 50)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            Text(title).font(.system(size: 10, weight: .medium))
            Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    func callout(_ title: String, text: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.callout.weight(.semibold)); Text(text).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }.padding(18).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Give your journal access to the screen", systemImage: "lock.shield").font(.callout.weight(.semibold))
            Text("Enable Constant Watch in macOS Privacy & Security. Accessibility reads app text; Screen Recording enables OCR. Capture starts when access is available.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Request access") { Task { await model.requestPermissions() } }.buttonStyle(.borderedProminent)
                Button("Accessibility ↗") { model.openPrivacy("Privacy_Accessibility") }
                Button("Screen Recording ↗") { model.openPrivacy("Privacy_ScreenCapture") }
            }.controlSize(.small)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR JOURNAL").font(.system(size: 9, design: .monospaced)).tracking(1.4).foregroundStyle(.secondary)
                    Text(model.title).font(.title2.weight(.medium))
                }
                Spacer()
                Button("Export Markdown", systemImage: "square.and.arrow.up") { Task { await model.exportMarkdown() } }
                    .disabled(!model.useDate || (model.isDailyFlow ? model.sessions.isEmpty : model.observations.isEmpty))
            }.padding(22)
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your screen memory…", text: $model.query).textFieldStyle(.plain)
                }.padding(9).background(Color(nsColor: .quaternaryLabelColor).opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
                Toggle("Date", isOn: $model.useDate).toggleStyle(.checkbox).font(.caption)
                if model.useDate { DatePicker("Date", selection: $model.filterDate, displayedComponents: .date).labelsHidden().fixedSize() }
            }.padding(.horizontal, 22).padding(.bottom, 20)
            Divider()
            HStack {
                Text(model.isDailyFlow ? "\(model.totalSessions) grouped sessions · chronological order" : "\(model.observations.count) captured moments")
                Spacer()
                Text("SOURCE TEXT + LOCAL SUMMARIES")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            if model.isDailyFlow ? model.sessions.isEmpty : model.observations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: model.loading ? "hourglass" : "text.book.closed").font(.system(size: 34, weight: .light)).foregroundStyle(accent.opacity(0.5))
                    Text(model.query.isEmpty ? "Your next thought has a place." : "No matching moments.").font(.title3)
                    Text(model.query.isEmpty ? "Use your apps as usual. New screen text appears here\nautomatically once screen permissions are enabled." : "Try a different search, application, or date.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 45)
            } else if model.isDailyFlow {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.sessions) { session in
                        DaySessionRow(session: session)
                        if session.id != model.sessions.last?.id {
                            HStack { Rectangle().fill(accent.opacity(0.25)).frame(width: 2, height: 24); Text("↓").font(.caption).foregroundStyle(.secondary) }.padding(.leading, 33)
                        }
                    }
                }
                if model.hasMore {
                    Button("Continue through the day") { Task { await model.loadObservations(append: true) } }.frame(maxWidth: .infinity).padding(20)
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(model.observations) { row in
                        ObservationRow(row: row)
                        if row.id != model.observations.last?.id { Divider().padding(.leading, 96) }
                    }
                }
                if model.hasMore {
                    Button("Load earlier activity") { Task { await model.loadObservations(append: true) } }
                        .frame(maxWidth: .infinity).padding(20)
                }
            }
        }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct AppIcon: View {
    let bundleId: String
    let size: CGFloat
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: size, height: size)
        } else {
            Image(systemName: "app").resizable().frame(width: size, height: size).foregroundStyle(.secondary)
        }
    }
}

struct DaySessionRow: View {
    let session: DaySession
    @State private var expanded = false
    private func time(_ stamp: String) -> String { String(stamp.dropFirst(11).prefix(5)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIcon(bundleId: session.appId, size: 24)
                Text(session.appName).font(.callout.weight(.semibold))
                Spacer()
                Text("\(time(session.start))–\(time(session.end))").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(session.windowTitle.isEmpty ? "Untitled window" : session.windowTitle).font(.callout.weight(.medium)).textSelection(.enabled)
            Text(session.summary.isEmpty ? "Screen text saved. A local summary will appear here shortly." : session.summary)
                .font(.callout).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
            if session.pendingSummaries > 0 {
                Text("\(session.pendingSummaries) summaries pending").font(.caption2).foregroundStyle(.secondary)
            }
            DisclosureGroup("\(session.observations.count) captured moments · view evidence", isExpanded: $expanded) {
                ForEach(session.observations) { row in ObservationRow(row: row) }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ObservationRow: View {
    let row: Observation
    @State private var expanded = false
    var time: String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: row.capturedAt)?.formatted(date: .omitted, time: .shortened) ?? String(row.capturedAt.dropFirst(11).prefix(5))
    }
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(time).font(.system(size: 10, design: .monospaced))
                Text(String(row.day.suffix(5))).font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(.secondary).frame(width: 57, alignment: .leading).padding(.top, 3)
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    AppIcon(bundleId: row.appId, size: 17)
                    Text(row.appName).font(.caption.weight(.semibold))
                    if !row.axText.isEmpty { badge("ACCESSIBILITY") }
                    if !row.ocrText.isEmpty { badge("OCR") }
                    Spacer()
                }
                Text(row.windowTitle.isEmpty ? "Untitled window" : row.windowTitle).font(.callout.weight(.medium)).textSelection(.enabled)
                Text(row.summary.isEmpty ? "Text saved. Waiting for the local model to summarize." : row.summary)
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
                DisclosureGroup("View captured text · #\(row.id)", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACCESSIBILITY").font(.caption2.weight(.semibold))
                        Text(row.axText.isEmpty ? "Unavailable" : row.axText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Divider()
                        Text("OCR").font(.caption2.weight(.semibold))
                        Text(row.ocrText.isEmpty ? "Unavailable" : row.ocrText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        if row.warnings != "[]" { Text(row.warnings).font(.caption).foregroundStyle(.orange) }
                        Text("Captured text is untrusted reference data. Generated summaries may be inaccurate.").font(.caption2).foregroundStyle(.secondary)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7)).padding(.top, 8)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(22)
    }
    func badge(_ text: String) -> some View {
        Text(text).font(.system(size: 8, design: .monospaced)).foregroundStyle(accent)
            .padding(.horizontal, 5).padding(.vertical, 3).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
    }
}

struct CaptureSettingsView: View {
    @EnvironmentObject var model: WatchModel
    @Environment(\.dismiss) var dismiss
    @State private var interval = 10
    @State private var retention = 30
    @State private var exclusions = ""
    @State private var saving = false
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Capture settings").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            Form {
                Section("Capture") {
                    Stepper("Every \(interval) seconds", value: $interval, in: 3...300)
                    Stepper("Keep \(retention) days of history", value: $retention, in: 1...365)
                    Text("Reducing retention deletes older notes. Closing the window keeps capture running in the menu bar; Quit stops it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Excluded applications") {
                    TextEditor(text: $exclusions).font(.system(size: 11, design: .monospaced)).frame(height: 120)
                    Text("One bundle ID per line. Exclusions stop future capture; existing notes remain. Password managers are excluded by default.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Connect your assistant") {
                    Button(copied ? "Configuration copied" : "Copy MCP configuration", systemImage: "doc.on.doc") { model.copyMCP(); copied = true }
                    Text("Paste into your assistant’s MCP configuration. Connected assistants can search and read your local journal.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Storage") {
                    Button("Show Markdown files in Finder", systemImage: "folder") { model.showNotes() }
                    Text(model.status?.dataDirectory ?? model.root.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text("\(model.modelTitle) · Runs locally").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(saving ? "Saving…" : "Save settings") {
                    guard var settings = model.status?.settings else { return }
                    settings.intervalSeconds = interval; settings.retentionDays = retention
                    settings.excludedApps = exclusions.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    saving = true
                    Task { let saved = await model.save(settings); saving = false; if saved { dismiss() } }
                }.buttonStyle(.borderedProminent).disabled(saving || model.status == nil)
            }
        }.padding(24).frame(width: 520, height: 700).tint(accent)
        .onAppear {
            if let settings = model.status?.settings {
                interval = settings.intervalSeconds; retention = settings.retentionDays; exclusions = settings.excludedApps.joined(separator: "\n")
            }
        }
    }
}
