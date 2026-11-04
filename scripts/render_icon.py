"""Render the icon with the actual upstream SwiftUI face, on the cloud macOS runner."""
import pathlib,subprocess,json
r=pathlib.Path(__file__).resolve().parent.parent
wire=(r/'Shared/GooglyLink.swift').read_text().split('public struct Packet:')[0]
icon=(r/'App/Character/VigilProof.swift').read_text().split('struct VigilIconView:View {')[1].rsplit('#endif',1)[0]
sources=['import AppKit\nimport SwiftUI\n',wire,(r/'Shared/Palette.swift').read_text(),(r/'App/Character/BlobShape.swift').read_text(),(r/'App/Character/FaceView.swift').read_text(),'struct VigilIconView:View {'+icon]
sources.append(r'''
@MainActor func png<V:View>(_ view:V,_ url:URL,opaque:Bool=false) throws {
    let renderer=ImageRenderer(content:view);renderer.scale=1
    guard let image=renderer.nsImage,let tiff=image.tiffRepresentation,
          var bitmap=NSBitmapImageRep(data:tiff) else {fatalError("Icon render failed")}
    if opaque {
        let width=bitmap.pixelsWide,height=bitmap.pixelsHigh
        let rect=CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height))
        guard let source=image.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let rgb=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {fatalError("RGB context failed")}
        rgb.setFillColor(NSColor.black.cgColor);rgb.fill(rect);rgb.draw(source,in:rect)
        guard let result=rgb.makeImage() else {fatalError("RGB conversion failed")}
        bitmap=NSBitmapImageRep(cgImage:result)
    }
    guard let data=bitmap.representation(using:.png,properties:[:]) else {fatalError("PNG conversion failed")}
    try data.write(to:url)
}
try MainActor.assumeIsolated {
    let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
    try png(VigilIconView().frame(width:1024,height:1024),root.appendingPathComponent("Resources/Vigil icon.png"),opaque:true)
    let previews=root.appendingPathComponent("proofs/icon-v2",isDirectory:true)
    try FileManager.default.createDirectory(at:previews,withIntermediateDirectories:true)
    for size in [1024,180,60,40] {
        let k=CGFloat(size)
        try png(VigilIconView().frame(width:1024,height:1024).scaleEffect(k/1024).frame(width:k,height:k).clipped().clipShape(RoundedRectangle(cornerRadius:k*0.224,style:.continuous)),previews.appendingPathComponent("masked-\(size).png"))
    }
    try png(VigilIconView().frame(width:1024,height:1024).clipShape(RoundedRectangle(cornerRadius:229.376,style:.continuous)),previews.appendingPathComponent("mac-master.png"))
}
''')
temp=pathlib.Path('/tmp/vigil-icon-render.swift');temp.write_text('\n'.join(sources))
subprocess.run(['swift',str(temp),str(r)],check=True,timeout=120)
master=r/'Resources/Vigil icon.png'
folder=r/'Resources/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((folder/'Contents.json').read_text())['images']:
 n=round(float(item['size'].split('x')[0])*float(item['scale'].replace('x','')))
 subprocess.run(['sips','-z',str(n),str(n),str(master),'--out',str(folder/item['filename'])],stdout=subprocess.DEVNULL,check=True)
iconset=r/'proofs/icon-v2/Vigil.iconset';iconset.mkdir(exist_ok=True)
for n in [16,32,128,256,512]:
 for scale in [1,2]:
  filename=f'icon_{n}x{n}'+('@2x' if scale==2 else '')+'.png'
  subprocess.run(['sips','-z',str(n*scale),str(n*scale),str(r/'proofs/icon-v2/mac-master.png'),'--out',str(iconset/filename)],stdout=subprocess.DEVNULL,check=True)
subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(r/'Resources/AppIcon.icns')],check=True)
subprocess.run(['cp',str(master),str(r/'proofs/icon-v2/icon-1024.png')],check=True)
print('Icon v2: full 70% blueberry body, black margins, native continuous corner previews at 1024/180/60/40; iOS and Mac assets generated')
