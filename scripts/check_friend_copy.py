"""Fail if personal names or in-jokes could reach the friend edition's screens."""
import pathlib,re,sys
bad=re.compile(r'\b(Keith|Macy|drifter|Sunday)\b',re.I)
problems=[]
# Strings swapped at runtime for the friend edition (see VigilHelp.topics and VigilCopy.parkingHeader).
handled=["Macy's edition has separate data and per-device access","header: String = \"Drifter-in-chief"]
for path in list(pathlib.Path('App').rglob('*.swift'))+list(pathlib.Path('Core').rglob('*.swift')):
    for n,line in enumerate(path.read_text().splitlines(),1):
        code=line.split('//')[0]
        if any(h in line for h in handled):continue
        for literal in re.findall(r'"((?:[^"\\]|\\.)*)"',code):
            if bad.search(literal):
                # Allowed only where the friend edition picks different wording.
                if 'VigilEdition.friend' in line or 'friend ?' in line or path.name=='VigilAI.swift' and 'static var' in line:continue
                if 'VigilEdition.macy' in line or '"keith"' in literal.lower() or literal in ('keith','macy'):continue
                problems.append(f'{path}:{n}: {literal[:80]}')
if problems:
    print('\n'.join(problems));sys.exit(1)
print('Friend-edition wording check passed')
