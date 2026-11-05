#if VIGIL_VOICE_VISION
import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor final class VigilVoiceOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = VigilVoiceOutput()
    @Published private(set) var speaking = false
    private let synthesizer = AVSpeechSynthesizer()
    var onFinished: (() -> Void)?
    override init() { super.init(); synthesizer.delegate = self }
    var enabled: Bool { UserDefaults.standard.object(forKey: "vigil.voice.spoken") as? Bool ?? true }
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }
    func speak(_ text: String) {
        guard enabled, !VoiceVisionController.proofMode else { return }
        stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let line = AVSpeechUtterance(string: VoiceVisionPolicy.sentence(text))
        let identifier = UserDefaults.standard.string(forKey: "vigil.voice.identifier") ?? ""
        line.voice = AVSpeechSynthesisVoice(identifier: identifier) ?? AVSpeechSynthesisVoice(language: "en-GB")
        line.volume = VoiceVisionPolicy.volume(UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5)
        line.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        speaking = true
        synthesizer.speak(line)
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate); speaking = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speaking = false
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            self.onFinished?()
        }
    }
}

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
            NSSound(named: NSSound.Name("Pop"))?.play()
            #else
            VigilChirp.shared.play()
            #endif
        }
        VoiceVisionController.shared.effect = selected
        VoiceVisionController.shared.effectAt = Date()
    }
}
#endif
