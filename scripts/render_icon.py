"""Render the icon with the actual upstream SwiftUI face, on the cloud macOS runner."""
import pathlib,subprocess,json
r=pathlib.Path(__file__).resolve().parent.parent
wire=(r/'Shared/GooglyLink.swift').read_text().split('public struct Packet:')[0]
icon=(r/'App/Character/VigilProof.swift').read_text().split('struct VigilIconView:View {')[1].rsplit('#endif',1)[0]
sources=['import AppKit\nimport SwiftUI\n',wire,(r/'Shared/Palette.swift').read_text(),(r/'App/Character/BlobShape.swift').read_text(),(r/'App/Character/FaceView.swift').read_text(),'struct VigilIconView:View {'+icon]
sources.append('''
let renderer=ImageRenderer(content:VigilIconView().frame(width:1024,height:1024))
renderer.scale=1
guard let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let png=bitmap.representation(using:.png,properties:[:])else{fatalError("Icon render failed")}
try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
''')
temp=pathlib.Path('/tmp/vigil-icon-render.swift');temp.write_text('\n'.join(sources))
master=r/'Resources/Vigil icon.png'
subprocess.run(['swift',str(temp),str(master)],check=True,timeout=120)
folder=r/'Resources/Assets.xcassets/AppIcon.appiconset'
for item in json.loads((folder/'Contents.json').read_text())['images']:
 n=round(float(item['size'].split('x')[0])*float(item['scale'].replace('x','')))
 subprocess.run(['sips','-z',str(n),str(n),str(master),'--out',str(folder/item['filename'])],stdout=subprocess.DEVNULL,check=True)
(r/'proofs').mkdir(exist_ok=True)
subprocess.run(['sips','-z','60','60',str(master),'--out',str(r/'proofs/Icon-60.png')],stdout=subprocess.DEVNULL,check=True)
print('Rendered full-bleed icon using Bluey FaceView.draw; all app icon sizes updated')
