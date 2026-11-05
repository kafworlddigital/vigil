#if VIGIL_VOICE_VISION
import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
import CoreAudio
#else
import UIKit
#endif

@MainActor final class VigilVoiceOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = VigilVoiceOutput()
    @Published private(set) var speaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var watchdog: Task<Void, Never>?
    private var utteranceID = UUID()
    private var file: AVAudioFile?
    private var outputURL: URL?
    private var activeText = ""
    private(set) var backend = "idle"
    private(set) var renderedPeak: Float = 0
    private(set) var playerStarted = false
    var isPlaying: Bool { player?.isPlaying == true }
    var playbackTime: TimeInterval { player?.currentTime ?? 0 }
    var playbackPower: Float {
        player?.updateMeters(); return player?.peakPower(forChannel: 0) ?? -160
    }
    #if os(macOS)
    var outputDevice: String { player?.currentDevice ?? "default" }
    #endif
    #if os(macOS)
    private var legacy: NSSpeechSynthesizer?
    private var sayProcess: Process?
    #endif
    var onFinished: (() -> Void)?
    override init() { super.init(); synthesizer.delegate = self }
    var enabled: Bool { UserDefaults.standard.object(forKey: "vigil.voice.spoken") as? Bool ?? true }
    static let voices: [AVSpeechSynthesisVoice] = {
        AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }()
    func speak(_ text: String, entireLine: Bool = false, audition: Bool = false) {
        guard (enabled || audition), !VoiceVisionController.proofMode else { return }
        stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let line = AVSpeechUtterance(string: entireLine ? String(text.prefix(300)) : VoiceVisionPolicy.sentence(text))
        let identifier = UserDefaults.standard.string(forKey: "vigil.voice.identifier") ?? ""
        line.voice = AVSpeechSynthesisVoice(identifier: identifier)
            ?? Self.voices.first(where: { $0.language == "en-GB" })
            ?? Self.voices.first(where: { $0.language.hasPrefix("en") })
            ?? Self.voices.first
        line.volume = VoiceVisionPolicy.volume(UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5)
        line.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        speaking = true
        #if os(macOS)
        guard line.volume > 0 else { finish(); return }
        line.volume = 1 // Apply the user's volume once, at AVAudioPlayer output.
        activeText = line.speechString; renderedPeak = 0; playerStarted = false
        let token = utteranceID
        backend = "AVSpeechSynthesizer → AVAudioPlayer"
        outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("vigil-speech-\(token).caf")
        // Rendering to PCM avoids macOS's occasionally silent direct speech route and
        // lets us verify a non-silent signal before normal background audio playback.
        synthesizer.write(line) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            // AVSpeech owns callback memory; retain a copy before changing queues.
            guard let copy = AVAudioPCMBuffer(pcmFormat: pcm.format, frameCapacity: max(1, pcm.frameLength)) else { return }
            copy.frameLength = pcm.frameLength
            let source = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for index in 0..<min(source.count, destination.count) {
                if let from = source[index].mData, let to = destination[index].mData {
                    memcpy(to, from, Int(source[index].mDataByteSize))
                }
            }
            // Keep callbacks in order, including the final empty buffer.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.utteranceID == token, self.backend.hasPrefix("AVSpeech") else { return }
                if copy.frameLength == 0 { self.playRendered(token); return }
                do {
                    if self.file == nil, let url = self.outputURL { self.file = try AVAudioFile(forWriting: url, settings: copy.format.settings) }
                    if let channels = copy.floatChannelData {
                        for channel in 0..<Int(copy.format.channelCount) {
                            for i in 0..<Int(copy.frameLength) { self.renderedPeak = max(self.renderedPeak, abs(channels[channel][i])) }
                        }
                    }
                    try self.file?.write(from: copy)
                } catch { self.fallback(token) }
            }
        }
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.utteranceID == token, !self.playerStarted else { return }
            self.fallback(token)
        }
        #else
        synthesizer.speak(line)
        #endif
    }
    func stop() {
        utteranceID = UUID(); watchdog?.cancel(); watchdog = nil
        synthesizer.stopSpeaking(at: .immediate); speaking = false
        player?.stop(); player = nil; file = nil
        #if os(macOS)
        legacy?.stopSpeaking(); legacy = nil
        if sayProcess?.isRunning == true { sayProcess?.terminate() }; sayProcess = nil
        #endif
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }; outputURL = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        #if !os(macOS)
        Task { @MainActor in
            self.speaking = false
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            self.onFinished?()
        }
        #endif
    }
    private func finish() { stop(); onFinished?() }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.finish() } }
    }
    #if os(macOS)
    private func playRendered(_ token: UUID) {
        guard token == utteranceID, !playerStarted else { return }
        file = nil
        guard let url = outputURL else { fallback(token); return }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.currentDevice = VigilAudioRoute.snapshot().uid
            audio.isMeteringEnabled = true
            audio.volume = VoiceVisionPolicy.volume(UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5)
            audio.delegate = self; player = audio
            audio.prepareToPlay(); playerStarted = audio.play()
            if playerStarted { watchdog?.cancel() } else { fallback(token) }
        } catch { fallback(token) }
    }
    private func fallback(_ token: UUID) {
        guard token == utteranceID, !playerStarted else { return }
        watchdog?.cancel(); synthesizer.stopSpeaking(at: .immediate); file = nil
        guard backend != "say → AVAudioPlayer" else { finish(); return }
        // Both fallback renderers write a local file, preserving the app volume.
        if backend.hasPrefix("AVSpeech") {
            backend = "NSSpeechSynthesizer → AVAudioPlayer"
            let voice = NSSpeechSynthesizer.availableVoices.first {
                (NSSpeechSynthesizer.attributes(forVoice: $0)[.localeIdentifier] as? String)?.hasPrefix("en_GB") == true
            }
            legacy = NSSpeechSynthesizer(voice: voice)
            legacy?.delegate = self
            if let url = outputURL, legacy?.startSpeaking(activeText, to: url) == true {
                watchdog = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    self?.fallback(token)
                }
                return
            }
        }
        legacy?.stopSpeaking(); legacy = nil; backend = "say → AVAudioPlayer"
        guard let url = outputURL else { finish(); return }
        try? FileManager.default.removeItem(at: url)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", url.path, "--data-format=LEF32@22050", "--", activeText]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.utteranceID == token else { return }
                if process.terminationStatus == 0 { self.playRendered(token) } else { self.finish() }
            }
        }
        sayProcess = process
        do { try process.run() } catch { finish() }
        watchdog = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard let self, self.utteranceID == token, !self.playerStarted else { return }; self.finish()
        }
    }
    #endif
}

