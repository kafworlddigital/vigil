#if os(macOS)
import AppKit
import SwiftUI
import QuartzCore
// Explicit, bounded UI evidence mode. Captures only Vigil's own views, never another app.
@MainActor enum VigilProof {
    static func begin(host:VigilCharacterHost){
        let args=ProcessInfo.processInfo.arguments
        guard let i=args.firstIndex(of:"--vigil-proof"),i+1<args.count else{return}
        let folder=URL(fileURLWithPath:args[i+1],isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let oldMouse=NSEvent.mouseLocation
        let oldFrame=host.panel?.frame
        let oldVisible=host.visible
        host.panel?.orderFrontRegardless()
        let fixture=args.contains("--vigil-renderer-fixture")
        var samples:[[String:Any]]=[]
        var warpResult:Int32=0
        func warp(_ x:Double,_ y:Double){
            if fixture{return}
            warpResult=CGWarpMouseCursorPosition(CGPoint(x:x,y:y)).rawValue
            if CGPreflightPostEventAccess(){CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:CGPoint(x:x,y:y),mouseButton:.left)?.post(tap:.cghidEventTap)}
        }
        func sample(){samples.append(["x":host.sampledMouse.x,"y":host.sampledMouse.y,"gazeX":host.sampledFace.gazeX,"gazeY":host.sampledFace.gazeY,"mode":fixture ? "renderer fixture":"actual desktop cursor","warpResult":warpResult])}
        func save(_ view:NSView?,_ name:String){
            guard let view,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
            view.cacheDisplay(in:view.bounds,to:rep)
            if let data=rep.representation(using:.png,properties:[:]){try? data.write(to:folder.appendingPathComponent(name))}
        }
        // The caller requested two real cursor positions and two frames one second apart.
        let screen=NSScreen.screens.first?.frame ?? CGRect(x:0,y:0,width:1440,height:900)
        let left=NSScreen.screens.min(by:{$0.frame.minX<$1.frame.minX})?.frame ?? screen
        let right=NSScreen.screens.max(by:{$0.frame.maxX<$1.frame.maxX})?.frame ?? screen
        let eyeY=host.panel.map{$0.frame.minY+$0.frame.height*0.485} ?? screen.midY
        let leftEyeY=min(left.maxY-20,max(left.minY+20,eyeY))
        let rightEyeY=min(right.maxY-20,max(right.minY+20,eyeY))
        DispatchQueue.main.asyncAfter(deadline:.now()+2){
            host.setMood(.listening);if fixture{host.rendererFixtureGaze=CGPoint(x:-0.92,y:-0.85)};warp(left.minX+40,screen.maxY-leftEyeY)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+4){sample();save(host.panel?.contentView,"Mac-face-left.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+5){if fixture{host.rendererFixtureGaze=CGPoint(x:0.92,y:0.85)};warp(right.maxX-40,screen.maxY-rightEyeY)}
        DispatchQueue.main.asyncAfter(deadline:.now()+7){sample();save(host.panel?.contentView,"Mac-face-right.png");save(host.panel?.contentView,"Mac-animation-1.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+8){save(host.panel?.contentView,"Mac-animation-2.png");host.nudge("A little nudge. Ready for your next step?")}
        DispatchQueue.main.asyncAfter(deadline:.now()+8.3){save(host.cursor.view,"Mac-cursor-flight.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+10){save(host.cursor.view,"Mac-cursor-buddy.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+11){
            if let data=try? JSONSerialization.data(withJSONObject:samples,options:.prettyPrinted){try? data.write(to:folder.appendingPathComponent("Mac-cursor-gaze.json"))}
            @MainActor func render<V:View>(_ view:V,_ name:String) {
                let renderer=ImageRenderer(content:view);renderer.scale=2
                if let image=renderer.nsImage,let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) {try? png.write(to:folder.appendingPathComponent(name))}
            }
            render(VigilHelpView().frame(width:680,height:1000),"Mac-help.png")
            render(VigilIntroView{}.frame(width:520,height:440),"Mac-intro.png")
            render(VigilSettingsView(state:VigilState(),changed:{_ in}).frame(width:620,height:900),"Mac-settings.png")
            if let icon=Bundle.main.url(forResource:"AppIcon",withExtension:"icns"),let image=NSImage(contentsOf:icon),let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) {try? png.write(to:folder.appendingPathComponent("Vigil icon.png"))}
            if let oldFrame{host.panel?.setFrame(oldFrame,display:true)}
            host.rendererFixtureGaze=nil
            host.setVisible(oldVisible);host.releaseMood()
            if !fixture{CGWarpMouseCursorPosition(CGPoint(x:oldMouse.x,y:screen.maxY-oldMouse.y))}
        }
    }
}
// Whole upstream blueberry, with 15% black side margins and an uncropped crown.
struct VigilIconView:View {
    var body:some View {
        Canvas{ctx,size in
            ctx.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.black))
            var face=FaceAnimator().step(1)
            face.gaze = .zero;face.mood = .listening;face.closed=0;face.browLift=8
            face.hop=0;face.blush=0.65;face.breathe=0;face.lean=0;face.talk=0
            let scale:CGFloat=1024*0.70/820
            ctx.translateBy(x:(1024-844*scale)/2,y:176)
            ctx.scaleBy(x:scale,y:scale)
            FaceView.draw(face,in:&ctx,size:CGSize(width:844,height:390),transparent:true)
        }
    }
}
#endif
