# ATV Remote 0.3.14 connection icons

Version 0.3.14, build 17, adds a TV symbol immediately to the right of the Samsung name and an Apple TV symbol immediately to the right of the Apple TV name in the bottom connection rows. The symbols occupy the same fixed 20-point column, followed by the aligned green/gray status dots. The existing right-side retry actions retain their reserved space. One-line names still truncate in the middle when needed.

Only a five-line Image block changed in RemoteScreen. The icons use the native `tv` and `appletv` symbols at 16 points in a secondary colour. They are hidden from VoiceOver because the existing name announcement already includes device type and connection state. Command routing and connection handling are unchanged. Independent source review found no blocking issue; native rendering was not exercised.

The native arm64 iPhoneOS Release archive compiled successfully, and the unsigned IPA passed ZIP, executable permission, version/build, bundle identity and signing checks. All 12 packaged files match the archive, and all 54 frozen inputs remain unchanged. The existing app/Shortcuts artwork, Xfinity preset, Samsung wake, stacked layout and live camera scanner remain; DEBUG fixtures are absent. [Combined validation](../audit/reproductions/atv-remote-0.3.14-validation.json), [IPA metadata](../audit/reproductions/atv-remote-0.3.14-ipa-validation.json), [archive log](../audit/reproductions/atv-remote-0.3.14-device-archive.log).

All 31 actual core/test inputs match the previously executed 0.3.13 suite of 171 passing cases. Tests were not rerun or added for this icon-only change. [Core reference](../audit/reproductions/atv-remote-0.3.14-core-reference.json). No camera, TV or native UI interaction was performed.

Download [ATV-Remote-0.3.14-unsigned.ipa](../Build/ATV-Remote-0.3.14-unsigned.ipa), 5,653,586 bytes, and sign it with your existing sideloading tool. SHA-256: `ddb2d317d814154a96292a99ad3002981a0227b7c7b869a1646bdd18af51bf55`.
