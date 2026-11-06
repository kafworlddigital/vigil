#if os(macOS)
import AppKit
import SwiftUI
import QuartzCore
import Combine

enum Fonts { static func display(_ size:CGFloat)->NSFont { NSFont(name:"Fredoka",size:size) ?? NSFont.systemFont(ofSize:size,weight:.semibold) } }

// Adapter for Riley Brown's original CursorOverlay; art and motion remain upstream.
final class Settings {
    static let shared=Settings()
    var cursorSize:Double { 64 }
    var phonePosition:Double { 0.5 }
    var showCursor:Bool { true }
    var followMouse:Bool { true }
    var mood:Mood = .listening
    var trail:PointerTrail { PointerTrail(rawValue:UserDefaults.standard.string(forKey:"vigil.pointer.trail") ?? "comet") ?? .comet }
}
@MainActor final class VigilSettingsAccess {
    static let shared = VigilSettingsAccess()
    var show: (() -> Void)?
    func open() { show?() }
}
final class VigilDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular)
        #if VIGIL_VOICE_VISION
        VigilFeatureProof.begin()
        VigilFeatureProof.beginNudgeCheck()
        VigilFeatureProof.beginRepairCheck()
        VigilFeatureProof.beginPolishCheck()
        VigilFeatureProof.beginAcceptanceCheck()
        #endif
        let args=ProcessInfo.processInfo.arguments
        if let i=args.firstIndex(of:"--vigil-test-connections"),i+1<args.count {
            Task{@MainActor in
                let results=await ConnectionTester.run()
                if let data=try? JSONEncoder().encode(results){try? data.write(to:URL(fileURLWithPath:args[i+1]),options:.atomic)}
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
}
@MainActor final class VigilCharacterHost:NSObject {
    static let shared=VigilCharacterHost()
    let animator=FaceAnimator()
    let cursor=CursorOverlay()
    var panel:NSPanel?
    private var systemSleeping = false
    private var focused = false
    private var connections: AnyCancellable?
    private var dragAnchor:NSPoint?
    private var origin:NSPoint?
    private var dragging=false
    private var started=false
    private var moodRelease:DispatchWorkItem?
    private weak var server:MacDeviceServer?
    private var lastBroadcast=0.0
    var rendererFixtureGaze:CGPoint?
    private(set) var sampledMouse=CGPoint.zero
    private(set) var sampledFace=FaceState()
    var visible:Bool { UserDefaults.standard.object(forKey:"vigil.face.visible") as? Bool ?? true }
    private var renderingVisible: Bool {
        visible && !systemSleeping && !NSApp.isHidden && panel?.isVisible == true
    }
    func start(server:MacDeviceServer) {
        self.server=server
        guard !started else{return};started=true
        let p=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.title="Vigil desktop face";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false
        p.level = .floating;p.hidesOnDeactivate=false;p.isFloatingPanel=true;p.ignoresMouseEvents=true
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        #if VIGIL_VOICE_VISION
        p.contentView=NSHostingView(rootView:FaceView(animator:animator,transparent:true)
            .contentShape(Rectangle())
            .onTapGesture { if !NSEvent.modifierFlags.contains(.option) { VoiceVisionController.shared.startManualListening() } }
            .contextMenu {
                Button("Settings…") { VigilSettingsAccess.shared.open() }.keyboardShortcut(",", modifiers: .command)
                Button("Try everything") { VoiceVisionController.shared.openSettings() }
                Button("Listen") { VoiceVisionController.shared.startManualListening() }
            }
            .accessibilityLabel("Vigil face. Click to listen, or press \(VoiceVisionController.shared.hotKeyLabel).")
            .help("Click to listen · \(VoiceVisionController.shared.hotKeyLabel) anywhere · Option-drag to move"))
        #else
        p.contentView=NSHostingView(rootView:FaceView(animator:animator,transparent:true))
        #endif
        panel=p;resize();setVisible(visible)
        animator.persistentTarget = true
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshVisibility), name: NSApplication.didHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshVisibility), name: NSApplication.didUnhideNotification, object: nil)
        cursor.onFace={ [weak self] frame in
            guard let self else{return}
            // Keep upstream's phone gaze: it sits BELOW the monitor and looks up at the mouse/buddy.
            // The added desktop face looks from its own eyes towards the cursor on any display.
            var face=frame
            if self.focused && self.cursor.view.engine.brainMood == nil { face.mood = .resting }
            #if VIGIL_VOICE_VISION
            let controller = VoiceVisionController.shared
            if VigilVoiceOutput.shared.speaking { face.mood = .talking }
            else if controller.busy { face.mood = .thinking }
            else if controller.status == "Listening…" { face.mood = .listening }
            #endif
            let global=CGEvent(source:nil)?.location ?? .zero
            let m=NSPoint(x:global.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-global.y)
            self.sampledMouse=global
            if let panel=self.panel {
                let eyes=CGPoint(x:panel.frame.midX,y:panel.frame.minY+panel.frame.height*0.485)
                let dx=m.x-eyes.x,dy=eyes.y-m.y
                let reach=max(100,hypot(dx,dy))
                face.gazeX=dx/reach;face.gazeY=dy/reach
            }
            if let fixture=self.rendererFixtureGaze {face.gazeX=fixture.x;face.gazeY=fixture.y}
            let changedMood = self.sampledFace.mood != face.mood
            self.sampledFace=face
            if changedMood { self.cursor.requestAnimation() }
            self.animator.receive(face,at:Date.timeIntervalSinceReferenceDate)
            let paused = !self.renderingVisible || !self.cursor.isAnimating
            if self.animator.animationPaused != paused { self.animator.animationPaused = paused }
            let now=CACurrentMediaTime()
            if now-self.lastBroadcast>=1.0/30 {self.lastBroadcast=now;self.server?.broadcast(Packet(face:frame))}
        }
        cursor.onSample = { [weak self] in self?.trackDrag() }
        cursor.pointerAnimationAllowed = { [weak self] in
            guard let self else { return false }
            return !self.focused || self.dragging || self.cursor.view.engine.brainMood != nil
        }
        cursor.hasCompanions = { [weak server] in !(server?.phones.isEmpty ?? true) }
        connections = server.$phones.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.cursor.requestAnimation() }
        }
        #if VIGIL_VOICE_VISION
        cursor.needsAnimation = {
            let controller = VoiceVisionController.shared
            return controller.busy || controller.status == "Listening…" || VigilVoiceOutput.shared.speaking
        }
        #endif
        cursor.start()
        VigilProof.begin(host:self)
    }
    @objc private func displaysChanged() { resize() }
    @objc private func refreshVisibility() {
        let show = renderingVisible
        if animator.animationPaused != !show { animator.animationPaused = !show }
        if !show { dragging = false; dragAnchor = nil; origin = nil }
        cursor.setFaceVisible(show)
    }
    @objc private func systemSleep() {
        systemSleeping = true; animator.animationPaused = true; panel?.orderOut(nil); cursor.setSleeping(true)
        #if VIGIL_VOICE_VISION
        VoiceVisionController.shared.systemSleep()
        #endif
    }
    @objc private func systemWake() {
        systemSleeping = false
        resize(); setVisible(visible); cursor.setSleeping(false)
        #if VIGIL_VOICE_VISION
        VoiceVisionController.shared.systemWake()
        #endif
    }
    func resize() {
        guard let p=panel,let screen=NSScreen.main else{return}
        let w=max(160,min(440,UserDefaults.standard.double(forKey:"vigil.face.width")==0 ? 260:UserDefaults.standard.double(forKey:"vigil.face.width")))
        let h=w*390/844
        let savedX=UserDefaults.standard.object(forKey:"vigil.face.x") as? Double
        let savedY=UserDefaults.standard.object(forKey:"vigil.face.y") as? Double
        let corner=CompanionPreferences().corner
        let area=screen.visibleFrame
        let proposed=NSPoint(x:savedX ?? (corner.left ? area.minX+24:area.maxX-w-24),y:savedY ?? (corner.top ? area.maxY-h-24:area.minY+24))
        let targetArea = NSScreen.screens.first(where: { $0.visibleFrame.intersects(CGRect(origin: proposed, size: CGSize(width:w,height:h))) })?.visibleFrame ?? area
        let position=NSPoint(x:min(targetArea.maxX-w,max(targetArea.minX,proposed.x)),y:min(targetArea.maxY-h,max(targetArea.minY,proposed.y)))
        p.setFrame(NSRect(origin:position,size:NSSize(width:w,height:h)),display:true)
    }
    func placeInCorner(){
        UserDefaults.standard.removeObject(forKey:"vigil.face.x")
        UserDefaults.standard.removeObject(forKey:"vigil.face.y")
        resize()
    }
    func setVisible(_ show:Bool){
        UserDefaults.standard.set(show,forKey:"vigil.face.visible")
        if show && !systemSleeping { panel?.orderFrontRegardless() } else { panel?.orderOut(nil) }
        refreshVisibility()
        if show { DispatchQueue.main.async { [weak self] in self?.refreshVisibility() } }
    }
    func showMoveHint(){cursor.view.caption="Click my face to listen. Hold Option and drag to move me.";DispatchQueue.main.asyncAfter(deadline:.now()+7){[weak self] in self?.cursor.view.caption=nil}}
    private func trackDrag(){
        guard let p=panel,renderingVisible else{return}
        let m=NSEvent.mouseLocation
        let option=NSEvent.modifierFlags.contains(.option)
        let pressed=NSEvent.pressedMouseButtons & 1 != 0
        if option,pressed,dragging || p.frame.contains(m){
            if !dragging{dragging=true;dragAnchor=m;origin=p.frame.origin}
            if let dragAnchor,let origin{p.setFrameOrigin(NSPoint(x:origin.x+m.x-dragAnchor.x,y:origin.y+m.y-dragAnchor.y))}
        }else if dragging{
            dragging=false;UserDefaults.standard.set(p.frame.origin.x,forKey:"vigil.face.x");UserDefaults.standard.set(p.frame.origin.y,forKey:"vigil.face.y")
        }
        #if VIGIL_VOICE_VISION
        let ignore = !(dragging || p.frame.contains(m))
        if p.ignoresMouseEvents != ignore { p.ignoresMouseEvents = ignore }
        #else
        let ignore = !(option && (dragging || p.frame.contains(m)))
        if p.ignoresMouseEvents != ignore { p.ignoresMouseEvents = ignore }
        #endif
    }
    func setMood(_ mood:Mood){Settings.shared.mood=mood;cursor.view.engine.brainMood=mood;cursor.requestAnimation()}
    func releaseMood(){cursor.view.engine.brainMood=nil;Settings.shared.mood = .listening;cursor.requestAnimation()}
    /// Confirmed task evidence lets Vigil rest; uncertainty never pretends to be focus.
    func setFocusActivity(_ activity: FocusActivity?) {
        focused = activity == .onTask
        cursor.view.engine.awake = activity == .offTask
        cursor.requestAnimation()
    }
    func nudge(_ text:String,target:CGPoint?=nil){
        #if VIGIL_VOICE_VISION
        if CompanionPreferences().nudge != .quiet {VigilFeedback.nudge()}
        #endif
        moodRelease?.cancel();setMood(CompanionPreferences().nudge == .quiet ? .listening:.surprised)
        cursor.view.caption=text
        // With no verified OCR target, point at Vigil's own face, never invent a desktop target.
        if CompanionPreferences().nudge == .quiet { cursor.goHome() }
        else if let target { cursor.mode = .pinned(target) }
        else if let p=panel,let screen=NSScreen.screens.first {
            cursor.mode = .pinned(CGPoint(x:p.frame.midX-screen.frame.minX,y:screen.frame.maxY-p.frame.midY))
        }
        let release=DispatchWorkItem{[weak self] in self?.cursor.view.caption=nil;self?.cursor.goHome();self?.releaseMood()}
        moodRelease=release;DispatchQueue.main.asyncAfter(deadline:.now()+8,execute:release)
    }
}
#endif
