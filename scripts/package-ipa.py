#!/usr/bin/env python3
"""Package a verified unsigned iPhone archive for a user-selected sideload signer."""
from pathlib import Path
import hashlib
import json
import plistlib
import stat
import subprocess
import zipfile
import argparse

root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--expected-bundle-id', default='local.roomremote.ios')
parser.add_argument('--archive', type=Path, default=root/'Build/RoomRemote.xcarchive')
parser.add_argument('--output-name')
args=parser.parse_args()
app=args.archive/'Products/Applications/RoomRemote.app'
if not app.is_dir(): raise SystemExit('Build the Release iPhone archive first.')
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']==args.expected_bundle_id, 'Archive does not match the explicitly expected bundle identity.'
assert info['CFBundleDisplayName']=='ATV Remote'
assert info['CFBundlePackageType']=='APPL'
assert info.get('CFBundleSupportedPlatforms')==['iPhoneOS'], 'Do not package a simulator build.'
binary=app/info['CFBundleExecutable']
arches=subprocess.check_output(['lipo','-archs',str(binary)],text=True).strip()
assert arches=='arm64', arches
assert not (app/'embedded.mobileprovision').exists(), 'Expected an unsigned archive.'
assert not (app/'_CodeSignature').exists(), 'Expected an unsigned archive.'
compiled_assets=json.loads(subprocess.check_output(['xcrun','assetutil','--info',str(app/'Assets.car')],text=True))
assert b'square.stack.3d.up' in binary.read_bytes(), 'The outline Shortcuts symbol is missing.'
assert b'Restart Xfinity Stream' in binary.read_bytes(), 'The bundled Xfinity preset is missing.'
assert b'Restart current app' in binary.read_bytes(), 'The chosen-app restart shortcut is missing.'
filename=args.output_name or f"ATV-Remote-{info['CFBundleShortVersionString']}-unsigned.ipa"
assert Path(filename).name == filename and filename.endswith('.ipa')
destination=root/'Build'/filename
with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for file in sorted(app.rglob('*')):
        if not file.is_file(): continue
        arcname='Payload/RoomRemote.app/'+str(file.relative_to(app))
        entry=zipfile.ZipInfo.from_file(file,arcname)
        entry.compress_type=zipfile.ZIP_DEFLATED
        z.writestr(entry,file.read_bytes())
with zipfile.ZipFile(destination) as z:
    assert z.testzip() is None
    plist_name='Payload/RoomRemote.app/Info.plist'
    assert plistlib.loads(z.read(plist_name))['MinimumOSVersion']=='27.0'
    mode=z.getinfo('Payload/RoomRemote.app/RoomRemote').external_attr>>16
    assert mode & stat.S_IXUSR, 'Executable permission missing in IPA.'
digest=hashlib.sha256(destination.read_bytes()).hexdigest()
record={'file':destination.name,'sha256':digest,'bytes':destination.stat().st_size,'architecture':arches,'platform':'iPhoneOS','minimum_ios':info['MinimumOSVersion'],'bundle_id':info['CFBundleIdentifier'],'display_name':info['CFBundleDisplayName'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'signed':False,'bundled_shortcuts':['Restart Xfinity Stream','Restart current app'],'shortcuts_icon_present':True,'shortcuts_icon_style':'transparent SF Symbol outline','installation':'Sign with the user-selected sideloading tool before installation.'}
(root/'Build/ipa-validation.json').write_text(json.dumps(record,indent=2)+'\n')
(root/'Build/SHA256.txt').write_text(digest+'  '+destination.name+'\n')
print(json.dumps(record,indent=2))
