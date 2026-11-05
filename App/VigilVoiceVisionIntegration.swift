import SwiftUI

#if VIGIL_VOICE_VISION
private struct VigilVoiceVisionIntegration: ViewModifier {
    @ObservedObject private var controller = VoiceVisionController.shared
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .task { controller.start() }
            .sheet(isPresented: $controller.showIntroduction) { VigilFeatureIntroduction() }
            #if os(iOS)
            .onChange(of: scenePhase) { _, phase in controller.setForeground(phase == .active) }
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
