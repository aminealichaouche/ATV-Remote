# ATV Remote 0.3.33 new logo

Version 0.3.33, build 36, uses the user-provided diagonal white remote on blue. The matching original Remote_Icon_Top_Right.png was visually identified in Downloads and copied byte-for-byte to the canonical 1254px square master. CoreGraphics resamples it to an opaque sRGB 1024px icon. No AI redraw, rotation, crop or rounded-corner mask is applied. The previous master is retained as design/assets/atv-remote-app-icon-0.3.32.png. [New master](../design/assets/atv-remote-app-icon-master.png), [provenance](../design/assets/atv-remote-app-icon-generation.json).

Both unsigned arm64 iPhoneOS archives passed and each IPA byte-matches all 12 archive files. AppIcon references resolve, the compiled asset is opaque RGB/sRGB 1024px, the compiled 120px icon differs from the previous release and was decoded and visually reviewed. Both bundle variants have the same icon. ZIP integrity and unsigned-profile checks passed. [Icon validation](../audit/reproductions/atv-remote-0.3.33-icon-validation.json), [compiled preview](../audit/reproductions/atv-remote-0.3.33-icon-120px.png).

All app and test Swift source hashes match 0.3.32. Its 98 native and four simulator checks were not rerun for this icon-only update. Manage TV, complete setup transfer, stars, preferences and remote/network logic are unchanged.

The existing Xcode project now uses the saved bundle ID and developer team; those settings were preserved. The primary IPA uses that configured identity. A second IPA uses local.roomremote.ios to match earlier sideload builds. It was built with a command-line override without changing the project. Package verification accepts an explicitly expected bundle ID and checks the archived value; it does not silently accept any identity.

- [Current Xcode identity IPA](../Build/ATV-Remote-0.3.33-unsigned.ipa)
- [Previous sideload identity IPA](../Build/ATV-Remote-0.3.33-legacy-bundle-unsigned.ipa)

Sign either unsigned package with your sideloading tool. Use the previous-identity variant when updating the earlier local.roomremote.ios installation. The different bundle IDs have separate app containers; changing to the current Xcode identity does not automatically copy setup. Full setup can be transferred using the 0.3.32 sharing feature.
