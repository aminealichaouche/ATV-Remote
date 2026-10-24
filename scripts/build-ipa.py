#!/usr/bin/env python3
"""Build an unsigned iPhone test IPA using the vendored dependencies."""
from pathlib import Path
import subprocess
import sys
import json

root = Path(__file__).resolve().parents[1]
logs = root / 'Build/logs'
logs.mkdir(parents=True, exist_ok=True)
subprocess.run([
    'swift', str(root / 'scripts/create-icon.swift'),
    str(root / 'design/assets/atv-remote-app-icon-master.png'),
    str(root / 'App/Resources/Assets.xcassets/AppIcon.appiconset/RemoteIcon.png'),
], check=True)
subprocess.run([sys.executable, str(root / 'scripts/generate-project.py')], check=True)
command = [
    'xcodebuild', '-project', str(root / 'App/RoomRemote.xcodeproj'),
    '-scheme', 'RoomRemote', '-configuration', 'Release',
    '-destination', 'generic/platform=iOS',
    '-derivedDataPath', '/private/tmp/roomremote-test-device-build',
    '-disableAutomaticPackageResolution',
    '-archivePath', str(root / 'Build/RoomRemote.xcarchive'),
    '-jobs', '4', 'archive',
    'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
    'SWIFT_COMPILATION_MODE=incremental', 'SWIFT_OPTIMIZATION_LEVEL=-Onone',
]
# This first hardware-test build uses Release conditions with optimization off.
# No DEBUG fixtures or UI-test reset code are compiled into the IPA.
log = logs / 'final-device-archive.log'
with log.open('w') as output:
    result = subprocess.run(command, cwd=root, stdout=output, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f'Archive failed ({result.returncode}); inspect {log}')
# The bundle ID comes from App/Signing.xcconfig plus the untracked local override.
settings = json.loads(subprocess.check_output([
    'xcodebuild', '-project', str(root / 'App/RoomRemote.xcodeproj'), '-target', 'RoomRemote',
    '-configuration', 'Release', '-showBuildSettings', '-json'
], cwd=root))
bundle_id = settings[0]['buildSettings']['PRODUCT_BUNDLE_IDENTIFIER']
subprocess.run([sys.executable, str(root / 'scripts/package-ipa.py'),
                '--expected-bundle-id', bundle_id], check=True)
