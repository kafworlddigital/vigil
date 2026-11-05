#if VIGIL_VOICE_VISION
import SwiftUI
#if os(macOS)
import AppKit
import Carbon
#endif

struct VigilAnswerBubble: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if controller.recording { Circle().fill(.red).frame(width: 8, height: 8) }
                Text(controller.recording ? "Camera and microphone on" : "Vigil").font(.caption.weight(.semibold))
                Spacer()
                if controller.busy { Button("Cancel") { controller.cancel() } }
                else { Button { controller.dismissAnswer() } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss answer") }
            }
            if controller.voiceNeedsPermission { VigilVoicePermissionCard() }
            else if controller.showShortcutCard {
                Label("Press \(controller.hotKeyLabel) to speak", systemImage: "keyboard").font(.headline)
                Text("Or click my face. Change the shortcut in Settings.").font(.caption)
            }
            else if !controller.answer.isEmpty { Text(controller.answer).font(.callout).fixedSize(horizontal: false, vertical: true) }
            if !controller.status.isEmpty { Text(controller.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.1), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
    }
}

struct VigilVoicePermissionCard: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    @State private var requesting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Let Vigil hear you", systemImage: "mic").font(.headline)
            Text(controller.permissionMessage).font(.callout).fixedSize(horizontal: false, vertical: true)
            Button("Allow") {
                requesting = true
                Task { await controller.allowVoice(); requesting = false }
            }.buttonStyle(.borderedProminent).disabled(requesting).accessibilityIdentifier("features.allowVoice")
        }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

#if os(macOS)
struct VigilHotKeySheet: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change listen shortcut").font(.title2.weight(.semibold))
            Text("Press a new combination with Control, Option or Command.")
            VigilHotKeyRecorder { event in
                if event.keyCode == 53 { dismiss(); return }
                var modifiers: UInt32 = 0
                let flags = event.modifierFlags
                if flags.contains(.control) { modifiers |= UInt32(controlKey) }
                if flags.contains(.option) { modifiers |= UInt32(optionKey) }
                if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
                let key = event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers ?? "").uppercased()
                guard !key.isEmpty else { return }
                let label = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + key
                if controller.changeHotKey(code: UInt32(event.keyCode), modifiers: modifiers, label: label) { dismiss() }
            }.frame(height: 50).overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
            Text(controller.hotKeyMessage).font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 400)
    }
}

private struct VigilHotKeyRecorder: NSViewRepresentable {
    let received: (NSEvent) -> Void
    func makeNSView(context: Context) -> KeyView { let view = KeyView(); view.received = received; return view }
    func updateNSView(_ view: KeyView, context: Context) { view.received = received }
    final class KeyView: NSView {
        var received: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
        override func keyDown(with event: NSEvent) { received?(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { received?(event); return true }
        override func draw(_ dirtyRect: NSRect) {
            let text = "Type shortcut here" as NSString
            text.draw(at: NSPoint(x: 16, y: 16), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }
}
#endif

struct VigilVoiceBar: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    @ObservedObject private var wake = VoiceVisionController.shared.wake
    @State private var typedCommand = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: wake.listening ? "mic.fill" : "mic.slash")
                Text(wake.listening ? "Listening for ‘Vigil’ on-device" : "Voice and vision").font(.caption)
                Spacer()
                Button(wake.listening ? "Stop listening" : "Listen") { controller.setListening(!wake.listening) }
            }
            HStack {
                #if os(macOS)
                Button("What is this?") { controller.ask(.whatIsThis("")) }
                #endif
                Button("Look at me") { controller.ask(.lookAtMe("")) }
                Button("I’m stuck") { controller.ask(.stuck("")) }
                Button("Introduction") { controller.showIntroduction = true }
            }.disabled(controller.busy)
            HStack {
                TextField("Vigil, remind me in 10 minutes to…", text: $typedCommand).textFieldStyle(.roundedBorder)
                    .onSubmit { sendCommand() }
                Button("Ask") { sendCommand() }.disabled(typedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.busy)
            }
            #if os(iOS)
            if controller.busy || !controller.answer.isEmpty || !controller.status.isEmpty { VigilAnswerBubble() }
            #endif
        }
    }
    private func sendCommand() {
        if let command = VigilVoiceCommand.parse(typedCommand) { controller.ask(command); typedCommand = "" }
        else { controller.announce("Try ‘Vigil, I’m stuck’ or ‘Vigil, remind me in 10 minutes to stretch’.", speak: false) }
    }
}

