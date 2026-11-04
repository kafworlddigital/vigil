#if os(macOS)
import AppKit
import SwiftUI

/// Screenshots of live production SwiftUI in Vigil's own nonactivating window.
/// No desktop pixels, Accessibility permission or cursor movement is needed.
@MainActor enum VigilIntroCapture {
    private static var panel:NSPanel?
    static func begin(){
        let args=ProcessInfo.processInfo.arguments
        guard let i=args.firstIndex(of:"--vigil-intro-proof"),i+1<args.count else{return}
        let folder=URL(fileURLWithPath:args[i+1],isDirectory:true)
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let frame=NSRect(x:80,y:80,width:720,height:900)
        let window=NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        window.backgroundColor = .windowBackgroundColor;window.isOpaque=true
        window.hidesOnDeactivate=false;window.title="Vigil intro preview"
        panel=window
        func show(_ page:Int){
            let view=NSHostingView(rootView:VigilIntroView(initialPage:page){}.environment(\.colorScheme,.light))
            view.frame=NSRect(origin:.zero,size:frame.size);window.contentView=view
            window.orderFrontRegardless();view.layoutSubtreeIfNeeded();view.display()
        }
        func capture(_ name:String){
            guard let view=window.contentView else{return}
            view.layoutSubtreeIfNeeded();view.display()
            guard let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
            view.cacheDisplay(in:view.bounds,to:rep)
            if let png=rep.representation(using:.png,properties:[:]){try? png.write(to:folder.appendingPathComponent(name))}
        }
        for page in 0..<6{
            DispatchQueue.main.asyncAfter(deadline:.now()+Double(page*3+1)){show(page)}
            DispatchQueue.main.asyncAfter(deadline:.now()+Double(page*3+3)){capture("Mac-intro-\(page+1).png")}
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+20){window.orderOut(nil);panel=nil}
    }
}
#endif
