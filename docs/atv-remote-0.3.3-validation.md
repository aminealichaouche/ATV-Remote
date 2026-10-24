# ATV Remote 0.3.3 icon application

The logo had previously been extracted into design assets but was not applied to the native app. The 0.3.2 IPA still contained the original dark monitor/D-pad icon. Version 0.3.3, build 6, replaces AppIcon with the blue gradient and white handheld remote.

The built-in image editor cleaned the previously AI-extracted logo and extended its blue background to a full square. This is an AI-prepared derivative, not a pixel-exact crop of the original upload. The original extracted PNG is retained. [Canonical artwork](../design/assets/atv-remote-app-icon-master.png), [exact prompt and tool details](../design/assets/atv-remote-app-icon-generation.json), [1024px asset](../App/Resources/Assets.xcassets/AppIcon.appiconset/RemoteIcon.png).

The source asset is a 1024×1024 opaque RGB PNG. CoreGraphics only resamples to the required size and encodes opaque sRGB; it no longer draws the previous icon. The build script always prepares the icon from the canonical master before archiving. [Apple’s icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons) calls for an opaque, full-bleed square; the operating system applies its corner shape.

App source is unchanged from 0.3.2. Room protection, fitted scrolling, connection rows, Home, Apps, power, pairing, and storage identities remain as documented in prior validation. This icon/packaging-only update does not rerun the 66 core tests; their unchanged source hashes are checked instead. No signing identity is included: install as an update with the same sideload signer.

## Validation

- **iPhone archive and unsigned IPA validation passed**: arm64, iPhoneOS, iOS 27 minimum, version 0.3.3/build 6, stable bundle ID `local.roomremote.ios`, no signature/profile, valid ZIP and executable permissions. Build inputs still match the frozen snapshot. All App/Sources hashes match 0.3.2. [Archive log](../audit/reproductions/atv-remote-0.3.3-device-archive.log), [IPA metadata](../audit/reproductions/atv-remote-0.3.3-ipa-validation.json), [source snapshot](../audit/reproductions/atv-remote-0.3.3-source-hashes.json).
- **Compiled icon audit passed**: the IPA’s icon PNGs and Assets.car exactly match the new archive; primary icon references resolve; compiled AppIcon metadata is opaque 1024px RGB/sRGB. Both raster hashes differ from the old monitor icon. The decoded 120px thumbnail was visually inspected and contains the new white remote on blue, with no old monitor artwork, padding, or baked outer corner mask. [Audit JSON](../audit/reproductions/atv-remote-0.3.3-icon-validation.json), [audit log](../audit/reproductions/atv-remote-0.3.3-icon-validation.log), [decoded compiled icon](../audit/reproductions/atv-remote-0.3.3-icon-120px.png).

Download [ATV-Remote-0.3.3-unsigned.ipa](../Build/ATV-Remote-0.3.3-unsigned.ipa), 5,181,790 bytes. SHA-256: `1a5977c435bac1db5a636355189d231838684f5ef1820e5e54ea7b9f7b3179de`. No physical iPhone installation or launcher-cache check was performed by this workspace.