struct VigilFeatureSettings: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    @ObservedObject private var wake = VoiceVisionController.shared.wake
    @AppStorage("vigil.nudge.style") private var style = "bounce"
    @AppStorage("vigil.voice.spoken") private var spoken = true
    @AppStorage("vigil.voice.identifier") private var voice = ""
    @AppStorage("vigil.voice.volume") private var volume = 0.5
    @AppStorage("vigil.camera.keepClips") private var keepClips = false
    @State private var changingHotKey = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nudges, voice and vision").font(.headline)
            Picker("Nudge style", selection: $style) {
                ForEach(VigilNudgeStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }.accessibilityIdentifier("features.nudgeStyle")
            VigilNudgeTestButtons()
            Toggle("Spoken nudges and answers", isOn: $spoken).onChange(of: spoken) { _, value in
                if !value { VigilVoiceOutput.shared.stop(); controller.resumeListening() }
            }
            Picker("Apple voice", selection: $voice) {
                Text("British English default").tag("")
                ForEach(VigilVoiceOutput.voices, id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) }
            }.disabled(!spoken)
            HStack {
                Text("Volume"); Slider(value: $volume, in: 0...1)
                Text("\(Int(volume * 100))%").monospacedDigit().frame(width: 45)
            }
            Text("Apple's installed voices are free. Short nudges say ‘Back to it’, ‘Focus’ or ‘One thing’. Silence mode turns speech off.").font(.caption).foregroundStyle(.secondary)
            Text("Volume controls both chime and speech. Zero means silent. Colour flash uses your companion colour.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Sound check") { controller.soundCheck() }
                    .disabled(controller.soundCheckRunning).accessibilityIdentifier("features.soundCheck")
                Text(controller.soundCheckRunning ? "Checking…" : "Chime, then ‘Vigil here.’").font(.caption).foregroundStyle(.secondary)
            }
            #if os(macOS)
            Text("Output: \(controller.audioOutputName)").font(.caption).foregroundStyle(.secondary)
            #endif
            ProgressView(value: min(1, Double(wake.inputPeak) * 8)) {
                Text(wake.listening ? "Microphone level" : "Microphone off").font(.caption)
            }.accessibilityIdentifier("features.microphoneLevel")
            if !controller.soundCheckMessage.isEmpty { Text(controller.soundCheckMessage).font(.caption).fixedSize(horizontal: false, vertical: true) }
            Divider()
            if controller.voiceNeedsPermission { VigilVoicePermissionCard() }
            Toggle("Listen for ‘Vigil’ on this device", isOn: Binding(get: { controller.enabled }, set: controller.setListening))
            Text(wake.message).font(.caption).foregroundStyle(.secondary)
            Button("Restart listening") { wake.stop(); controller.resumeListening() }.disabled(!controller.enabled || controller.busy)
            #if os(macOS)
            HStack {
                Text("Listen shortcut"); Spacer(); Text(controller.hotKeyLabel).font(.body.monospaced().weight(.medium))
                Button("Change") { changingHotKey = true }.accessibilityIdentifier("features.changeHotkey")
            }.sheet(isPresented: $changingHotKey) { VigilHotKeySheet() }
            Text(controller.hotKeyMessage).font(.caption).foregroundStyle(.secondary)
            Text("\(controller.hotKeyLabel) works from any app. Click Vigil’s face to listen; Option-drag moves the face.").font(.caption)
            Text("Say ‘Vigil, what is this?’ to read the item under your pointer. Accessibility text comes first; otherwise only a small crop is sent. Protected work screens are skipped.").font(.caption)
            #else
            Text("Wake listening works while Vigil is open. iPhone and iPad cannot read other apps or the Mac pointer. For that, speak to Vigil on the Mac.").font(.caption)
            #endif
            Text("Say ‘Vigil, look at me’, then ask your question during the four-second camera clip. Three small frames and on-device transcribed words go to the available models; raw video and audio are never uploaded.").font(.caption)
            Toggle("Keep requested camera clips after answers", isOn: $keepClips)
            Text(keepClips ? "Clips stay locally in Vigil's Application Support / Requested clips folder. Turning this off leaves previously saved clips in place." : "Temporary clips are removed after the answer, cancellation or an error. Saving is off.").font(.caption).foregroundStyle(.secondary)
            Text("Answers bring a small sparkle and a light haptic tap on supported hardware. Reduce Motion replaces motion with a quiet glow.").font(.caption).foregroundStyle(.secondary)
            Button("Feature introduction and permissions") { controller.showIntroduction = true }
            VigilSupportSettings()
            VigilVoiceBar()
        }.onAppear { controller.refreshVoicePermissions() }
    }
}

