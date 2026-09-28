import SwiftUI
import AppKit

struct ReviewDay: Decodable, Identifiable {
    var day: String
    var captures: Int
    var id: String { day }
}
struct ReviewApp: Decodable, Identifiable {
    var appId: String
    var appName: String
    var captures: Int
    var id: String { appId }
}
struct ReviewHighlight: Decodable, Identifiable {
    var id: Int
    var title: String
    var basis: String
    var captures: Int
    var apps: [String]
    var sources: [RecallSource]
}
struct ReviewReport: Decodable {
    var captures: Int
    var appCount: Int
    var daysWithCaptures: Int
    var totalGroups: Int
    var days: [ReviewDay]
    var apps: [ReviewApp]
    var highlights: [ReviewHighlight]
    var draft: String
}

struct ReviewWorkspace: View {
    @EnvironmentObject var model: WatchModel
    @State private var date = Date()
    @State private var week = false
    @State private var report: ReviewReport?
    @State private var error: String?
    @State private var loading = false
    @State private var draft = ""
    @State private var editing = false
    @State private var copied = false
    @State private var refresh = 0
    private func day(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    private var start: Date { week ? Calendar.current.dateInterval(of: .weekOfYear, for: date)!.start : date }
    private var end: Date { week ? Calendar.current.date(byAdding: .day, value: 6, to: start)! : date }
    private var range: String { "start=\(day(start))&end=\(day(end))" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MAKE SENSE OF YOUR TIME").font(.system(size: 10)).tracking(2).foregroundStyle(Ink.ash)
                        Text(week ? "The week, gathered." : "A day worth remembering.").font(.system(size: 32, weight: .medium)).tracking(-0.7)
                        Text("Your context. Its sources. A place to pick up tomorrow.").font(.callout).foregroundStyle(Ink.ash)
                    }
                    Spacer()
                    Button { refresh += 1 } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(QuietButton()).accessibilityLabel("Refresh review").disabled(loading)
                }
                HStack {
                    Picker("Review period", selection: $week) { Text("Day").tag(false); Text("Week").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 155)
                    if let report, report.captures > 0 {
                        Button("Prepare update") { draft = report.draft; copied = false; editing = true }.buttonStyle(QuietButton())
                    }
                    Spacer()
                    DatePicker("Review date", selection: $date, displayedComponents: .date).labelsHidden()
                }
                if week { Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Ink.ash) }
                if loading { ProgressView("Gathering your context…").frame(maxWidth: .infinity).padding(40) }
                else if let error {
                    Text(error).foregroundStyle(Ink.ash)
                    Button("Try again") { refresh += 1 }.buttonStyle(QuietButton())
                } else if let report {
                    if report.captures == 0 {
                        VStack(spacing: 16) {
                            Image(systemName: "sun.horizon").font(.system(size: 38, weight: .ultraLight))
                            Text("Room for the day to unfold.").font(.title2)
                            Text("No captures for this period. Choose another date, or keep working with capture enabled.").font(.callout).foregroundStyle(Ink.ash).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(48).background(Ink.card, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        overview(report)
                        HStack {
                            Text("THREADS TO REVISIT").font(.system(size: 10)).tracking(1.8).foregroundStyle(Ink.ash)
                            Spacer()
                            Text("\(report.highlights.count) of \(report.totalGroups) · Most captured first").font(.caption).foregroundStyle(Ink.ash)
                        }
                        ForEach(report.highlights) { highlight in
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(highlight.title).font(.system(size: 20, weight: .medium)).lineLimit(2)
                                        Text(highlight.apps.joined(separator: " · ")).font(.caption).foregroundStyle(Ink.ash)
                                    }
                                    Spacer()
                                    Text("\(highlight.captures) captures").font(.caption).foregroundStyle(Ink.ash)
                                }
                                ForEach(highlight.sources) { source in
                                    Button { model.evidenceID = source.id } label: {
                                        HStack(alignment: .top, spacing: 12) {
                                            Rectangle().fill(accent.opacity(0.4)).frame(width: 2)
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(source.quote).font(.system(size: 13)).lineSpacing(4).lineLimit(4).multilineTextAlignment(.leading)
                                                Text("\(source.appName) · Source #\(source.id) ↗").font(.system(size: 10)).foregroundStyle(accent)
                                            }
                                            Spacer(minLength: 0)
                                        }.fixedSize(horizontal: false, vertical: true)
                                    }.buttonStyle(.plain).accessibilityLabel("Open source \(source.id): \(source.documentName)")
                                }
                                Text(highlight.basis).font(.system(size: 10)).foregroundStyle(Ink.ash)
                            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Ink.card, in: RoundedRectangle(cornerRadius: 16))
                        }
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Leave with a useful update.").font(.system(size: 20, weight: .medium))
                                Text("Review the sources, add outcomes and priorities, then copy a Markdown draft.").font(.callout).foregroundStyle(Ink.ash)
                            }
                            Spacer()
                            Button("Prepare update ↗") { draft = report.draft; copied = false; editing = true }.buttonStyle(QuietButton(primary: true))
                        }.padding(.vertical, 16)
                    }
                }
            }.padding(32)
        }
        .task(id: range + "&refresh=\(refresh)") {
            loading = true; error = nil; report = nil
            do {
                let value = try await model.decoded(ReviewReport.self, path: "/api/review?\(range)")
                guard !Task.isCancelled else { return }; report = value; loading = false
            } catch { if !Task.isCancelled { self.error = "Couldn’t load this review. \(error.localizedDescription)"; loading = false } }
        }
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Your update, in your words.").font(.title2); Spacer(); Button("Done") { editing = false } }
                Text("Edit before sharing. This draft stays here until you copy it; edits are not saved after closing this workspace.").font(.caption).foregroundStyle(Ink.ash)
                TextEditor(text: $draft).font(.system(size: 13, design: .monospaced)).padding(12).background(Ink.card).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text("Source links open in Constant Watch on this Mac.").font(.caption).foregroundStyle(Ink.ash)
                    Spacer()
                    Button(copied ? "Copied ✓" : "Copy Markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft, forType: .string); copied = true }.buttonStyle(QuietButton(primary: true))
                }
            }.padding(28).frame(width: 700, height: 550).onChange(of: draft) { copied = false }
        }
    }
    private func overview(_ report: ReviewReport) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 36) {
                metric("\(report.captures)", "captured moments")
                metric("\(report.appCount)", "applications")
                if week { metric("\(report.daysWithCaptures)", "days with context") }
            }
            if week {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(report.days) { item in
                        VStack(spacing: 8) {
                            Text("\(item.captures)").font(.system(size: 10)).foregroundStyle(Ink.ash)
                            RoundedRectangle(cornerRadius: 4).fill(item.captures > 0 ? accent.opacity(0.65) : Ink.control).frame(height: max(3, 60 * Double(item.captures) / Double(max(1, report.days.map(\.captures).max() ?? 1))))
                            Text(String(item.day.suffix(5))).font(.system(size: 10)).foregroundStyle(Ink.ash)
                        }.frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel("\(item.day), \(item.captures) captures")
                    }
                }
            }
            ForEach(report.apps.prefix(5)) { app in
                HStack(spacing: 12) {
                    AppIcon(bundleId: app.appId, size: 18)
                    Text(app.appName).font(.caption).frame(width: 110, alignment: .leading).lineLimit(1)
                    GeometryReader { geometry in
                        Capsule().fill(Ink.control)
                        Capsule().fill(accent.opacity(0.45)).frame(width: max(3, geometry.size.width * Double(app.captures) / Double(max(1, report.captures))))
                    }.frame(height: 5)
                    Text("\(app.captures)").font(.system(size: 11, design: .monospaced)).frame(width: 40, alignment: .trailing)
                }
            }
            Text("Capture counts show available context, not hours worked or productivity. Highlights quote visible text; they don’t confirm completed actions.").font(.system(size: 11)).foregroundStyle(Ink.ash).lineSpacing(3)
        }.padding(24).background(Ink.card, in: RoundedRectangle(cornerRadius: 16))
    }
    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 32, weight: .medium, design: .rounded)); Text(label).font(.caption).foregroundStyle(Ink.ash) }
    }
}
