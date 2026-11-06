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
    @Published private(set) var inputPeak: Float = 0
    var meteringRequested = false
    private(set) var inputBuffers = 0
    private(set) var maximumInputPeak: Float = 0
    private(set) var localeIdentifier = ""
    private(set) var lastError = ""
    private var routeObserver: NSObjectProtocol?

    static var availableRecognizer: SFSpeechRecognizer? {
        (VigilEdition.macy ? ["en-US"] : ["en-GB", "en-US"]).compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first { $0.isAvailable && $0.supportsOnDeviceRecognition }
    }
    static var availability: [[String: Any]] {
        ["en-GB", "en-US"].map { locale in
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
            return ["locale": locale, "available": recognizer?.isAvailable ?? false, "onDevice": recognizer?.supportsOnDeviceRecognition ?? false]
        }
    }

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
        guard let recognizer = Self.availableRecognizer else {
            message = "On-device English speech is unavailable. Download English Dictation in your device’s keyboard settings, then restart listening."; return
        }
        let token = generation
        self.recognizer = recognizer
        localeIdentifier = recognizer.locale.identifier; lastError = ""
        inputBuffers = 0; inputPeak = 0; maximumInputPeak = 0
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let engine = AVAudioEngine(); self.engine = engine
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = ["Vigil", "Virgil", "Vigil what is this", "Vigil look at me"]
            request.taskHint = .confirmation
            self.request = request; delivered = false; wakeShown = false; lastCommand = nil
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let result, !self.delivered {
                        let transcript = result.bestTranscription.formattedString
                        let phrase = VigilVoiceCommand.wakePhrase(in: transcript)
                        let heardName = phrase != nil
                        if heardName && !self.wakeShown {
                            self.wakeShown = true; self.wakeCount += 1
                            self.armedUntil = Date().addingTimeInterval(10); self.onWake?()
                        }
                        let command = VigilVoiceCommand.parse(phrase ?? transcript, requiresWakeWord: Date() >= self.armedUntil)
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
                    if let error {
                        let failure = error as NSError
                        self.lastError = "\(failure.domain) \(failure.code)"
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
            let meter = VigilInputMeter()
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
                request?.append(buffer)
                if let data = buffer.floatChannelData?[0] {
                    var peak: Float = 0
                    for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[index])) }
                    guard let batch = meter.observe(peak: peak) else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.inputBuffers = batch.buffers; self.maximumInputPeak = batch.maximum
                        if self.meteringRequested || Date() < self.armedUntil {
                            if self.inputPeak != batch.peak { self.inputPeak = batch.peak }
                        }
                        let silent = "Microphone is delivering silence. Check macOS Sound → Input and speak near the selected mic."
                        if batch.buffers > 150 && batch.maximum < 0.00001 && self.message != silent {
                            self.message = silent
                        }
                    }
                }
            }
            tapped = true; engine.prepare(); try engine.start()
            listening = true; message = "Listening on-device for ‘Vigil’ or ‘Virgil’ · \(localeIdentifier)"
            routeObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }; self.stop()
                    if VoiceVisionController.shared.enabled { self.start() }
                }
            }
            // Recognition sessions are bounded. Rotate rather than holding an expired task.
            rotation = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 50_000_000_000) } catch { return }
                guard let self, self.generation == token else { return }
                self.stop(); self.start()
            }
        } catch {
            stop(); let failure = error as NSError; lastError = "\(failure.domain) \(failure.code)"
            message = "Microphone unavailable (\(failure.code)). Check your device’s microphone settings, then restart listening."
        }
    }
    func stop() {
        generation = UUID(); debounce?.cancel(); debounce = nil; rotation?.cancel(); rotation = nil
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }; routeObserver = nil
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
