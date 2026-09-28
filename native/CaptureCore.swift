import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

enum CaptureCore {
    @MainActor static func run(_ command: String, excluded: Set<String> = []) async -> [String: Any] {
        let args = [command]
        if args.contains("permissions") || args.contains("request-accessibility") {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if args.contains("permissions") || args.contains("request-screen") { _ = CGRequestScreenCaptureAccess() }
        let axAllowed = AXIsProcessTrusted()
        let screenAllowed = CGPreflightScreenCaptureAccess()
        var result: [String: Any] = ["accessibility": axAllowed, "screen_recording": screenAllowed]
        if args.contains("status") || args.contains("permissions") || args.contains("request-accessibility") || args.contains("request-screen") { return result }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if session?["CGSSessionScreenIsLocked"] as? Bool == true || session?["kCGSessionOnConsoleKey"] as? Bool == false {
            result["skipped"] = "Screen is locked"; return result
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            result["skipped"] = "No foreground application"; return result
        }
        let bundle = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
        result["app_id"] = bundle
        result["app_name"] = app.localizedName ?? bundle
        if excluded.contains(bundle) { result["skipped"] = "Excluded application"; return result }
        var lines: [String] = []
        var secure = false
        var title = ""
        var sourceURL = ""
        var nodes = 0
        let started = Date()
        if axAllowed {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.3)
            func walk(_ element: AXUIElement, _ depth: Int) {
                guard depth < 18, nodes < 650, Date().timeIntervalSince(started) < 2 else { return }
                nodes += 1
                let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
                if subrole == "AXSecureTextField" { secure = true; return }
                // A web-area URL identifies the page. Child link URLs do not.
                if sourceURL.isEmpty, attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                    if let url = attribute(element, "AXURL") as? URL { sourceURL = url.absoluteString }
                    else if let value = attribute(element, "AXURL") as? String { sourceURL = value }
                }
                for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                    if let text = attribute(element, key) as? String, !text.isEmpty { lines.append(String(text.prefix(4000))) }
                }
                if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                    for child in children { walk(child, depth + 1) }
                }
            }
            if let focused = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = focused as! AXUIElement
                if attribute(element, kAXSubroleAttribute) as? String == "AXSecureTextField" { secure = true }
            }
            if let value = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let window = value as! AXUIElement
                title = attribute(window, kAXTitleAttribute) as? String ?? ""
                if let url = attribute(window, kAXDocumentAttribute) as? URL { sourceURL = url.absoluteString }
                else if let value = attribute(window, kAXDocumentAttribute) as? String { sourceURL = value }
                walk(window, 0)
            }
        }
        if secure { result["skipped"] = "Secure text field visible"; return result }
        result["window_title"] = title
        result["source_url"] = sourceURL
        result["ax_text"] = lines.joined(separator: "\n")
        var ocr: [String] = []
        var warnings: [String] = []
        if !axAllowed { warnings.append("Accessibility permission missing") }
        if !screenAllowed { warnings.append("Screen Recording permission missing") }
        if screenAllowed {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let candidates = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 50 && $0.frame.height > 50 }
                // CGWindowList is front-to-back. Use the actual foreground window, not an arbitrary SC window.
                let ordered = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let ids = ordered.compactMap { $0[kCGWindowNumber as String] as? UInt32 }
                let window = candidates.first(where: { !$0.title.isNilOrEmpty && $0.title == title }) ?? ids.compactMap { id in candidates.first { $0.windowID == id } }.first
                if let window {
                    if title.isEmpty { result["window_title"] = window.title ?? "" }
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let config = SCStreamConfiguration()
                    config.width = Int(window.frame.width * 2)
                    config.height = Int(window.frame.height * 2)
                    config.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    ocr = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                } else { warnings.append("No capturable foreground window") }
            } catch { warnings.append("OCR: \(error.localizedDescription)") }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            return ["skipped": "Foreground application changed during capture"]
        }
        result["ocr_text"] = ocr.joined(separator: "\n")
        result["warnings"] = warnings
        return result
    }
}

extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
