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
        var samples:[[String:Double]]=[]
        func warp(_ x:Double,_ y:Double){
            CGWarpMouseCursorPosition(CGPoint(x:x,y:y))
            CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:CGPoint(x:x,y:y),mouseButton:.left)?.post(tap:.cghidEventTap)
        }
        func sample(){samples.append(["x":host.sampledMouse.x,"y":host.sampledMouse.y,"gazeX":host.sampledFace.gazeX,"gazeY":host.sampledFace.gazeY])}
        func save(_ view:NSView?,_ name:String){
            guard let view,let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
            view.cacheDisplay(in:view.bounds,to:rep)
            if let data=rep.representation(using:.png,properties:[:]){try? data.write(to:folder.appendingPathComponent(name))}
        }
        // The caller requested two real cursor positions and two frames one second apart.
        let screen=NSScreen.screens.first?.frame ?? CGRect(x:0,y:0,width:1440,height:900)
        DispatchQueue.main.asyncAfter(deadline:.now()+2){
            host.setMood(.listening);warp(40,40)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+4){sample();save(host.panel?.contentView,"Mac-face-left.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+5){warp(screen.width-40,screen.height-40)}
        DispatchQueue.main.asyncAfter(deadline:.now()+7){sample();save(host.panel?.contentView,"Mac-face-right.png");save(host.panel?.contentView,"Mac-animation-1.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+8){save(host.panel?.contentView,"Mac-animation-2.png");host.nudge("A little nudge. Ready for your next step?")}
        DispatchQueue.main.asyncAfter(deadline:.now()+8.3){save(host.cursor.view,"Mac-cursor-flight.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+10){save(host.cursor.view,"Mac-cursor-buddy.png")}
        DispatchQueue.main.asyncAfter(deadline:.now()+11){
            if let data=try? JSONSerialization.data(withJSONObject:samples,options:.prettyPrinted){try? data.write(to:folder.appendingPathComponent("Mac-cursor-gaze.json"))}
            let design=VigilIconView().frame(width:1024,height:1024)
            let renderer=ImageRenderer(content:design);renderer.scale=1
            if let image=renderer.nsImage,let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]){try? png.write(to:folder.appendingPathComponent("Vigil icon.png"))}
            if let oldFrame{host.panel?.setFrame(oldFrame,display:true)}
            host.setVisible(oldVisible);host.releaseMood()
            CGWarpMouseCursorPosition(CGPoint(x:oldMouse.x,y:screen.maxY-oldMouse.y))
        }
    }
}
// Uses the same upstream renderer and paths, composed over a full-bleed midnight glow.
struct VigilIconView:View {
    var body:some View {
        Canvas{ctx,size in
            ctx.fill(Path(CGRect(origin:.zero,size:size)),with:.radialGradient(Gradient(colors:[Color(hex:0x344AC0),Color(hex:0x090E35)]),center:CGPoint(x:512,y:460),startRadius:40,endRadius:750))
            var face=FaceAnimator().step(1)
            face.gaze = .zero;face.mood = .listening;face.closed=0;face.browLift=8;face.hop=0;face.blush=0.65
            // The face is enlarged from the original landscape art, retaining round eyes and crown.
            ctx.translateBy(x:0,y:230)
            FaceView.draw(face,in:&ctx,size:CGSize(width:1024,height:474),transparent:true)
            // Continue the body gradient down to the full-bleed edge, behind the lower crop.
        }
    }
}
#endif
