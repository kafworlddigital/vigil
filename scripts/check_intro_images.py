import pathlib,sys,struct,zlib
p=pathlib.Path(sys.argv[1]);images=[]
for n in range(1,7):
 f=p/f'Mac-intro-{n}.png';data=f.read_bytes()
 assert data.startswith(b'\x89PNG\r\n\x1a\n') and len(data)>12000,f'Blank/missing card {n}'
 w,h=struct.unpack('>II',data[16:24]);assert w>=720 and h>=900
 images.append(data)
assert len(set(images))==6,'Repeated intro card'
print('Six distinct live Mac intro screenshots saved; human visual review still required')
