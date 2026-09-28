import SwiftUI
import AppKit
import AVFoundation

private let guideBlue = Color(red: 0.08, green: 0.43, blue: 0.97)

@MainActor final class OnboardingMusic: ObservableObject {
    private var player: AVAudioPlayer?
    @Published var unavailable = false
    func play() {
        guard player?.isPlaying != true else { return }
        do {
            if player == nil {
                guard let url = Bundle.main.url(forResource: "OnboardingAmbience", withExtension: "wav") else { unavailable = true; return }
                player = try AVAudioPlayer(contentsOf: url)
                player?.numberOfLoops = -1
                player?.prepareToPlay()
            }
            player?.volume = 0
            unavailable = player?.play() != true
            player?.setVolume(0.22, fadeDuration: 3)
        } catch { unavailable = true }
    }
    func stop() { player?.stop() }
}

struct SetupIllustration: View {
    @EnvironmentObject var model: WatchModel
    let step: Int
    @Binding var permission: String
    var body: some View {
        VStack(spacing: 22) {
            switch step {
            case 1: permissionGuide
            case 2: localModel
            default: exampleJournal
            }
        }.frame(maxWidth: .infinity)
    }
    private var permissionGuide: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                guideTab("Accessibility", kind: "accessibility")
                guideTab("Screen Recording", kind: "screen")
                Spacer(minLength: 0)
            }.padding(.bottom, 17)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 17) {
                        trafficLights.padding(.bottom, 8)
                        HStack(spacing: 4) { Image(systemName: "magnifyingglass"); Text("Search") }.font(.system(size: 8)).foregroundStyle(Ink.ash.opacity(0.5)).padding(6).frame(maxWidth: .infinity, alignment: .leading).background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
                        sidebarItem("bell.fill", "Notifications", .red)
                        sidebarItem("speaker.wave.2.fill", "Sound", .pink)
                        sidebarItem("moon.fill", "Focus", .purple)
                        sidebarItem("hourglass", "Screen Time", .indigo)
                        sidebarItem("gear", "General", .gray)
                        sidebarItem("hand.raised.fill", "Privacy & Security", guideBlue, active: true)
                        sidebarItem("person.crop.circle", "Accessibility", .blue)
                        Spacer(minLength: 0)
                    }.padding(10).frame(width: 118).background(Color(red: 0.96, green: 0.96, blue: 0.97))
                    VStack(alignment: .leading, spacing: 17) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left").foregroundStyle(Ink.ash)
                            Text(permission == "screen" ? "Screen Recording" : "Accessibility").fontWeight(.medium)
                        }.font(.system(size: 10)).padding(.bottom, 8)
                        Text(permission == "screen" ? "Allow apps to read what’s on your screen." : "Allow apps to read accessible text.").font(.system(size: 9)).foregroundStyle(Ink.ash).lineSpacing(3)
                        VStack(spacing: 0) {
                            placeholderRow
                            Divider().opacity(0.5)
                            HStack(spacing: 8) {
                                ConstantMark().frame(width: 24, height: 24)
                                Text("Constant Watch").font(.system(size: 10, weight: .medium))
                                Spacer(minLength: 0)
                                Capsule().fill(granted ? guideBlue : Color.gray.opacity(0.2)).frame(width: 25, height: 14)
                                    .overlay(alignment: granted ? .trailing : .leading) { Circle().fill(.white).frame(width: 10, height: 10).padding(2) }
                            }.padding(.vertical, 13)
                            Divider().opacity(0.5)
                            placeholderRow
                        }.padding(.horizontal, 10).background(guideBlue.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(guideBlue.opacity(0.28), lineWidth: 1))
                        Spacer(minLength: 0)
                        HStack { Image(systemName: "plus"); Image(systemName: "minus"); Spacer(); Image(systemName: "questionmark.circle") }.font(.system(size: 10)).foregroundStyle(Ink.ash.opacity(0.5))
                    }.padding(15).frame(maxWidth: .infinity)
                }.frame(height: 290)
            }.background(.white, in: RoundedRectangle(cornerRadius: 15))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.black.opacity(0.06)))
                .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
                .accessibilityElement(children: .ignore).accessibilityLabel("Illustrated System Settings guide for \(permission == "screen" ? "Screen Recording" : "Accessibility"). Constant Watch is \(granted ? "enabled" : "not enabled").")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "arrow.up.circle.fill").foregroundStyle(guideBlue).font(.system(size: 16))
                    Text(granted ? "Permission connected. You’re ready to continue." : "Drag the app into the System Settings list, then turn its switch on.").font(.system(size: 10)).lineSpacing(3)
                }
                HStack(spacing: 9) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 24, height: 24)
                    Text("Constant Watch").font(.system(size: 11))
                    Spacer()
                    Image(systemName: "hand.draw").font(.system(size: 11)).foregroundStyle(Ink.ash)
                    Text("Drag me").font(.system(size: 9)).foregroundStyle(Ink.ash)
                }.padding(10).background(Ink.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                    .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .accessibilityLabel("Drag the installed Constant Watch app into System Settings")
            }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.12), radius: 15, y: 9)
                .padding(.horizontal, 22).offset(y: -13)
            Button("Open System Settings ↗") { model.openPrivacy(permission == "screen" ? "Privacy_ScreenCapture" : "Privacy_Accessibility") }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(guideBlue).padding(.top, 5)
            Text("SETUP GUIDE").font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(Ink.ash.opacity(0.6)).padding(.top, 12)
        }
    }
    private var granted: Bool { permission == "screen" ? model.status?.permissions.screenRecording == true : model.status?.permissions.accessibility == true }
    private func guideTab(_ title: String, kind: String) -> some View {
        Button { permission = kind } label: {
            VStack(spacing: 7) {
                Text(title).font(.system(size: 10, weight: permission == kind ? .medium : .regular)).foregroundStyle(permission == kind ? guideBlue : Ink.ash)
                Capsule().fill(permission == kind ? guideBlue : .clear).frame(height: 2)
            }
        }.buttonStyle(.plain)
    }
    private var trafficLights: some View {
        HStack(spacing: 5) { ForEach([Color(red: 1, green: 0.48, blue: 0.4), Color(red: 1, green: 0.79, blue: 0.35), Color(red: 0.38, green: 0.77, blue: 0.4)], id: \.self) { Circle().fill($0).frame(width: 7, height: 7) } }.accessibilityHidden(true)
    }
    private func sidebarItem(_ icon: String, _ title: String, _ color: Color, active: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 8)).foregroundStyle(active ? .white : color.opacity(0.4))
            Text(title).font(.system(size: 7)).foregroundStyle(active ? .white : Ink.ash.opacity(0.32))
        }.padding(.vertical, 5).padding(.horizontal, 4).frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? guideBlue : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
    private var placeholderRow: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.06)).frame(width: 17, height: 17)
            Capsule().fill(Color.black.opacity(0.06)).frame(width: 53, height: 6)
            Spacer()
            Capsule().fill(Color.black.opacity(0.055)).frame(width: 25, height: 14)
                .overlay(alignment: .leading) { Circle().fill(.white).frame(width: 10, height: 10).padding(2) }
        }.padding(.vertical, 12)
    }
    private var localModel: some View {
        VStack(spacing: 25) {
            ZStack {
                Circle().fill(guideBlue.opacity(0.025)).frame(width: 280, height: 280)
                Circle().stroke(guideBlue.opacity(0.08), lineWidth: 1).frame(width: 222, height: 222)
                RoundedRectangle(cornerRadius: 30).fill(LinearGradient(colors: [.white, Color(red: 0.9, green: 0.95, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 143, height: 143)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(guideBlue.opacity(0.14)))
                    .shadow(color: guideBlue.opacity(0.1), radius: 24, y: 12)
                VStack(spacing: 12) { Image(systemName: "cpu").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(guideBlue); Text("Qwen").font(.system(size: 16, weight: .medium)) }
            }
            HStack(spacing: 21) { pipeline("text.viewfinder", "Screen text"); Image(systemName: "arrow.right").foregroundStyle(Ink.control); pipeline("cpu", "Local model"); Image(systemName: "arrow.right").foregroundStyle(Ink.control); pipeline("doc.text", "Your journal") }.font(.system(size: 12))
            Text("A little intelligence. All yours.").font(.system(size: 12)).foregroundStyle(Ink.ash)
        }
    }
    private func pipeline(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 9) { Image(systemName: icon).font(.system(size: 20, weight: .light)).foregroundStyle(guideBlue); Text(label).font(.system(size: 9)).foregroundStyle(Ink.ash) }
    }
    private var exampleJournal: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 21) {
                HStack { trafficLights; Spacer(); Image(systemName: "sidebar.left").foregroundStyle(Ink.ash.opacity(0.4)).font(.system(size: 12)) }
                HStack { Text("Your day, in one thread.").font(.system(size: 20, weight: .medium)).tracking(-0.5); Spacer() }.padding(.top, 12)
                HStack(spacing: 7) { Image(systemName: "magnifyingglass"); Text(step == 3 ? "Atlas" : "Find a moment…") }.font(.system(size: 11)).foregroundStyle(Ink.ash).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Ink.card, in: RoundedRectangle(cornerRadius: 9))
                exampleMoment("09:41", "Safari", "A little research", "Ideas and references for the next prototype.", "safari", .blue)
                exampleMoment("10:02", "TextEdit", "Project Atlas", "Launch review · Friday at 10 AM", "doc.text", .gray)
                exampleMoment("10:24", "Your journal", "The thread stays with you.", "Find the detail. Pick up where you left off.", "circle.hexagongrid", guideBlue)
            }.padding(25).background(.white, in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.black.opacity(0.06)))
                .shadow(color: .black.opacity(0.055), radius: 25, y: 12)
            Text("EXAMPLE DAY · YOUR OWN MOMENTS WILL APPEAR HERE").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(Ink.ash.opacity(0.7))
        }
    }
    private func exampleMoment(_ time: String, _ app: String, _ title: String, _ detail: String, _ icon: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 11) { Image(systemName: icon).font(.system(size: 17, weight: .light)).foregroundStyle(color); Rectangle().fill(Ink.control).frame(width: 1, height: 32) }.frame(width: 21)
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text(app).font(.system(size: 10)).foregroundStyle(Ink.ash); Spacer(); Text(time).font(.system(size: 9, design: .monospaced)).foregroundStyle(Ink.ash.opacity(0.65)) }
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Ink.ash).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
