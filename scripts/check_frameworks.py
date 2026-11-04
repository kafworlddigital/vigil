import subprocess,sys,pathlib,plistlib
app=pathlib.Path(sys.argv[1])
mac=(app/'Contents').exists()
info=plistlib.loads((app/('Contents/Info.plist' if mac else 'Info.plist')).read_bytes())
executable=app/('Contents/MacOS' if mac else '')/info['CFBundleExecutable']
frameworks=app/('Contents/Frameworks' if mac else 'Frameworks')
pending=[executable];seen=set()
while pending:
 binary=pending.pop()
 if binary in seen:continue
 seen.add(binary)
 result=subprocess.check_output(['otool','-L',str(binary)],text=True)
 print(result)
 for line in result.splitlines()[1:]:
  dependency=line.strip().split(' (')[0]
  if dependency.startswith('@rpath/'):
   relative=dependency[len('@rpath/'):]
   embedded=frameworks/relative
   if relative.startswith('libswift') and pathlib.Path('/usr/lib/swift',relative).exists():continue
   if not embedded.exists():raise SystemExit('Missing embedded @rpath dependency: '+dependency)
   pending.append(embedded)
print('All @rpath dependencies embedded or supplied by the system Swift runtime')
