import SwiftUI
#if os(macOS)
import AppKit
#endif

#if VIGIL_VOICE_VISION
private struct VigilVoiceVisionIntegration: ViewModifier {
    @ObservedObject private var controller = VoiceVisionController.shared
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content
            .task { controller.start() }
            .sheet(isPresented: $controller.showIntroduction) { VigilFeatureIntroduction() }
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