/// The same native buttons are exercised by the bounded installed-app check.
struct VigilNudgeTestButtons: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(VigilNudgeStyle.allCases, id: \.rawValue) { option in
                HStack {
                    Text(option.title); Spacer()
                    Button("Test") { VigilFeedback.testNudge(option) }
                        .accessibilityLabel("Test " + option.title).accessibilityIdentifier("features.test." + option.rawValue)
                }
            }
        }
    }
}

struct VigilFeatureIntroduction: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    @State private var page = 0
    @State private var requesting = false
    init(initialPage: Int = 0) { _page = State(initialValue: min(Self.cards.count - 1, max(0, initialPage))) }
    static let cards: [(String, String, String)] = [
        ("Choose your nudge", "bell.badge", "Pick a chime, a little bounce, a colour flash, an eye wiggle or a spoken line. Try each in Settings. Motion stays around Vigil's face."),
        ("A few quiet words", "speaker.wave.2", "‘Back to it.’ ‘Focus.’ ‘One thing.’ Choose a free Apple voice and volume, or switch speech off in Settings."),
        ("Vigil, what is this?", "cursorarrow.rays", "On Mac, point at something and ask. Vigil reads Accessibility text first, or sends a small cursor crop. You hear one sentence and see a bubble by the face. Other apps stay private on iPhone and iPad."),
        ("A small celebration", "sparkles", "A short sparkle around the face and a light haptic tap mark an answer. Haptics depend on your hardware; Reduce Motion uses a gentle glow."),
        ("Vigil, look at me", "camera", "Only your request starts a video clip. A visible indicator stays on during the four-second video and audio clip. Ask your question while it records. Only three small frames and locally recognised words are sent. The temporary clip is removed after the answer unless you enable saving."),
        ("Vigil, I’m stuck", "arrow.right.circle", "Say or type ‘Vigil, I’m stuck’ for one small next step on your current focus task. Free non-OpenAI models fail over automatically; a simple local step is always available. Switch it off in Settings."),
        ("Remind me in a few minutes", "timer", "Say or type ‘Vigil, remind me in 10 minutes to send the draft’. Vigil saves the reminder locally, nudges and speaks when due while open. Background or closed apps use an Apple notification; speech needs Vigil running. Manage or cancel reminders in Settings."),
        ("Meeting in 5 minutes", "calendar", "Enable meeting warnings in Settings and allow Calendar once. Vigil reads meeting titles locally and gives a five-minute heads-up. No calendar information goes to a model; no events are changed."),
        ("A little break", "figure.stand", "After 50 minutes of continuous work, hear ‘Stand up. Drink water.’ Change the interval or turn it off in Settings. An idle period or sleep resets the clock. This is a work timer, not a sitting sensor."),
        ("A private tired check", "eye", "Off by default. Enable it and confirm your camera cover is open for this run. Every five minutes, one frame is checked by Apple Vision on-device for eyes, mouth and posture cues. No image is saved or uploaded. Cover closed, darkness, cancellation or backgrounding skips the check; there is no reliable hardware cover sensor. These cues are fallible, not a health assessment."),
        ("You're in control", "hand.raised", "Microphone and Speech Recognition let Vigil hear its name on-device. On Mac, Accessibility reads the pointed item and Screen Recording allows a small crop. Camera permission is requested only when you ask to record or explicitly enable tired checks with the cover open. Wake listening is visible and can be stopped at any time. Free non-OpenAI models fail over automatically; providers have their own data policies.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("VOICE AND VISION").font(.caption.weight(.semibold)); Spacer(); Text("\(page + 1) of \(Self.cards.count)").font(.caption.monospacedDigit()) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: Self.cards[page].1).font(.system(size: 38)).foregroundStyle(Color(hex: Palette.gradient[2]))
                    Text(Self.cards[page].0).font(.largeTitle.weight(.semibold))
                    Text(Self.cards[page].2).font(.title3).fixedSize(horizontal: false, vertical: true)
                    #if os(macOS)
                    if page == 0 {
                        Label("Press \(controller.hotKeyLabel) or click my face to speak.", systemImage: "keyboard")
                        Text("Change the shortcut in Settings.").font(.caption).foregroundStyle(.secondary)
                    }
                    #endif
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            }
            HStack {
                if page > 0 { Button("Back") { page -= 1 } }
                Button("Later") { controller.skipIntroduction() }
                Spacer()
                Button(page == Self.cards.count - 1 ? "Enable voice features" : "Next") {
                    if page < Self.cards.count - 1 { page += 1 }
                    else { requesting = true; Task { await controller.enablePermissions(); requesting = false } }
                }.buttonStyle(.borderedProminent).disabled(requesting)
            }
        }.padding(24).frame(minWidth: 300, idealWidth: 540, minHeight: 300, idealHeight: 470)
            .interactiveDismissDisabled(requesting)
    }
}

