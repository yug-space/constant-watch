import Foundation
import AVFoundation
import ScreenCaptureKit
import AppKit

// Audio never leaves the local meeting directory. No screen frames are retained.
final class MeetingRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let shared = MeetingRecorder()
    private let queue = DispatchQueue(label: "local.constantwatch.meeting-audio")
    private var stream: SCStream?
    private var engine: AVAudioEngine?
    private var files: [String: AVAudioFile] = [:]
    private var tracks: [[String: Any]] = []
    private var folder: URL?
    private var startTime = ProcessInfo.processInfo.systemUptime
    private var heartbeat = Date()
    private var timer: Timer?
    private var recording = false
    private var failure = ""
    private var tapped = false

    @MainActor
    func command(_ command: String, payload: [String: Any]) async -> [String: Any] {
        do {
            switch command {
            case "meeting-permission":
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    // Do not block the command queue while macOS displays its permission prompt.
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                } else if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
                return ["requested": true]
            case "meeting-start":
                guard let id = payload["meeting_id"] as? String,
                      id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { throw audioError("Invalid meeting ID") }
                guard !recording else { throw audioError("A meeting is already recording.") }
                let microphone = payload["microphone"] as? Bool ?? true
                let systemAudio = payload["system_audio"] as? Bool ?? true
                guard microphone || systemAudio else { throw audioError("Choose an audio source.") }
                if microphone && AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                    throw audioError("Enable microphone access below, then start recording again.")
                }
                if systemAudio && !CGPreflightScreenCaptureAccess() {
                    throw audioError("Enable Screen & System Audio Recording in macOS Settings, then reopen Constant Watch.")
                }
                let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Constant Watch/meetings")
                let destination = root.appendingPathComponent(id)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                queue.sync {
                    folder = destination; tracks = []; files = [:]; failure = ""
                    startTime = ProcessInfo.processInfo.systemUptime
                }
                heartbeat = Date()
                recording = true
                do {
                    if microphone {
                        let audioEngine = AVAudioEngine()
                        engine = audioEngine
                        let input = audioEngine.inputNode
                        let format = input.outputFormat(forBus: 0)
                        guard format.sampleRate > 0 && format.channelCount > 0 else { throw audioError("No microphone is available.") }
                        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                            guard let self else { return }
                            // The tap buffer is borrowed; finish writing before returning it to AVAudioEngine.
                            self.queue.sync { self.write(buffer, name: "microphone", label: "Microphone") }
                        }
                        tapped = true
                        try audioEngine.start()
                    }
                    if systemAudio {
                        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        guard let display = content.displays.first else { throw audioError("No display is available for computer audio.") }
                        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                        let config = SCStreamConfiguration()
                        config.width = 2; config.height = 2
                        config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
                        config.capturesAudio = true
                        config.excludesCurrentProcessAudio = true
                        config.sampleRate = 16000; config.channelCount = 1
                        let capture = SCStream(filter: filter, configuration: config, delegate: self)
                        stream = capture
                        try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                        try await capture.startCapture()
                    }
                    timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                        Task { @MainActor in
                            guard let self, self.recording else { return }
                            // Stop if the service vanishes; recording must never become an orphan.
                            if Date().timeIntervalSince(self.heartbeat) > 25 {
                                self.queue.sync { self.failure = "Recording stopped because the local service disconnected." }
                                _ = await self.stop()
                            }
                        }
                    }
                    return ["recording": true]
                } catch {
                    _ = await stop()
                    throw error
                }
            case "meeting-stop": return await stop()
            case "meeting-status":
                heartbeat = Date()
                return queue.sync { ["recording": recording, "warning": failure] }
            default: throw audioError("Unknown meeting command")
            }
        } catch { return ["error": error.localizedDescription] }
    }

    private func audioError(_ message: String) -> NSError {
        NSError(domain: "ConstantWatch.Meetings", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func write(_ buffer: AVAudioPCMBuffer, name: String, label: String) {
        guard let folder, failure.isEmpty, buffer.frameLength > 0 else { return }
        do {
            if files[name] == nil {
                let file = folder.appendingPathComponent(name + ".wav")
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: Int(buffer.format.channelCount), AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
                files[name] = try AVAudioFile(forWriting: file, settings: settings,
                    commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                tracks.append(["file": name + ".wav", "source": label,
                    "offset": max(0, ProcessInfo.processInfo.systemUptime - startTime - Double(buffer.frameLength) / buffer.format.sampleRate)])
            }
            if let file = files[name], let track = tracks.first(where: { $0["file"] as? String == name + ".wav" }), let offset = track["offset"] as? Double {
                // System streams may deliver no packets during silence. Preserve that gap in
                // the file so transcript timestamps still line up with the screen journal.
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime - offset - Double(buffer.frameLength) / buffer.format.sampleRate
                var gap = Int64(max(0, elapsed) * buffer.format.sampleRate) - file.length
                if gap > Int64(buffer.format.sampleRate * 0.25) {
                    while gap > 0 {
                        let frames = AVAudioFrameCount(min(gap, 4096))
                        if let silence = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) {
                            silence.frameLength = frames
                            for audio in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                                if let data = audio.mData { memset(data, 0, Int(audio.mDataByteSize)) }
                            }
                            try file.write(from: silence)
                        }
                        gap -= Int64(frames)
                    }
                }
            }
            try files[name]?.write(from: buffer)
        } catch { failure = "Audio capture stopped: \(error.localizedDescription)" }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        if status == noErr { write(buffer, name: "system", label: "Computer audio") }
        else { failure = "Computer audio format could not be read. Stop and retry the recording." }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.failure = "Computer audio disconnected: \(error.localizedDescription)" }
    }

    @MainActor
    private func stop() async -> [String: Any] {
        timer?.invalidate(); timer = nil
        if let engine {
            engine.stop()
            if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        }
        engine = nil
        if let stream { try? await stream.stopCapture() }
        stream = nil
        recording = false
        return queue.sync {
            files.removeAll() // Closes WAV files and finalizes their headers before transcription.
            folder = nil
            return ["recording": false, "tracks": tracks, "warning": failure]
        }
    }
}
