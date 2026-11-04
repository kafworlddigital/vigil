import sys,pathlib,struct,zlib,hashlib,json
p=pathlib.Path(sys.argv[1])
def pixels(name):
 raw=(p/name).read_bytes();assert raw.startswith(b"\x89PNG"),name
 i=8;data=b""
 while i<len(raw):
  n=int.from_bytes(raw[i:i+4],"big");kind=raw[i+4:i+8]
  if kind==b"IDAT":data+=raw[i+8:i+8+n]
  i+=12+n
 return zlib.decompress(data)
gaze=json.loads((p/"Mac-cursor-gaze.json").read_text())
fixture=all(g.get("mode")=="renderer fixture" for g in gaze)
if fixture:assert "--allow-renderer-fixture" in sys.argv,"Actual desktop cursor proof required"
else:
 assert all(g.get("mode")=="actual desktop cursor" for g in gaze)
 assert abs(gaze[0]["x"]-gaze[1]["x"])>100,"Desktop cursor did not move"

assert len(gaze)==2 and gaze[0]["gazeX"] < -0.5 and gaze[1]["gazeX"] > 0.5, "Cursor gaze did not track both actual desktop positions: "+str(gaze)
for a,b in [("Mac-face-left.png","Mac-face-right.png"),("Mac-animation-1.png","Mac-animation-2.png")]:
 assert pixels(a)!=pixels(b),"Character did not change: "+a
for name in ["Mac-cursor-buddy.png","Mac-cursor-flight.png","Vigil icon.png"]: assert len(pixels(name))>100
(p/"Mac-launch.json").write_text(json.dumps({"survivedSeconds":15,"configuration":"Release","cursorPositions":0 if fixture else 2,"rendererFixture":fixture,"animationFrameSpacingSeconds":1,"capture":"Vigil own rendered views only"},indent=2))
print("Mac survived 15 seconds; two gaze directions and animation differ; "+("RENDERER FIXTURE, real Mac cursor gate still required" if fixture else "ACTUAL DESKTOP CURSOR VERIFIED"))
