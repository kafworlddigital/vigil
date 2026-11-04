"""Keep the intro honest about its feature controls and actual production character."""
from pathlib import Path
r=Path(__file__).resolve().parent.parent
s=(r/'App/VigilIntro.swift').read_text()
assert 'Image(systemName:' not in s,'Intro must use character art, never generic symbols'
for token in ['FaceView(animator:','Teardrop.path','CompanionControls()','intro.skip','intro.next','vigil.intro.v2.completed','No setup']:
 assert token in s,token
app=(r/'App/VigilApp.swift').read_text()
assert 'Button("Show intro again")' in app and 'CompanionControls()' in app
assert 'VigilAskView()' in app
for token in ['nameKey','colourKey','nudgeKey','cornerKey']:
 assert '@AppStorage(CompanionPreferences.'+token+')' in s
assert 'CURRENT_PROJECT_VERSION: \'5\'' in (r/'project.yml').read_text()
print('Intro v2: real face + real cursor art, immediate saved controls, replay and Ask entry point')
