import Foundation

@main
struct Capture {
    @MainActor static func main() async {
        let excluded = Set((ProcessInfo.processInfo.environment["CW_EXCLUDED_APPS"] ?? "").split(separator: "\n").map(String.init))
        let result = await CaptureCore.run(CommandLine.arguments.dropFirst().first ?? "capture", excluded: excluded)
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
    }
}
