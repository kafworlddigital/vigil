#if os(macOS)
import AppKit
import SwiftUI
import QuartzCore

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
final class VigilDelegate:NSObject,NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.regular)
        #if VIGIL_VOICE_VISION
        VigilFeatureProof.begin()
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
    private var poll:Timer?
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
    func start(server:MacDeviceServer) {
        self.server=server
        guard !started else{return};started=true
        let p=NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.title="Vigil desktop face";p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=false
        p.level = .floating;p.hidesOnDeactivate=false;p.isFloatingPanel=true;p.ignoresMouseEvents=true
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        p.contentView=NSHostingView(rootView:FaceView(animator:animator,transparent:true))
        panel=p;resize();setVisible(visible)
        cursor.onFace={ [weak self] frame in
            guard let self else{return}
            // Keep upstream's phone gaze: it sits BELOW the monitor and looks up at the mouse/buddy.
            // The added desktop face looks from its own eyes towards the cursor on any display.
            var face=frame
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
            self.sampledFace=face
            self.animator.receive(face,at:Date.timeIntervalSinceReferenceDate)
            let now=CACurrentMediaTime()
            if now-self.lastBroadcast>=1.0/30 {self.lastBroadcast=now;self.server?.broadcast(Packet(face:frame))}
        }
        cursor.start()
        VigilProof.begin(host:self)
        poll=Timer.scheduledTimer(withTimeInterval:1.0/30,repeats:true){[weak self] _ in Task{@MainActor in self?.trackDrag()}}
    }
    func resize() {
        guard let p=panel,let screen=NSScreen.main else{return}
        let w=max(160,min(440,UserDefaults.standard.double(forKey:"vigil.face.width")==0 ? 260:UserDefaults.standard.double(forKey:"vigil.face.width")))
        let h=w*390/844
        let savedX=UserDefaults.standard.object(forKey:"vigil.face.x") as? Double
        let savedY=UserDefaults.standard.object(forKey:"vigil.face.y") as? Double
        let corner=CompanionPreferences().corner
        let area=screen.visibleFrame
        let position=NSPoint(x:savedX ?? (corner.left ? area.minX+24:area.maxX-w-24),y:savedY ?? (corner.top ? area.maxY-h-24:area.minY+24))
        p.setFrame(NSRect(origin:position,size:NSSize(width:w,height:h)),display:true)
    }
    func placeInCorner(){
        UserDefaults.standard.removeObject(forKey:"vigil.face.x")
        UserDefaults.standard.removeObject(forKey:"vigil.face.y")
        resize()
    }
    func setVisible(_ show:Bool){UserDefaults.standard.set(show,forKey:"vigil.face.visible");if show{panel?.orderFrontRegardless()}else{panel?.orderOut(nil)}}
    func showMoveHint(){cursor.view.caption="Hold Option and drag my face to move me. Ordinary clicks pass through.";DispatchQueue.main.asyncAfter(deadline:.now()+7){[weak self] in self?.cursor.view.caption=nil}}
    private func trackDrag(){
        guard let p=panel,visible else{return}
        let m=NSEvent.mouseLocation
        let option=NSEvent.modifierFlags.contains(.option)
        let pressed=NSEvent.pressedMouseButtons & 1 != 0
        if option,pressed,dragging || p.frame.contains(m){
            if !dragging{dragging=true;dragAnchor=m;origin=p.frame.origin}
            if let dragAnchor,let origin{p.setFrameOrigin(NSPoint(x:origin.x+m.x-dragAnchor.x,y:origin.y+m.y-dragAnchor.y))}
        }else if dragging{
            dragging=false;UserDefaults.standard.set(p.frame.origin.x,forKey:"vigil.face.x");UserDefaults.standard.set(p.frame.origin.y,forKey:"vigil.face.y")
        }
        // Transparent at rest; only the deliberate Option-drag gesture consumes input.
        p.ignoresMouseEvents = !(option && (dragging || p.frame.contains(m)))
    }
    func setMood(_ mood:Mood){Settings.shared.mood=mood;cursor.view.engine.brainMood=mood}
    func releaseMood(){cursor.view.engine.brainMood=nil;Settings.shared.mood = .listening}
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
