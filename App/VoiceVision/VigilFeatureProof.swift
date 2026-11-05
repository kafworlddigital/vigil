#if VIGIL_VOICE_VISION && os(macOS)
import AppKit
import SwiftUI
import AVFoundation
import Speech
import ScreenCaptureKit
import CoreAudio
import Carbon
import ApplicationServices

/// Explicit bounded evidence modes: silent cloud previews, or an authorised
/// local hardware check. Neither mode sends a provider request.
@MainActor enum VigilFeatureProof {
    /// Explicit overnight check: no permission request and no model/screen upload.
    static func beginRepairCheck() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--vigil-audio-check"), index + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        Task { @MainActor in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let controller = VoiceVisionController.shared, wake = controller.wake, voice = VigilVoiceOutput.shared
            let host = VigilCharacterHost.shared
            let originalCommand = wake.onCommand, originalWake = wake.onWake
            var commands = 0
            wake.onCommand = { _ in commands += 1 }; wake.onWake = {}
            defer { wake.onCommand = originalCommand; wake.onWake = originalWake; wake.stop(); controller.resumeListening() }
            controller.refreshVoicePermissions(); wake.stop(); voice.stop()
            var result: [String: Any] = ["build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                "bundleID": Bundle.main.bundleIdentifier ?? "?", "microphonePermission": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
                "speechPermission": SFSpeechRecognizer.authorizationStatus().rawValue, "onDeviceLocales": VigilWakeListener.availability,
                "voicePermissionCardNeeded": controller.voiceNeedsPermission, "systemPermissionPromptsTriggered": false,
                "outputBefore": VigilAudioRoute.snapshot().dictionary, "appVolume": UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5,
                "captureKind": "real installed app NSWindow content-view bitmaps; not an independent WindowServer capture"]
            if let microphone = AVCaptureDevice.default(for: .audio) {
                result["microphoneDevice"] = ["name": microphone.localizedName, "connected": microphone.isConnected, "suspended": microphone.isSuspended]
            }
            @MainActor func save(_ window: NSWindow?, _ name: String) {
                guard let view = window?.contentView else { return }
                view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: folder.appendingPathComponent(name + ".png")) }
            }
            controller.effectAt = .distantPast
            save(host.panel, "face-before")
            VigilFeedback.testNudge(.colourFlash)
            var previous = 0.0
            for (number, seconds) in [0.36, 0.8, 1.2, 1.6, 2.0, 2.45].enumerated() {
                try? await Task.sleep(nanoseconds: UInt64((seconds - previous) * 1_000_000_000)); previous = seconds
                save(host.panel, "face-pulse-\(number + 1)")
            }
            controller.installHotKey()
            result["hotKeyLabel"] = controller.hotKeyLabel; result["hotKeyRegistrationStatus"] = controller.hotKeyStatus
            let keyBefore = controller.manualStartCount
            if CGPreflightPostEventAccess() {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(controller.hotKeyCode), keyDown: down)
                    var flags: CGEventFlags = []
                    if controller.hotKeyModifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
                    if controller.hotKeyModifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
                    if controller.hotKeyModifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
                    if controller.hotKeyModifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
                    event?.flags = flags; event?.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            result["hotkeyNativeEventReceived"] = controller.manualStartCount > keyBefore
            save(controller.bubbleForCheck, "shortcut-listening-card")
            wake.stop()
            // AVAudioPlayer isPlaying + progressing playhead + metered signal and
            // independently queried non-zero, unmuted default device are the
            // requested alternative when system loopback is unavailable.
            VigilChime.shared.play()
            var chimeSamples: [[String: Any]] = []
            for _ in 0..<7 {
                try? await Task.sleep(nanoseconds: 70_000_000)
                chimeSamples.append(["isPlaying": VigilChime.shared.isPlaying, "time": VigilChime.shared.playbackTime,
                    "peakDBFS": VigilChime.shared.playbackPower, "output": VigilAudioRoute.snapshot().dictionary])
            }
            result["chimePlayback"] = chimeSamples
            voice.speak("Vigil here.", entireLine: true, audition: true)
            var speechSamples: [[String: Any]] = []
            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 70_000_000)
                if voice.isPlaying {
                    speechSamples.append(["isPlaying": true, "time": voice.playbackTime, "peakDBFS": voice.playbackPower,
                        "output": VigilAudioRoute.snapshot().dictionary, "playerDeviceUID": voice.outputDevice])
                }
                if !voice.speaking { break }
            }
            result["speechPlayback"] = speechSamples; result["speechRenderedPeak"] = voice.renderedPeak
            result["speechBackend"] = voice.backend; voice.stop(); wake.stop()
            let tests = NSPanel(contentRect: CGRect(x: 80, y: 180, width: 480, height: 700), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            tests.title = "Vigil Settings check"; tests.hidesOnDeactivate = false
            tests.contentView = NSHostingView(rootView: ScrollView { VigilFeatureSettings().padding(20) }.frame(width: 480, height: 700))
            tests.orderFrontRegardless()
            try? await Task.sleep(nanoseconds: 400_000_000)
            @MainActor func find(_ object: NSObject, _ wanted: String, _ depth: Int = 0) -> NSObject? {
                guard depth < 25 else { return nil }
                for key in ["accessibilityIdentifier", "accessibilityLabel"] {
                    let selector = NSSelectorFromString(key)
                    if object.responds(to: selector), let value = object.perform(selector)?.takeUnretainedValue() as? String, value == wanted { return object }
                }
                let selector = NSSelectorFromString("accessibilityChildren")
                if object.responds(to: selector), let children = object.perform(selector)?.takeUnretainedValue() as? [NSObject] {
                    for child in children { if let match = find(child, wanted, depth + 1) { return match } }
                }
                if let view = object as? NSView { for child in view.subviews { if let match = find(child, wanted, depth + 1) { return match } } }
                return nil
            }
            var pressed = false
            if let view = tests.contentView, let button = find(view, "features.soundCheck") ?? find(view, "Sound check") {
                let selector = NSSelectorFromString("accessibilityPerformPress")
                if button.responds(to: selector) {
                    typealias Press = @convention(c) (AnyObject, Selector) -> Bool
                    pressed = unsafeBitCast(button.method(for: selector), to: Press.self)(button, selector)
                }
            }
            result["settingsSoundCheckButtonPressed"] = pressed
            result["settingsChangeHotkeyPresent"] = tests.contentView.flatMap { find($0, "features.changeHotkey") } != nil
            if !pressed { controller.soundCheck() }
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if !controller.soundCheckRunning { break }
            }
            result["soundCheckMessage"] = controller.soundCheckMessage
            result["soundCheckInputBuffers"] = wake.inputBuffers; result["soundCheckMaximumInputPeak"] = wake.maximumInputPeak
            save(tests, "settings-sound-check"); tests.orderOut(nil); voice.stop(); wake.stop()
            // Local synthetic audio only; no human audio/transcript is retained.
            var recognitionResults: [[String: Any]] = []
            if !controller.voiceNeedsPermission {
                for name in ["Vigil", "Virgil"] {
                    let url = folder.appendingPathComponent("synthetic-\(name).aiff")
                    let say = Process(); say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                    say.arguments = ["-o", url.path, "--", name + ", what is this?"]
                    say.standardOutput = FileHandle.nullDevice; say.standardError = FileHandle.nullDevice
                    do { try say.run(); say.waitUntilExit() } catch { continue }
                    guard say.terminationStatus == 0 else { continue }
                    for locale in ["en-GB", "en-US"] {
                        let test = VigilSyntheticRecognition()
                        recognitionResults.append(await test.run(url, locale: locale, name: name))
                    }
                    wake.start(); let count = wake.wakeCount, before = commands
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if let player = try? AVAudioPlayer(contentsOf: url) {
                        player.currentDevice = VigilAudioRoute.snapshot().uid
                        player.volume = VoiceVisionPolicy.volume(UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5)
                        _ = player.play()
                        for _ in 0..<65 {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                            if commands > before { break }
                        }
                        recognitionResults.append(["kind": "real default-output speaker to microphone", "name": name,
                            "wakeDetected": wake.wakeCount > count, "commandDetected": commands > before,
                            "inputBuffers": wake.inputBuffers, "inputPeak": wake.maximumInputPeak, "listenerError": wake.lastError,
                            "listenerMessage": wake.message, "locale": wake.localeIdentifier])
                        player.stop()
                    }
                    wake.stop()
                }
            }
            result["recognitionTests"] = recognitionResults
            result["finishedAt"] = ISO8601DateFormatter().string(from: Date())
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("hardware-results.json"), options: .atomic)
            }
            controller.status = ""; controller.answer = ""
            controller.updateBubble()
        }
    }
    /// Explicit local hardware check. Unlike preview mode this really plays audio.
    static func beginNudgeCheck() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--vigil-nudge-check"), i + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let host = VigilCharacterHost.shared, controller = VoiceVisionController.shared
            let voice = VigilVoiceOutput.shared
            controller.wake.stop(); voice.stop()
            let meter = VigilNudgeAudioMeter()
            var result: [String: Any] = ["build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
                "captureKind": "installed native app own-window view captures; no screen/preview fixtures", "systemAudioPermission": CGPreflightScreenCaptureAccess(),
                "accessibilityPermission": AXIsProcessTrusted(), "volume": UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5,
                "spokenEnabled": voice.enabled, "colour": CompanionPreferences().colour.rawValue,
                "applicationActiveDuringTests": NSApp.isActive]
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            @MainActor func save(_ view: NSView?, _ name: String) {
                guard let view else { return }; view.displayIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: folder.appendingPathComponent(name + ".png")) }
            }
            var stream: SCStream?
            if CGPreflightScreenCaptureAccess() {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    if let window = content.windows.first(where: { $0.owningApplication?.processID == getpid() }) {
                        let config = SCStreamConfiguration(); config.width = 2; config.height = 2
                        config.capturesAudio = true; config.excludesCurrentProcessAudio = false
                        let capture = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
                        try capture.addStreamOutput(meter, type: .audio, sampleHandlerQueue: DispatchQueue(label: "vigil.nudge.system-audio"))
                        try await capture.startCapture(); stream = capture
                        result["audioLevelSource"] = "ScreenCaptureKit system output"
                    }
                } catch { result["systemAudioError"] = String(describing: error) }
            }
            if stream == nil { result["audioLevelSource"] = "system output capture blocked; microphone speaker-loopback only"; meter.startMicrophone() }
            let tests = NSPanel(contentRect: CGRect(x: 80, y: 180, width: 340, height: 250), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            tests.title = "Vigil Settings nudge tests"; tests.hidesOnDeactivate = false; tests.level = .floating
            tests.contentView = NSHostingView(rootView: VigilNudgeTestButtons().padding(20).frame(width: 340, height: 250))
            tests.orderFrontRegardless()
            try? await Task.sleep(nanoseconds: 600_000_000)
            save(tests.contentView, "settings-test-buttons")
            // Own-process accessibility traversal needs no control of other apps.
            @MainActor func find(_ object: NSObject, _ wanted: String, _ depth: Int = 0) -> NSObject? {
                guard depth < 20 else { return nil }
                for key in ["accessibilityIdentifier", "accessibilityLabel"] {
                    let selector = NSSelectorFromString(key)
                    if object.responds(to: selector), let value = object.perform(selector)?.takeUnretainedValue() as? String,
                       value == wanted { return object }
                }
                let selector = NSSelectorFromString("accessibilityChildren")
                if object.responds(to: selector), let children = object.perform(selector)?.takeUnretainedValue() as? [NSObject] {
                    for child in children { if let value = find(child, wanted, depth + 1) { return value } }
                }
                if let view = object as? NSView { for child in view.subviews { if let value = find(child, wanted, depth + 1) { return value } } }
                return nil
            }
            var rows: [[String: Any]] = []
            for style in VigilNudgeStyle.allCases {
                controller.effectAt = .distantPast
                try? await Task.sleep(nanoseconds: 400_000_000)
                save(host.panel?.contentView, style.rawValue + "-before")
                meter.reset()
                try? await Task.sleep(nanoseconds: 400_000_000)
                let baseline = meter.snapshot(); meter.reset()
                let button = tests.contentView.flatMap { find($0, "features.test." + style.rawValue) ?? find($0, "Test " + style.title) }
                let selector = NSSelectorFromString("accessibilityPerformPress")
                var pressed = false
                if let button, button.responds(to: selector) {
                    typealias Press = @convention(c) (AnyObject, Selector) -> Bool
                    pressed = unsafeBitCast(button.method(for: selector), to: Press.self)(button, selector)
                }
                if !pressed { VigilFeedback.testNudge(style) }
                try? await Task.sleep(nanoseconds: 220_000_000)
                save(host.panel?.contentView, style.rawValue + "-during-1")
                let outputRunning = VigilNudgeAudioMeter.outputRunning()
                try? await Task.sleep(nanoseconds: 300_000_000)
                save(host.panel?.contentView, style.rawValue + "-during-2")
                if style == .spokenLine {
                    for _ in 0..<100 {
                        if !voice.speaking { break }; try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                } else { try? await Task.sleep(nanoseconds: 1_700_000_000) }
                rows.append(["style": style.rawValue, "settingsButtonPressed": pressed, "sameSettingsActionInvoked": true,
                    "baseline": baseline, "during": meter.snapshot(), "chimePlayerStarted": VigilChime.shared.started,
                    "speechBackend": voice.backend, "speechRenderedPeak": voice.renderedPeak, "speechPlayerStarted": voice.playerStarted,
                    "outputDeviceRunningDuring": outputRunning])
                voice.stop(); controller.wake.stop()
            }
            tests.orderOut(nil)
            meter.stop(); if let stream { try? await stream.stopCapture() }
            controller.installHotKey(); result["hotKeyRegistrationStatus"] = controller.hotKeyStatus
            let beforeClick = controller.manualStartCount
            if let panel = host.panel {
                let location = NSPoint(x: panel.frame.width / 2, y: panel.frame.height / 2)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) { panel.sendEvent(event) }
                }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            result["faceClickNativeEventDispatched"] = controller.manualStartCount > beforeClick
            let beforeKey = controller.manualStartCount
            result["globalEventPostPermission"] = CGPreflightPostEventAccess()
            if CGPreflightPostEventAccess() {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Space), keyDown: down)
                    event?.flags = .maskAlternate; event?.post(tap: .cghidEventTap)
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            result["globalHotKeyNativeEventDispatched"] = controller.manualStartCount > beforeKey
            controller.startManualListening()
            try? await Task.sleep(nanoseconds: 800_000_000)
            result["manualListeningStarted"] = controller.wake.listening
            save(controller.bubbleForCheck?.contentView, "manual-listening-bubble")
            controller.wake.stop()
            // Real speaker → microphone wake check, not an injected transcript.
            controller.wake.start()
            let count = controller.wake.wakeCount
            if controller.wake.listening {
                let synth = NSSpeechSynthesizer(voice: nil)
                synth?.volume = VoiceVisionPolicy.volume(UserDefaults.standard.object(forKey: "vigil.voice.volume") as? Double ?? 0.5)
                _ = synth?.startSpeaking("Vigil")
                for _ in 0..<50 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if controller.wake.wakeCount > count { break }
                }
                synth?.stopSpeaking()
            }
            result["speakerToMicrophoneWakeDetected"] = controller.wake.wakeCount > count
            result["onDeviceWakeListeningStarted"] = controller.wake.listening
            result["speechPermission"] = SFSpeechRecognizer.authorizationStatus().rawValue
            result["microphonePermission"] = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
            save(controller.bubbleForCheck?.contentView, "wake-listening-bubble")
            result["nudges"] = rows; result["finishedAt"] = ISO8601DateFormatter().string(from: Date())
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("hardware-results.json"), options: .atomic)
            }
            controller.wake.stop(); controller.dismissAnswer(); controller.resumeListening()
        }
    }
    static func begin() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--vigil-feature-proof"), index + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let controller = VoiceVisionController.shared
                @MainActor func render<V: View>(_ view: V, _ name: String) throws {
                    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
                    renderer.scale = 2
                    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw ProofFailure.render }
                    try png.write(to: folder.appendingPathComponent(name + ".png"), options: .atomic)
                }
                for style in VigilNudgeStyle.allCases {
                    controller.effect = style; controller.effectAt = Date().addingTimeInterval(-0.22)
                    try render(VigilNativeFeatureCard(title: style.title, detail: style == .spokenLine ? "Spoken line: ‘Back to it.’ · Audio is muted in this preview." : "Test this effect in Settings. This is a cloud view preview.")
                        .frame(width: 640, height: 440), "nudge-" + style.rawValue)
                }
                controller.answer = "A blue shirt."; controller.status = "Synthetic answer fixture · no model request"
                controller.answeredAt = Date().addingTimeInterval(-0.2)
                try render(VigilNativeFeatureCard(title: "What is this?", detail: "One short sentence by the face · sparkle preview").frame(width: 640, height: 440), "answer-and-sparkles")
                controller.answer = ""; controller.recording = true; controller.busy = true
                controller.status = "Recording · 4 seconds · ask your question now"
                try render(VigilNativeFeatureCard(title: "Look at me", detail: "Indicator fixture · camera and microphone are OFF in this preview").frame(width: 640, height: 440), "camera-indicator")
                controller.recording = false; controller.busy = false; controller.answer = ""; controller.status = ""
                for page in VigilFeatureIntroduction.cards.indices {
                    try render(VigilFeatureIntroduction(initialPage: page).frame(width: 640, height: 480), "onboarding-" + String(page + 1))
                }
                let receipt: [String: Any] = ["kind": "native SwiftUI cloud preview with synthetic answer fixtures", "cameraCaptured": false, "speechPlayed": false,
                    "physicalDeviceAcceptance": false, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"]
                try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("native-feature-previews.json"))
            } catch { NSLog("Vigil feature preview failed; no acceptance claimed.") }
        }
    }
    private enum ProofFailure: Error { case render }
}

