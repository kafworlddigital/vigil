#if VIGIL_VOICE_VISION
import SwiftUI
import Speech
import AVFoundation

/// Apple recognition is required to be on-device; there is no cloud speech fallback.
@MainActor final class VigilWakeListener: ObservableObject {
    @Published private(set) var listening = false
    @Published var message = "Wake listening is off."
    var onCommand: ((VigilVoiceCommand) -> Void)?
    var onWake: (() -> Void)?
    private var recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var debounce: Task<Void, Never>?
    private var rotation: Task<Void, Never>?
    private var generation = UUID()
    private var tapped = false
    private var delivered = false
    private var armedUntil = Date.distantPast
    private var wakeShown = false
    private var lastCommand: VigilVoiceCommand?
    private(set) var wakeCount = 0
    private(set) var inputPeak: Float = 0

    func arm() {
        armedUntil = Date().addingTimeInterval(10)
        onWake?()
        start()
    }

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
        self.recognizer = recognizer
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let engine = AVAudioEngine(); self.engine = engine
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = ["Vigil"]
            self.request = request; delivered = false; wakeShown = false; lastCommand = nil
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let result, !self.delivered {
                        let transcript = result.bestTranscription.formattedString
                        let heardName = VigilVoiceCommand.hasWakeWord(transcript)
                        if heardName && !self.wakeShown {
                            self.wakeShown = true; self.wakeCount += 1
                            self.armedUntil = Date().addingTimeInterval(10); self.onWake?()
                        }
                        let command = VigilVoiceCommand.parse(transcript, requiresWakeWord: Date() >= self.armedUntil)
                        if let command, command != self.lastCommand {
                            self.lastCommand = command; self.debounce?.cancel()
                            self.debounce = Task { @MainActor [weak self] in
                                do { try await Task.sleep(nanoseconds: 700_000_000) } catch { return }
                                guard let self, self.generation == token, !self.delivered else { return }
                                self.delivered = true; self.armedUntil = .distantPast; self.stop(); self.onCommand?(command)
                            }
                        } else if command == nil {
                            self.lastCommand = nil; self.debounce?.cancel(); self.debounce = nil
                        }
                    }
                    if (error != nil || result?.isFinal == true), self.lastCommand == nil {
                        self.stop()
                        self.rotation = Task { @MainActor [weak self] in
                            do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
                            guard let self, VoiceVisionController.shared.enabled || Date() < self.armedUntil else { return }
                            self.start()
                        }
                    }
                }
            }
            let input = engine.inputNode, format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw WakeFailure.noInput }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
                request?.append(buffer)
                if let data = buffer.floatChannelData?[0] {
                    var peak: Float = 0
                    for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[index])) }
                    Task { @MainActor [weak self] in self?.inputPeak = peak }
                }
            }
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
        request?.endAudio(); recognition?.cancel(); recognition = nil; request = nil; recognizer = nil; engine = nil; listening = false
        message = "Wake listening is off."
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
    private enum WakeFailure: Error { case noInput }
}
#endif
