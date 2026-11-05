#if VIGIL_VOICE_VISION
import SwiftUI
import Speech
import AVFoundation

/// Apple recognition is required to be on-device; there is no cloud speech fallback.
@MainActor final class VigilWakeListener: ObservableObject {
    @Published private(set) var listening = false
    @Published var message = "Wake listening is off."
    var onCommand: ((VigilVoiceCommand) -> Void)?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var debounce: Task<Void, Never>?
    private var rotation: Task<Void, Never>?
    private var generation = UUID()
    private var tapped = false
    private var delivered = false

    func start() {
        guard !listening, !VoiceVisionController.proofMode else { return }
        stop()
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            message = "Enable Microphone and Speech Recognition in the introduction."; return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            message = "On-device English speech is unavailable. Use the buttons instead."; return
        }
        let token = generation
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let engine = AVAudioEngine(); self.engine = engine
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = ["Vigil", "Vigil what is this", "Vigil look at me"]
            self.request = request; delivered = false
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let result, !self.delivered,
                       let command = VigilVoiceCommand.parse(result.bestTranscription.formattedString) {
                        self.debounce?.cancel()
                        self.debounce = Task { @MainActor [weak self] in
                            do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
                            guard let self, self.generation == token, !self.delivered else { return }
                            self.delivered = true; self.stop(); self.onCommand?(command)
                        }
                    } else if result != nil { self.debounce?.cancel() }
                    if (error != nil || result?.isFinal == true), self.debounce == nil || self.debounce?.isCancelled == true {
                        self.stop(); self.message = "Speech paused. Tap Listen to restart."
                    }
                }
            }
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw WakeFailure.noInput }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in request?.append(buffer) }
            tapped = true; engine.prepare(); try engine.start()
            listening = true; message = "Listening on-device for ‘Vigil’ · microphone on"
            // Recognition sessions are bounded. Rotate rather than holding an expired task.
            rotation = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 50_000_000_000) } catch { return }
                guard let self, self.generation == token else { return }
                self.stop(); self.start()
            }
        } catch { stop(); message = "The microphone is busy. Use the buttons or try Listen again." }
    }
    func stop() {
        generation = UUID(); debounce?.cancel(); debounce = nil; rotation?.cancel(); rotation = nil
        engine?.stop()
        if tapped { engine?.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil; engine = nil; listening = false
        message = "Wake listening is off."
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    private enum WakeFailure: Error { case noInput }
}
#endif
