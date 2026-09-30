import SwiftUI
import WebKit
import AppKit

struct MeetingState: Decodable {
    struct Session: Decodable { let id: String; let title: String; let startedAt: String }
    struct Candidate: Decodable { let title: String; let appName: String }
    let active: Session?
    let candidate: Candidate?
}

struct MeetingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Meetings").font(.headline); Spacer(); Button("Done") { dismiss() } }
                .padding(.horizontal, 24).padding(.vertical, 12)
            MeetingWebView()
        }.frame(minWidth: 920, minHeight: 670).background(.white)
    }
}

struct MeetingWebView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "copyMarkdown")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        let selection = WatchModel.shared.meetingSelection.map { "&meeting=" + $0 } ?? ""
        WatchModel.shared.meetingSelection = nil
        view.load(URLRequest(url: URL(string: "http://127.0.0.1:8765/meetings?embedded=1" + selection)!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "copyMarkdown")
    }
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.securityOrigin.host == "127.0.0.1", message.frameInfo.securityOrigin.port == 8765,
                  let text = message.body as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "constantwatch", url.host == "observation", let id = Int(url.lastPathComponent) {
                WatchModel.shared.meetingsPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { WatchModel.shared.evidenceID = id }
                decisionHandler(.cancel)
            } else {
                decisionHandler(url.scheme == "http" && url.host == "127.0.0.1" && url.port == 8765 ? .allow : .cancel)
            }
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = "Delete meeting?"
            alert.informativeText = message
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard let window = webView.window else { completionHandler(false); return }
            alert.beginSheetModal(for: window) { response in completionHandler(response == .alertFirstButtonReturn) }
        }
    }
}
