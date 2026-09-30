import SwiftUI
import AppKit

struct RecallTopic: Decodable, Identifiable {
    var key: String
    var label: String
    var captures: Int
    var appCount: Int
    var apps: String
    var id: String { key }
}
struct RecallSource: Decodable, Identifiable {
    var id: Int
    var capturedAt: String
    var appId: String
    var appName: String
    var documentName: String
    var sourceUrl: String
    var quote: String
    var cleanText: String?
    var axText: String?
    var ocrText: String?
    var noiseRemoved: Int?
}
struct MeetingEvidence: Decodable {
    var id: String
    var title: String
    var start: Double
    var source: String
    var text: String
}
struct RecallAnswer: Decodable {
    var meetingEvidence: [MeetingEvidence]?
    var answer: String
    var found: Bool
    var sources: [RecallSource]
}
struct RecallTopics: Decodable { var topics: [RecallTopic] }
struct RecallThread: Decodable {
    var sources: [RecallSource]
    var total: Int
    var nextOffset: Int?
}

@MainActor final class RecallModel: ObservableObject {
    @Published var question = ""
    @Published var answer: RecallAnswer?
    @Published var topics: [RecallTopic] = []
    @Published var selectedTopic: RecallTopic?
    @Published var thread: [RecallSource] = []
    @Published var nextOffset: Int?
    @Published var total = 0
    @Published var loading = false
    @Published var error: String?
    @Published var todayOnly = false
    @Published var appID = ""
    private var generation = 0
    var day: String {
        guard todayOnly else { return "" }
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM-dd"
        return format.string(from: Date())
    }
    func queryPath(_ path: String, _ items: [URLQueryItem]) -> String {
        var parts = URLComponents(); parts.path = path; parts.queryItems = items.filter { $0.value != "" }
        return parts.string ?? path
    }
    func read<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await WatchModel.shared.request(path)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
    func ask(_ suggested: String? = nil) async {
        if let suggested { question = suggested }
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        generation += 1; let current = generation
        loading = true; error = nil; answer = nil
        do {
            let body = try JSONSerialization.data(withJSONObject: ["question": question, "day": day, "app_id": appID])
            let data = try await WatchModel.shared.request("/api/ask", method: "POST", body: body)
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(RecallAnswer.self, from: data)
            guard current == generation else { return }
            answer = result
        } catch { if current == generation { self.error = "Couldn’t search your captures. \(error.localizedDescription)" } }
        if current == generation { loading = false }
    }
    func loadTopics() async {
        do { topics = try await read(queryPath("/api/topics", [.init(name: "day", value: day)]), as: RecallTopics.self).topics }
        catch { self.error = "Couldn’t load topics. \(error.localizedDescription)" }
    }
    func select(_ topic: RecallTopic, append: Bool = false) async {
        generation += 1; let current = generation
        selectedTopic = topic; loading = true; error = nil
        if !append { thread = []; nextOffset = nil }
        do {
            let path = queryPath("/api/topics/" + topic.key, [.init(name: "day", value: day), .init(name: "offset", value: String(append ? nextOffset ?? 0 : 0))])
            let result = try await read(path, as: RecallThread.self)
            guard current == generation else { return }
            thread += result.sources; nextOffset = result.nextOffset; total = result.total
        } catch { if current == generation { self.error = "Couldn’t load this topic. \(error.localizedDescription)" } }
        if current == generation { loading = false }
    }
    func changedFilters() async {
        generation += 1; loading = false; answer = nil; selectedTopic = nil; thread = []; error = nil
        await loadTopics()
    }
}