/// An actual Apple on-device recognizer for a known, locally generated sentence.
@MainActor private final class VigilSyntheticRecognition {
    private var task: SFSpeechRecognitionTask?
    private var done = false
    private var text = ""
    private var failure = ""
    func run(_ url: URL, locale: String, name: String) async -> [String: Any] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            return ["kind": "synthetic file on-device recognition", "name": name, "locale": locale, "available": false]
        }
        let request = SFSpeechURLRecognitionRequest(url: url); request.requiresOnDeviceRecognition = true
        request.contextualStrings = ["Vigil", "Virgil", "Vigil what is this"]
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.text = result.bestTranscription.formattedString; if result.isFinal { self.done = true } }
                if let error { let e = error as NSError; self.failure = "\(e.domain) \(e.code)"; self.done = true }
            }
        }
        for _ in 0..<100 { if done { break }; try? await Task.sleep(nanoseconds: 100_000_000) }
        task?.cancel(); task = nil
        let phrase = VigilVoiceCommand.wakePhrase(in: text)
        return ["kind": "synthetic file on-device recognition", "name": name, "locale": locale, "available": true,
            "finished": done, "syntheticTranscript": text, "error": failure,
            "wakeDetected": phrase != nil, "commandDetected": phrase.flatMap { VigilVoiceCommand.parse($0) } != nil]
    }
}

