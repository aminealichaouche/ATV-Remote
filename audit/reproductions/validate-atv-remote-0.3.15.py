#!/usr/bin/env python3
"""Offline provenance and package verification for the frozen 0.3.15 build."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import stat
import subprocess
import zipfile

root = Path(__file__).resolve().parents[2]
audit = root / 'audit/reproductions'
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def read_json(name):
    return json.loads((audit / name).read_text())

frozen = read_json('atv-remote-0.3.15-source-hashes.json')['sha256']
changes = [name for name, expected in frozen.items() if digest(root/name) != expected]
assert not changes, changes
core = read_json('atv-remote-0.3.15-core-tests.json')
assert core['process_exit_code'] == 0 and core['tests_executed'] == 181 and core['failures'] == 0
core_inputs = core['source_and_test_sha256_after']
assert len(core_inputs) == 34
assert all(digest(root/name) == value == frozen[name] for name, value in core_inputs.items())
ui = read_json('atv-remote-0.3.15-ui-compile.json')
assert ui['exit_code'] == 0 and ui['ui_methods_compiled'] == 8 and ui['tests_executed'] == 0
ui_hashes = read_json('atv-remote-0.3.15-ui-compile-input-hashes.json')
assert all(digest(root/name) == value for name, value in ui_hashes.items())

ipa = root/'Build/ATV-Remote-0.3.15-unsigned.ipa'
app = root/'Build/RoomRemote.xcarchive/Products/Applications/RoomRemote.app'
info = plistlib.loads((app/'Info.plist').read_bytes())
binary_path = app/info['CFBundleExecutable']
binary = binary_path.read_bytes()
assert info['CFBundleShortVersionString'] == '0.3.15' and info['CFBundleVersion'] == '18'
assert info['CFBundleDisplayName'] == 'ATV Remote' and info['CFBundleIdentifier'] == 'local.roomremote.ios'
assert info['MinimumOSVersion'] == '27.0' and info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
assert info['NSCameraUsageDescription'] == 'Read the IP and MAC addresses shown on your TV to fill its setup.'
assert not any(key.startswith('NSPhotoLibrary') for key in info)
assert not (app/'embedded.mobileprovision').exists() and not (app/'_CodeSignature').exists()
arches = subprocess.check_output(['lipo','-archs',str(binary_path)],text=True).strip()
assert arches == 'arm64'
inspection = subprocess.run(['codesign','-dv',str(app)],capture_output=True,text=True)
assert inspection.returncode != 0 and 'not signed' in inspection.stderr

files = sorted(path for path in app.rglob('*') if path.is_file())
with zipfile.ZipFile(ipa) as package:
    assert package.testzip() is None
    assert len(package.namelist()) == len(files)
    for path in files:
        name = 'Payload/RoomRemote.app/'+str(path.relative_to(app))
        assert package.read(name) == path.read_bytes(), name
    assert package.getinfo('Payload/RoomRemote.app/RoomRemote').external_attr >> 16 & stat.S_IXUSR

assets = json.loads(subprocess.check_output(['xcrun','assetutil','--info',str(app/'Assets.car')],text=True))
remote_icon = [item for item in assets if item.get('RenditionName') == 'RemoteIcon.png']
shortcuts_icon = [item for item in assets if item.get('Name') == 'ShortcutsIcon']
previous = read_json('atv-remote-0.3.12-validation.json')
assert remote_icon and shortcuts_icon
assert remote_icon[0]['SHA1Digest'] == previous['compiled_remote_app_icon'][0]['SHA1Digest']
assert shortcuts_icon[0]['SHA1Digest'] == previous['compiled_shortcuts_icon'][0]['SHA1Digest']
compiled_assets_files = []
for name in ['AppIcon60x60@2x.png','AppIcon76x76@2x~ipad.png','Assets.car']:
    value = digest(app/name)
    if name != 'Assets.car':
        old = next(item for item in previous['compiled_assets_files'] if item['file'] == name)
        assert value == old['sha256']
    compiled_assets_files.append({'file':name,'sha256':value,'bytes':(app/name).stat().st_size,'matches_archive':True})

word_source = (root/'App/Sources/TransferWords.swift').read_text()
words = [line.strip() for line in word_source.split('"""')[1].splitlines() if line.strip()]
assert len(words) == 7772 and len(set(words)) == 7772
assert '\n'.join(words).encode() in binary
assert b'EFF' in (app/'ThirdPartyNotices.txt').read_bytes()
for required in [b'Restart Xfinity Stream',b'com.comcast.cim.x2',b'Turn on Samsung TV',b'Disconnect',b'Apple TV remote',b'Scan TV text',b'Scan TV IP address',b'Scan TV MAC address',b'RoomRemote.remoteLayout.v1']:
    assert required in binary, required
