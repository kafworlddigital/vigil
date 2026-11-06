import SwiftUI
#if os(macOS)
import AppKit
#endif

#if VIGIL_VOICE_VISION
private struct VigilVoiceVisionIntegration: ViewModifier {
    @ObservedObject private var controller = VoiceVisionController.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("vigil.intro.v2.completed") private var basicIntroductionComplete = false
    func body(content: Content) -> some View {
        content
            .task { controller.start() }
            .sheet(isPresented: $controller.showIntroduction) { VigilFeatureIntroduction() }
            .onChange(of: basicIntroductionComplete) { _, completed in
                if completed && VigilEdition.macy && !UserDefaults.standard.bool(forKey: "vigil.voice.introduced") {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard basicIntroductionComplete && !UserDefaults.standard.bool(forKey: "vigil.voice.introduced") else { return }
                        controller.showIntroduction = true
                    }
                }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                controller.refreshVoicePermissions(); controller.resumeListening(); controller.updateBubble()
            }
            #endif
            #if os(iOS)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { controller.setForeground(false) }
                else if phase == .active { controller.setForeground(true) }
            }
            #endif
    }
}
#endif
extension View {
    func vigilVoiceVision() -> some View {
        #if VIGIL_VOICE_VISION
        modifier(VigilVoiceVisionIntegration())
        #else
        self
        #endif
    }
}