struct RecallWorkspace: View {
    @EnvironmentObject var model: WatchModel
    @StateObject private var recall = RecallModel()
    var showTopics: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(showTopics ? "A THREAD ACROSS YOUR APPS" : "A LITTLE LESS LOST CONTEXT").font(.system(size: 10)).tracking(2).foregroundStyle(Ink.ash)
                    Text(showTopics ? "Pick up a thread." : "What were you looking for?").font(.system(size: 34, weight: .medium)).tracking(-0.6)
                    Text(showTopics ? "Related moments, brought together by project name or document title." : "Find a detail you saw, a decision you discussed, or where you left off.")
                        .font(.system(size: 14)).foregroundStyle(Ink.ash).lineSpacing(4)
                }.padding(.top, 28)
                HStack {
                    Toggle("Today only", isOn: $recall.todayOnly).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    if !showTopics {
                        Picker("Look in", selection: $recall.appID) {
                            Text("All apps").tag("")
                            ForEach(model.apps) { app in Text(app.appName).tag(app.appId) }
                        }.frame(maxWidth: 260)
                    }
                }.font(.caption).foregroundStyle(Ink.ash)
                if !showTopics { questionBox }
                if let error = recall.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Ink.ash)
                }
                if recall.loading { ProgressView("Finding the captured details…").font(.caption) }
                if showTopics {
                    if let topic = recall.selectedTopic {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(topic.label).font(.title2)
                                Text("\(recall.total) captured moments · Earliest first").font(.caption).foregroundStyle(Ink.ash)
                            }
                            Spacer()
                            Button("All topics") { recall.selectedTopic = nil; recall.thread = [] }.buttonStyle(QuietButton())
                        }
                        ForEach(recall.thread) { source in RecallSourceCard(source: source) }
                        if recall.nextOffset != nil {
                            Button("More moments") { Task { await recall.select(topic, append: true) } }.buttonStyle(QuietButton()).disabled(recall.loading)
                        }
                    } else { topicList }
                } else if let answer = recall.answer {
                    if !answer.sources.isEmpty {
                        HStack {
                            Text("FROM YOUR CAPTURED TEXT").tracking(1.5)
                            Spacer()
                            Text("\(answer.sources.count) sources")
                        }.font(.system(size: 10)).foregroundStyle(Ink.ash)
                        ForEach(answer.sources) { source in RecallSourceCard(source: source) }
                        Text("These are source excerpts, not confirmation that a task was completed. Open the captured text to check the full context.")
                            .font(.caption).foregroundStyle(Ink.ash).lineSpacing(4)
                    } else if (answer.meetingEvidence ?? []).isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No supporting capture found.").font(.title3)
                            Text(answer.answer).font(.callout).foregroundStyle(Ink.ash)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Ink.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(Array((answer.meetingEvidence ?? []).enumerated()), id: \.offset) { _, meeting in
                        VStack(alignment: .leading, spacing: 12) {
                            Label("MEETING TRANSCRIPT", systemImage: "waveform").font(.caption).foregroundStyle(Ink.ash)
                            Text(meeting.title).font(.headline)
                            Text(meeting.text).font(.callout).textSelection(.enabled)
                            Button("Open transcript · \(Int(meeting.start) / 60):\(String(format: "%02d", Int(meeting.start) % 60)) · \(meeting.source)") {
                                model.meetingSelection = meeting.id
                                model.meetingsPresented = true
                            }.buttonStyle(QuietButton())
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Ink.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                } else if !recall.loading {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("TRY ASKING").font(.system(size: 10)).tracking(1.5).foregroundStyle(Ink.ash)
                        ForEach(["What did I work on today?", "Where did I leave off with Atlas?", "Find decisions I saw"], id: \.self) { suggestion in
                            Button { Task { await recall.ask(suggestion) } } label: {
                                HStack { Text(suggestion); Spacer(); Image(systemName: "arrow.up.left") }
                                    .font(.system(size: 14)).padding(18).background(Ink.card, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("Search uses text saved on this Mac. Results include the original app, time, and a source link when the app provides one.")
                        .font(.caption).foregroundStyle(Ink.ash).lineSpacing(4)
                }
            }.padding(.horizontal, 36).padding(.bottom, 36).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
        .task { await recall.loadTopics() }
        .onChange(of: recall.todayOnly) { _, _ in Task { await recall.changedFilters() } }
        .onChange(of: recall.appID) { _, _ in Task { await recall.changedFilters() } }
    }
    private var questionBox: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass").foregroundStyle(Ink.ash)
            TextField("Ask about something you saw or worked on…", text: $recall.question, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 16)).lineLimit(1...4)
                .onSubmit { Task { await recall.ask() } }.disabled(recall.loading)
                .accessibilityLabel("Ask your day question")
            Button { Task { await recall.ask() } } label: { Image(systemName: "arrow.up").font(.system(size: 16, weight: .medium)).padding(12) }
                .buttonStyle(.plain).foregroundStyle(.white).background(accent, in: Circle())
                .accessibilityLabel("Find captured answers").disabled(recall.loading || recall.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(18).background(Ink.canvas, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Ink.ash.opacity(0.24), lineWidth: 1))
    }
    private var topicList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Suggested groups · Matching names may refer to different projects.").font(.caption).foregroundStyle(Ink.ash)
            if recall.topics.isEmpty {
                Text("Topics will appear when a capture includes a project name or a recognizable document title.").font(.callout).padding(24)
            }
            ForEach(recall.topics) { topic in
                Button { Task { await recall.select(topic) } } label: {
                    HStack(spacing: 18) {
                        Image(systemName: "square.stack.3d.up").font(.title2).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(topic.label).font(.system(size: 18, weight: .medium))
                            Text(topic.apps).font(.caption).foregroundStyle(Ink.ash).lineLimit(2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 7) {
                            Text("\(topic.appCount) \(topic.appCount == 1 ? "app" : "apps")").font(.callout)
                            Text("\(topic.captures) moments").font(.caption).foregroundStyle(Ink.ash)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.ash)
                    }.padding(22).background(Ink.card, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }
    }
}

struct RecallSourceCard: View {
    @EnvironmentObject var model: WatchModel
    var source: RecallSource
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                AppIcon(bundleId: source.appId, size: 22)
                Text(source.appName).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(String(source.capturedAt.prefix(19)).replacingOccurrences(of: "T", with: " · "))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.ash)
            }
            if !source.documentName.isEmpty { Text(source.documentName).font(.system(size: 17, weight: .medium)).lineLimit(3) }
            HStack(alignment: .top, spacing: 14) {
                Rectangle().fill(accent.opacity(0.45)).frame(width: 2)
                Text(source.quote).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("View captured text · #\(source.id)") { model.evidenceID = source.id }.buttonStyle(.plain).foregroundStyle(accent).font(.caption)
                Spacer()
                RecallSourceLink(source: source.sourceUrl)
            }
        }.padding(24).background(Ink.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct RecallSourceLink: View {
    var source: String
    @State private var failed = false
    private var url: URL? {
        guard let url = URL(string: source), ["https", "http", "file"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        if url.isFileURL {
            guard ["txt", "md", "pdf", "rtf", "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx", "pages", "numbers", "key", "html"].contains(url.pathExtension.lowercased()), url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
        } else if url.host == nil { return nil }
        return url
    }
    var body: some View {
        Group {
            if let url {
                Button {
                    if url.isFileURL {
                        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        else { failed = true }
                    } else if !NSWorkspace.shared.open(url) { failed = true }
                } label: { Label(url.isFileURL ? "Reveal document" : "Open source", systemImage: "arrow.up.right") }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(accent).help(source)
            } else { Text("Original link unavailable").font(.system(size: 10)).foregroundStyle(Ink.ash) }
        }.alert("Source couldn’t be opened", isPresented: $failed) { Button("OK", role: .cancel) {} } message: { Text("The original file may have moved, or its app may no longer be available. Your captured text is still here.") }
    }
}

struct RecallEvidenceView: View {
    @EnvironmentObject var model: WatchModel
    @Environment(\.dismiss) private var dismiss
    @State private var source: RecallSource?
    @State private var error: String?
    var observationID: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Captured evidence · #\(observationID)").font(.title2)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(QuietButton()).keyboardShortcut(.cancelAction)
            }
            if let source {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(source.documentName).font(.headline)
                        Text("\(source.appName) · \(source.capturedAt)").font(.caption).foregroundStyle(Ink.ash)
                    }
                    Spacer(); RecallSourceLink(source: source.sourceUrl)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("This is what was visible at that moment. It does not confirm that anything was sent, saved, or completed.").font(.caption).foregroundStyle(Ink.ash)
                        evidenceSection("Readable text", source.cleanText ?? source.quote)
                        DisclosureGroup("Accessibility text") { evidenceSection("", source.axText ?? "") }
                        DisclosureGroup("OCR text") { evidenceSection("", source.ocrText ?? "") }
                        if let count = source.noiseRemoved { Text("\(count) duplicate or interface lines removed from readable text. Original captured text is preserved above.").font(.caption).foregroundStyle(Ink.ash) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let error { Text(error).foregroundStyle(Ink.ash) }
            else { ProgressView("Loading captured text…") }
        }.padding(30).frame(width: 740, height: 570).background(Ink.canvas).foregroundStyle(Ink.ivory)
            .task(id: observationID) {
                do {
                    let data = try await model.request("/api/evidence/\(observationID)")
                    let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
                    source = try decoder.decode(RecallSource.self, from: data)
                } catch { self.error = "This capture couldn’t be loaded. It may have expired under your retention setting. \(error.localizedDescription)" }
            }
    }
    private func evidenceSection(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !heading.isEmpty { Text(heading).font(.headline) }
            Text(text.isEmpty ? "No text available." : text).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).background(Ink.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
