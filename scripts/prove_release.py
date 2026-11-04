import subprocess,json,pathlib,sys,time,plistlib
app=pathlib.Path(sys.argv[1]).resolve()
subprocess.run(['python3','scripts/check_frameworks.py',str(app)],check=True)
info=plistlib.loads((app/'Info.plist').read_bytes());bundle=info['CFBundleIdentifier']
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
flat=[d for runtime in sorted(devices,reverse=True) for d in devices[runtime] if d.get('isAvailable')]
pathlib.Path('proofs').mkdir(exist_ok=True)
for family in ['iPhone','iPad']:
 device=next((d for d in flat if family in d['name']),None)
 if not device:raise SystemExit('No available '+family+' simulator')
 udid=device['udid']
 if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',udid],check=True)
 subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True,timeout=600)
 subprocess.run(['xcrun','simctl','install',udid,str(app)],check=True,timeout=90)
 subprocess.run(['xcrun','simctl','ui',udid,'appearance','dark'],check=True)
 subprocess.run(['xcrun','simctl','io',udid,'orientation','landscapeLeft'],check=False,capture_output=True)
 result=subprocess.check_output(['xcrun','simctl','launch',udid,bundle,'--vigil-proof'],text=True,timeout=60).strip()
 pid=int(result.rsplit(':',1)[1]);time.sleep(15)
 check=subprocess.run(['xcrun','simctl','spawn',udid,'launchctl','list'],capture_output=True,text=True,check=True)
 matching=[line for line in check.stdout.splitlines() if bundle in line and str(pid)==line.split()[0]]
 if not matching:raise SystemExit(f'{family} Release process did not survive 15 seconds')
 subprocess.run(['xcrun','simctl','io',udid,'screenshot',f'proofs/{family}-Release.png'],check=True)
 time.sleep(1)
 subprocess.run(['xcrun','simctl','io',udid,'screenshot',f'proofs/{family}-animation-2.png'],check=True)
 assert pathlib.Path(f'proofs/{family}-Release.png').read_bytes()!=pathlib.Path(f'proofs/{family}-animation-2.png').read_bytes(), 'Static phone face'
 pathlib.Path(f'proofs/{family}-launch.json').write_text(json.dumps({'family':family,'simulator':device['name'],'udid':udid,'bundle':bundle,'pid':pid,'survivedSeconds':15,'process':matching,'configuration':'Release'},indent=2))
 print(f'{family}: Release installed, launched and stayed up 15 seconds')
 subprocess.run(['xcrun','simctl','shutdown',udid],check=True)
