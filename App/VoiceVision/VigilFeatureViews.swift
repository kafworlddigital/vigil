#if VIGIL_VOICE_VISION
import SwiftUI

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
            if !controller.answer.isEmpty { Text(controller.answer).font(.callout).fixedSize(horizontal: false, vertical: true) }
            if !controller.status.isEmpty { Text(controller.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.1), lineWidth: 0.5))
            .accessibilityElement(children: .contain)
    }
}

struct VigilVoiceBar: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    @ObservedObject private var wake = VoiceVisionController.shared.wake
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
                Button("Introduction") { controller.showIntroduction = true }
            }.disabled(controller.busy)
            #if os(iOS)
            if controller.busy || !controller.answer.isEmpty || !controller.status.isEmpty { VigilAnswerBubble() }
            #endif
        }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nudges, voice and vision").font(.headline)
            Picker("Nudge style", selection: $style) {
                ForEach(VigilNudgeStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }.accessibilityIdentifier("features.nudgeStyle")
            ForEach(VigilNudgeStyle.allCases, id: \.rawValue) { option in
                HStack {
                    Text(option.title); Spacer()
                    Button("Test") { VigilFeedback.nudge(option) }
                        .accessibilityLabel("Test " + option.title).accessibilityIdentifier("features.test." + option.rawValue)
                }
            }
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
            }.disabled(!spoken)
            Text("Apple's installed voices are free. Short nudges say ‘Back to it’, ‘Focus’ or ‘One thing’. Silence mode turns speech off.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Listen for ‘Vigil’ on this device", isOn: Binding(get: { controller.enabled }, set: controller.setListening))
            Text(wake.message).font(.caption).foregroundStyle(.secondary)
            Button("Restart listening") { wake.stop(); controller.resumeListening() }.disabled(!controller.enabled || controller.busy)
            #if os(macOS)
            Text("Say ‘Vigil, what is this?’ to read the item under your pointer. Accessibility text comes first; otherwise only a small crop is sent. Protected work screens are skipped.").font(.caption)
            #else
            Text("Wake listening works while Vigil is open. iPhone and iPad cannot read other apps or the Mac pointer. For that, speak to Vigil on the Mac.").font(.caption)
            #endif
            Text("Say ‘Vigil, look at me’, then ask your question during the four-second camera clip. Three small frames and on-device transcribed words go to the available models; raw video and audio are never uploaded.").font(.caption)
            Toggle("Keep requested camera clips after answers", isOn: $keepClips)
            Text(keepClips ? "Clips stay locally in Vigil's Application Support / Requested clips folder. Turning this off leaves previously saved clips in place." : "Temporary clips are removed after the answer, cancellation or an error. Saving is off.").font(.caption).foregroundStyle(.secondary)
            Text("Answers bring a small sparkle and a light haptic tap on supported hardware. Reduce Motion replaces motion with a quiet glow.").font(.caption).foregroundStyle(.secondary)
            Button("Feature introduction and permissions") { controller.showIntroduction = true }
            VigilVoiceBar()
        }
    }
}

struct VigilFeatureIntroduction: View {
    @ObservedObject private var controller = VoiceVisionController.shared
    @State private var page = 0
    @State private var requesting = false
    init(initialPage: Int = 0) { _page = State(initialValue: min(5, max(0, initialPage))) }
    static let cards: [(String, String, String)] = [
        ("Choose your nudge", "bell.badge", "Pick a chime, a little bounce, a colour flash, an eye wiggle or a spoken line. Try each in Settings. Motion stays around Vigil's face."),
        ("A few quiet words", "speaker.wave.2", "‘Back to it.’ ‘Focus.’ ‘One thing.’ Choose a free Apple voice and volume, or switch speech off in Settings."),
        ("Vigil, what is this?", "cursorarrow.rays", "On Mac, point at something and ask. Vigil reads Accessibility text first, or sends a small cursor crop. You hear one sentence and see a bubble by the face. Other apps stay private on iPhone and iPad."),
        ("A small celebration", "sparkles", "A short sparkle around the face and a light haptic tap mark an answer. Haptics depend on your hardware; Reduce Motion uses a gentle glow."),
        ("Vigil, look at me", "camera", "Only your request starts the camera. A visible indicator stays on during the four-second video and audio clip. Ask your question while it records. Only three small frames and locally recognised words are sent. The temporary clip is removed after the answer unless you enable saving."),
        ("You're in control", "hand.raised", "Microphone and Speech Recognition let Vigil hear its name on-device. On Mac, Accessibility reads the pointed item and Screen Recording allows a small crop. Camera permission is requested only when you ask to record. Wake listening is visible and can be stopped at any time. Free or included non-OpenAI models fail over automatically; providers have their own data policies.")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("VOICE AND VISION").font(.caption.weight(.semibold)); Spacer(); Text("\(page + 1) of \(Self.cards.count)").font(.caption.monospacedDigit()) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: Self.cards[page].1).font(.system(size: 38)).foregroundStyle(Color(hex: Palette.gradient[2]))
                    Text(Self.cards[page].0).font(.largeTitle.weight(.semibold))
                    Text(Self.cards[page].2).font(.title3).fixedSize(horizontal: false, vertical: true)
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
            let wave = age >= 0 && age < 0.9 ? sin(age * .pi * 5) * (1 - age / 0.9) : 0
            content
                .offset(y: !reduceMotion && controller.effect == .bounce ? -abs(wave) * 9 : 0)
                .overlay {
                    Group {
                    if (age >= 0 && age < 0.8 && controller.effect == .colourFlash) || (reduceMotion && burst >= 0 && burst < 0.8) {
                        RoundedRectangle(cornerRadius: 35).stroke(Color(hex: Palette.gradient[1]).opacity(0.7), lineWidth: 3).padding(4)
                    }
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
