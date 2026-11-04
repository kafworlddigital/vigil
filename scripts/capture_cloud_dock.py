from pathlib import Path
import ctypes as C,plistlib,subprocess,json,time,sys,hashlib
app=Path(sys.argv[1]).resolve();info=plistlib.loads((app/'Contents/Info.plist').read_bytes());assert info['CFBundleIdentifier']=='com.kafworlddigital.vigil.mac'
out=Path('proofs');out.mkdir(exist_ok=True)
url=app.as_uri()+'/'
entry={'tile-type':'file-tile','tile-data':{'file-type':41,'file-label':'Vigil','bundle-identifier':info['CFBundleIdentifier'],'file-data':{'_CFURLString':url,'_CFURLStringType':15}}}
raw=plistlib.dumps(entry).decode();xml=raw[raw.index('<dict>'):raw.rindex('</dict>')+7]
dock=plistlib.loads(subprocess.check_output(['defaults','export','com.apple.dock','-']))
if not any(x.get('tile-data',{}).get('file-data',{}).get('_CFURLString')==url for x in dock.get('persistent-apps',[])):
 subprocess.run(['defaults','write','com.apple.dock','persistent-apps','-array-add',xml],check=True)
subprocess.run(['defaults','write','com.apple.dock','autohide','-bool','false'],check=True)
dockProcess=subprocess.run(['pgrep','-x','Dock'],capture_output=True)
if dockProcess.returncode!=0:
 subprocess.Popen(['/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock'],stdout=(out/'Dock-process.log').open('w'),stderr=subprocess.STDOUT)
subprocess.run(['open','-g','-n',str(app),'--args','--vigil-screen','face','--vigil-skip-intro'],check=False)
time.sleep(10)
cg=C.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');cf=C.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
cg.CGWindowListCopyWindowInfo.argtypes=[C.c_uint32,C.c_uint32];cg.CGWindowListCopyWindowInfo.restype=C.c_void_p
cf.CFPropertyListCreateData.argtypes=[C.c_void_p,C.c_void_p,C.c_long,C.c_ulong,C.c_void_p];cf.CFPropertyListCreateData.restype=C.c_void_p
cf.CFDataGetLength.argtypes=[C.c_void_p];cf.CFDataGetLength.restype=C.c_long
cf.CFDataGetBytePtr.argtypes=[C.c_void_p];cf.CFDataGetBytePtr.restype=C.c_void_p;cf.CFRelease.argtypes=[C.c_void_p]
a=cg.CGWindowListCopyWindowInfo(1,0);d=cf.CFPropertyListCreateData(None,a,100,0,None);windows=plistlib.loads(C.string_at(cf.CFDataGetBytePtr(d),cf.CFDataGetLength(d)));cf.CFRelease(d);cf.CFRelease(a)
(out/'Cloud-Dock-windows.json').write_text(json.dumps([w for w in windows if w.get('kCGWindowOwnerName')=='Dock'],indent=2))
subprocess.run(['screencapture','-x',str(out/'Cloud-Mac-Desktop.png')],check=True,timeout=30)
found=[]
for w in windows:
 b=w.get('kCGWindowBounds',{});width=b.get('Width',0);height=b.get('Height',0)
 if w.get('kCGWindowOwnerName')=='Dock' and max(width,height)>200 and 20<min(width,height)<250:found.append(w)
if not found:
 print('Whole cloud desktop captured for direct Dock inspection; no bounded Dock window was reported.')
 (out/'Cloud-Mac-Dock.json').write_text(json.dumps({'environment':'GitHub hosted macOS test machine; not Keith desktop','iconSHA256':hashlib.sha256((app/'Contents/Resources/AppIcon.icns').read_bytes()).hexdigest(),'scope':'Actual isolated cloud desktop; inspect Dock in the image'},indent=2))
 raise SystemExit
window=max(found,key=lambda w:w['kCGWindowBounds']['Width']*w['kCGWindowBounds']['Height'])
subprocess.run(['screencapture','-x','-l',str(window['kCGWindowNumber']),str(out/'Cloud-Mac-Dock.png')],check=True,timeout=30)
assert (out/'Cloud-Mac-Dock.png').stat().st_size>1000
(out/'Cloud-Mac-Dock.json').write_text(json.dumps({'environment':'GitHub hosted macOS test machine; not Keith desktop','bundle':info['CFBundleIdentifier'],'build':info['CFBundleVersion'],'iconSHA256':hashlib.sha256((app/'Contents/Resources/AppIcon.icns').read_bytes()).hexdigest(),'appPath':str(app),'scope':'Actual Dock window only'},indent=2))
print('Actual cloud Mac Dock screenshot captured; clearly labelled as cloud proof.')
