#if VIGIL_VOICE_VISION && os(macOS)
import AppKit
import SwiftUI

/// Explicit cloud-only captures of real native views with labelled synthetic data.
/// No camera, microphone, speech, haptic, private screen content or provider request.
@MainActor enum VigilFeatureProof {
    static func begin() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--vigil-feature-proof"), index + 1 < args.count else { return }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let controller = VoiceVisionController.shared
                func render<V: View>(_ view: V, _ name: String) throws {
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
                for page in 0..<6 {
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