/// Lightweight native Canvas particles; one bounded burst and no particle engine.
struct VigilFaceEffects: ViewModifier {
    @ObservedObject private var controller = VoiceVisionController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let age = timeline.date.timeIntervalSince(controller.effectAt)
            let burst = timeline.date.timeIntervalSince(controller.answeredAt)
            let wave = age >= 0 && age < 1.6 ? sin(age * .pi * 4) * (1 - age / 1.6) : 0
            content
                .offset(y: !reduceMotion && controller.effect == .bounce ? -abs(wave) * 18 : 0)
                .overlay {
                    Group {
                    // The face Canvas draws the masked glow; this overlay holds particles only.
                    if !reduceMotion && burst >= 0 && burst < 1.1 {
                        Canvas { context, size in
                            for index in 0..<14 {
                                let angle = Double(index) * .pi * 2 / 14
                                let travel = 0.4 + burst * 0.35
                                let x = size.width / 2 + cos(angle) * size.width * travel
                                let y = size.height / 2 + sin(angle) * size.height * travel
                                let radius = max(0.7, 2.4 * (1 - burst / 1.1))
                                let star = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                                context.fill(Path(ellipseIn: star), with: .color((index.isMultiple(of: 3) ? Color.white : Color(hex: Palette.gradient[1])).opacity(max(0, 1 - burst / 1.1))))
                            }
                        }
                    }
                    }.allowsHitTesting(false)
                }
        }
    }
}
#endif
