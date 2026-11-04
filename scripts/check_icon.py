from pathlib import Path
import json,struct,hashlib
r=Path(__file__).resolve().parent.parent
icons=r/'Resources/Assets.xcassets/AppIcon.appiconset'
for image in json.loads((icons/'Contents.json').read_text())['images']:
    if 'filename' not in image:continue
    raw=(icons/image['filename']).read_bytes();assert raw[:8]==b'\x89PNG\r\n\x1a\n'
    assert raw[25]==2, 'iOS icon must be RGB without alpha: '+image['filename']
    w,h=struct.unpack('!II',raw[16:24]);size=round(float(image['size'].split('x')[0])*float(image['scale'].removesuffix('x')))
    assert (w,h)==(size,size),(image['filename'],w,h,size)
assert (r/'Resources/AppIcon.icns').read_bytes()[:4]==b'icns'
print('Icon v2: generated iOS PNG dimensions and Mac icns verified')