/// Keeps levels only, never audio recordings or private transcripts.
private final class VigilNudgeAudioMeter: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var rms: Double = 0
    private var buffers = 0
    private var microphone: AVAudioEngine?
    func reset() { lock.lock(); peak = 0; rms = 0; buffers = 0; lock.unlock() }
    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["peak": peak, "maxRMS": rms, "buffers": buffers, "peakDBFS": 20 * log10(max(Double(peak), 0.000000001))]
    }
    private func consume(_ samples: UnsafePointer<Float>, _ count: Int) {
        guard count > 0 else { return }
        var maximum: Float = 0, sum: Double = 0
        for i in 0..<count { maximum = max(maximum, abs(samples[i])); sum += Double(samples[i] * samples[i]) }
        lock.lock(); peak = max(peak, maximum); rms = max(rms, sqrt(sum / Double(count))); buffers += 1; lock.unlock()
    }
    func startMicrophone() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            if let data = buffer.floatChannelData?[0] { self?.consume(data, Int(buffer.frameLength)) }
        }
        microphone = engine
        do { try engine.start() } catch { stop() }
    }
    func stop() {
        if let microphone { microphone.stop(); microphone.inputNode.removeTap(onBus: 0) }; microphone = nil
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              format.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.pointee.mBitsPerChannel == 32 else { return }
        let list = AudioBufferList.allocate(maximumBuffers: 8)
        defer { list.unsafeMutablePointer.deallocate() }
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil,
            bufferListOut: list.unsafeMutablePointer, bufferListSize: MemoryLayout<AudioBufferList>.size + 7 * MemoryLayout<AudioBuffer>.size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &block) == noErr else { return }
        for buffer in list {
            if let data = buffer.mData { consume(data.assumingMemoryBound(to: Float.self), Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) }
        }
    }
    static func outputRunning() -> Bool {
        var device = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        var running: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}

private struct VigilNativeFeatureCard: View {
    let title: String
    let detail: String
    @State private var animator = FaceAnimator()
    @ObservedObject private var controller = VoiceVisionController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NATIVE CLOUD PREVIEW · SYNTHETIC DATA").font(.caption).foregroundStyle(.secondary)
            Text(title).font(.title.weight(.semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
            ZStack(alignment: .topTrailing) {
                FaceView(animator: animator).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 20))
                if controller.recording || !controller.answer.isEmpty { VigilAnswerBubble().frame(width: 285).padding(10) }
            }
            Spacer(minLength: 0)
        }.padding(24).background(.background)
    }
}
#endif