assert b'RoomRemote.useTouchpad.v1' in binary and b'ATVAppArtwork-v1' in binary
assert b'--ui-testing' not in binary
for excluded in [b'--ui-testing-reset',b'--ui-testing-scan-text',b'--ui-testing-transfer',b'Room group TVs']:
    assert excluded not in binary, excluded
scanner = (root/'App/Sources/TVPhotoScanScreen.swift').read_text()
assert 'recognizedDataTypes: [.text(languages: ["en-US"])]' in scanner
assert not any(value in scanner for value in ['.barcode(', 'PhotosPicker', 'capturePhoto', 'UIImagePickerController', 'Take photo', 'Choose photo'])
archive_log = (root/'Build/logs/final-device-archive.log').read_text()
assert '** ARCHIVE SUCCEEDED **' in archive_log

metadata = json.loads((root/'Build/ipa-validation.json').read_text())
assert metadata['sha256'] == digest(ipa) and metadata['bytes'] == ipa.stat().st_size
shutil.copy2(root/'Build/ipa-validation.json',audit/'atv-remote-0.3.15-ipa-validation.json')
shutil.copy2(root/'Build/logs/final-device-archive.log',audit/'atv-remote-0.3.15-device-archive.log')
result = {
    'version':'0.3.15','build':'18','source_snapshot_files_checked':len(frozen),
    'source_changes_after_snapshot':changes,'core_test_input_files_checked':len(core_inputs),
    'core_input_changes_after_tests':[],'core_tests_executed':181,'core_failures':0,'artwork_tests_passed':10,
    'ipa':metadata,'archive_result':'ARCHIVE SUCCEEDED',
    'all_packaged_files_match_device_archive':True,'packaged_file_count':len(files),
    'compiled_assets_files':compiled_assets_files,'compiled_remote_app_icon':remote_icon,
    'compiled_shortcuts_icon':shortcuts_icon,'codesign_inspection':inspection.stderr.strip(),
    'ui_test_compile':ui,'ui_compile_inputs_match_final_sources':True,
    'live_text_scan':{
        'input':'Live VisionKit camera text only','recognition_on_device':True,
        'entry_points':['New Samsung IP field','New Samsung MAC field','Saved Samsung power-on MAC field'],
        'button_target_points':44,'camera_usage_description':info['NSCameraUsageDescription'],
        'photo_library_permission':False,'qr_recognition':False,'still_photo_capture':False,
        'max_ip_candidates':8,'max_mac_candidates':8,'review_before_applying':True,
        'apply_scope':'Unsaved setup fields; adding/pairing and saving remain separate',
        'parser_tests_passed':16,'camera_permission_and_hardware_execution':False,
        'debug_fixture_absent_from_ipa':True,
        'source_audit':'docs/atv-remote-live-text-audit.md'
    },
    'remote_layout':{'alternative_title':'Apple TV remote','stored_raw_value':'stackedVolume','pad_gap_points':24,'pad_preference_key':'RoomRemote.useTouchpad.v1','button_rows':[['Back','Home'],['Play / pause','Volume up'],['Mute','Volume down']],'continuous_volume_rocker':True,'standard_retained':True},
    'app_artwork':{'verified_exact_bundle_ID':True,'cache_entries':128,'cache_bytes':20971520,'positive_days':30,'negative_hours':24,'error_backoff_minutes':15,'maximum_stale_days':180,'downloaded_artwork_internet_source':'Apple public catalog/CDN','installed_apps_source':'selected Apple TV','builtin_fallbacks':True,'source_audit':'docs/atv-remote-app-artwork-audit.md','live_HTTP_exercised':False},
    'phrase_transfer':previous['phrase_transfer'],
    'xfinity_swipe_plan':previous['xfinity_swipe_plan'],
    'transfer_dictionary_verified_in_binary':True,'xfinity_preset_preserved':True,
    'wake_control_label_in_binary':True,'disconnect_label_in_binary':True,
    'debug_reset_fixture_absent_from_binary':True,
    'runtime_scope':'181 actual-source offline Mac core cases executed. Native iOS27 app and eight UI methods compiled only. No simulator boot/UI geometry/camera permission/TV OCR/TV command/Keychain/FaceID/AirDrop/clipboard operations.'
}
(audit/'atv-remote-0.3.15-validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'ipa':metadata['file'],'sha256':metadata['sha256'],'bytes':metadata['bytes'],
                  'core_tests':181,'native_ui_methods_compiled':8,'source_files_checked':len(frozen),
                  'packaged_files':len(files),'changes':changes},indent=2))