#if os(macOS)
extension VigilVoiceOutput: NSSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finished: Bool) {
        Task { @MainActor in
            guard self.legacy === sender, self.backend.hasPrefix("NSSpeech") else { return }
            if finished { self.playRendered(self.utteranceID) } else { self.fallback(self.utteranceID) }
        }
    }
}

@MainActor final class VigilChime {
    static let shared = VigilChime()
    private var player: AVAudioPlayer?
    private(set) var started = false
    var isPlaying: Bool { player?.isPlaying == true }
    var playbackTime: TimeInterval { player?.currentTime ?? 0 }
    var playbackPower: Float { player?.updateMeters(); return player?.peakPower(forChannel: 0) ?? -160 }
    func play() {
        started = false
        guard let url = Bundle.main.url(forResource: "VigilChime", withExtension: "wav"),
              let audio = try? AVAudioPlayer(contentsOf: url) else { return }
        player?.stop(); player = audio
        audio.currentDevice = VigilAudioRoute.snapshot().uid
        audio.isMeteringEnabled = true
        audio.volume = VoiceVisionPolicy.volume(UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5)
        audio.prepareToPlay(); started = audio.play()
    }
}

/// Read current CoreAudio routing at each playback; never change system volume.
enum VigilAudioRoute {
    struct Snapshot {
        var name = "Default output"
        var uid: String?
        var volume: Float?
        var muted: Bool?
        var running = false
        var dictionary: [String: Any] {
            ["name": name, "uid": uid ?? "default", "volume": volume.map { $0 as Any } ?? NSNull(),
             "muted": muted.map { $0 as Any } ?? NSNull(), "running": running]
        }
    }
    static func snapshot() -> Snapshot {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return Snapshot() }
        var result = Snapshot()
        func string(_ selector: AudioObjectPropertySelector) -> String? {
            var value: CFString?; var size = UInt32(MemoryLayout<CFString?>.size)
            var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value) == noErr else { return nil }
            guard let value else { return nil }; return value as String
        }
        result.name = string(kAudioObjectPropertyName) ?? result.name
        result.uid = string(kAudioDevicePropertyDeviceUID)
        var volume: Float = 0; size = UInt32(MemoryLayout<Float>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr { result.volume = volume }
        var mute: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size); address.mSelector = kAudioDevicePropertyMute
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &mute) == noErr { result.muted = mute != 0 }
        var running: UInt32 = 0; address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere; address.mScope = kAudioObjectPropertyScopeGlobal
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr { result.running = running != 0 }
        return result
    }
}
#endif

@MainActor enum VigilFeedback {
    static func tap() {
        guard !VoiceVisionController.proofMode else { return }
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        #endif
    }
    static func nudge(_ style: VigilNudgeStyle? = nil) {
        let selected = style ?? VigilNudgeStyle(rawValue: UserDefaults.standard.string(forKey: "vigil.nudge.style") ?? "bounce") ?? .bounce
        if selected == .spokenLine, VigilVoiceOutput.shared.enabled { VoiceVisionController.shared.pauseForSpeech(); VigilVoiceOutput.shared.speak(VoiceVisionPolicy.shortLines.randomElement()!) }
        if selected == .chime, !VoiceVisionController.proofMode {
            #if os(macOS)
            VigilChime.shared.play()
            #else
            VigilChirp.shared.play()
            #endif
        }
        VoiceVisionController.shared.effect = selected
        VoiceVisionController.shared.effectAt = Date()
    }
    // Settings and the installed-app check deliberately share this action.
    static func testNudge(_ style: VigilNudgeStyle) { nudge(style) }
}
#endif
