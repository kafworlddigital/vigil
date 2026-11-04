import subprocess,json,pathlib,sys,time,plistlib
app=pathlib.Path(sys.argv[1]).resolve()
prefix=(sys.argv[2]+'-') if len(sys.argv)>2 else ''
subprocess.run(['python3','scripts/check_frameworks.py',str(app)],check=True)
info=plistlib.loads((app/'Info.plist').read_bytes());bundle=info['CFBundleIdentifier']
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
flat=[dict(d,runtime=runtime) for runtime in sorted(devices,reverse=True) for d in devices[runtime] if d.get('isAvailable')]
pathlib.Path('proofs').mkdir(exist_ok=True)
def screenshot(udid,path):
 for attempt in range(2):
  try:
   subprocess.run(['xcrun','simctl','io',udid,'screenshot',path],check=True,timeout=90)
   data=pathlib.Path(path).read_bytes()
   assert len(data)>1000 and data[:8]==b'\x89PNG\r\n\x1a\n', 'No valid simulator screenshot'
   return
  except (subprocess.TimeoutExpired,subprocess.CalledProcessError):
   if attempt:raise
   time.sleep(3)

for family in ['iPhone','iPad']:
 device=next((d for d in flat if family in d['name']),None)
 if not device:raise SystemExit('No available '+family+' simulator')
 # Keith gets a fresh simulator. Macy installs a separate bundle into that already-proven OS.
 prior=pathlib.Path('proofs')/(family+'-launch.json')
 if prefix and prior.exists():
  udid=json.loads(prior.read_text())['udid']
 else:
  udid=subprocess.check_output(['xcrun','simctl','create','Vigil-'+family,device['deviceTypeIdentifier'],device['runtime']],text=True,timeout=60).strip()
 device=dict(device,udid=udid,state='Shutdown')
 if device['state']!='Booted':subprocess.run(['xcrun','simctl','boot',udid],check=True)
 subprocess.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True,timeout=600)
 # First-boot system services can remain busy after bootstatus completes.
 # Retry installation, then independently prove the launched PID survives.
 for installAttempt in range(2):
  try:
   subprocess.run(['xcrun','simctl','install',udid,str(app)],check=True,timeout=300)
   break
  except (subprocess.TimeoutExpired,subprocess.CalledProcessError):
   if installAttempt:raise
   time.sleep(10)
 subprocess.run(['xcrun','simctl','ui',udid,'appearance','dark'],check=True)
 subprocess.run(['xcrun','simctl','io',udid,'orientation','landscapeLeft'],check=False,capture_output=True)
 pid=None
 for launchAttempt in range(2):
  try:
   result=subprocess.check_output(['xcrun','simctl','launch','--terminate-running-process',udid,bundle,'--vigil-proof','--vigil-skip-intro'],text=True,timeout=120).strip()
   pid=int(result.rsplit(':',1)[1]);break
  except (subprocess.TimeoutExpired,subprocess.CalledProcessError):
   # A slow simctl reply is not a process proof. Read the actual launchd process independently.
   listing=subprocess.run(['xcrun','simctl','spawn',udid,'launchctl','list'],capture_output=True,text=True,timeout=30)
   matching=[line.split()[0] for line in listing.stdout.splitlines() if bundle in line and line.split()[0].isdigit()]
   if matching:pid=int(matching[0]);break
   if launchAttempt==1:raise
   time.sleep(5)
 assert pid is not None
 time.sleep(15)
 check=subprocess.run(['xcrun','simctl','spawn',udid,'launchctl','list'],capture_output=True,text=True,check=True)
 matching=[line for line in check.stdout.splitlines() if bundle in line and str(pid)==line.split()[0]]
 if not matching:raise SystemExit(f'{family} Release process did not survive 15 seconds')
 screenshot(udid,f'proofs/{prefix}{family}-Release.png')
 time.sleep(1)
 screenshot(udid,f'proofs/{prefix}{family}-animation-2.png')
 assert pathlib.Path(f'proofs/{prefix}{family}-Release.png').read_bytes()!=pathlib.Path(f'proofs/{prefix}{family}-animation-2.png').read_bytes(), 'Static phone face'
 pathlib.Path(f'proofs/{prefix}{family}-launch.json').write_text(json.dumps({'family':family,'simulator':device['name'],'udid':udid,'bundle':bundle,'pid':pid,'survivedSeconds':15,'process':matching,'configuration':'Release'},indent=2))
 # Capture actual production intro and Settings views in this fresh simulator.
 for screen in ['intro','settings','help']:
  subprocess.run(['xcrun','simctl','launch','--terminate-running-process',udid,bundle,'--vigil-screen',screen,'--vigil-skip-intro'],check=True,timeout=120)
  time.sleep(15 if screen=='settings' else 3)
  screenshot(udid,f'proofs/{prefix}{family}-{screen}.png')
 subprocess.run(['xcrun','simctl','terminate',udid,bundle],check=True,timeout=120)
 time.sleep(2)
 screenshot(udid,f'proofs/{prefix}{family}-home-icon.png')
 print(f'{family}: Release installed, launched and stayed up 15 seconds')
 subprocess.run(['xcrun','simctl','shutdown',udid],check=True)
