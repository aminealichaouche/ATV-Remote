# ATV Remote 0.3.12 stacked-volume placement

Version 0.3.12, build 15, moves stacked volume below Back/Home/Play, in the same volume area as Standard. Mute is centred in the left column; + and − stay together vertically in the right column. Both columns share available width. Navigation pad/touchpad and the horizontal Standard row keep their existing layout.

The former beside-pad layout and its horizontal fallback are removed. A single volumeControls call follows navigationControls. The saved layout preference, Samsung routing, 48-point minimum targets, 22-point symbols, single-line room header, crypto transfers and shortcuts are unchanged. Stacked volume is 58 points taller than the Standard row, so the existing vertical ViewThatFits uses a non-scrolling remote where it fits and scrolling when needed.

Native iOS 27 build-for-testing passed, exit 0 in 15.53 seconds. App and seven UI methods compile. The existing geometry helper now checks mute left and vertically centred, + above −, and the whole group below navigation actions. No simulator boot, UI test execution or visual verification occurred. [Compilation log](../audit/reproductions/atv-remote-0.3.12-ui-compile.log).

All 29 actual core/test inputs match the passing 0.3.11 run of 155 XCTest cases. Those tests were not rerun for this presentation change. [Reference verification](../audit/reproductions/atv-remote-0.3.12-core-reference.json).

The unsigned arm64 iPhoneOS archive/IPA passed validation with version 0.3.12/build 15, minimum iOS 27, stable bundle ID, valid ZIP, executable permissions and unsigned code inspection. All 12 packaged files match the archive and all 51 frozen inputs remain unchanged. Main remote icon, Shortcuts icon/preset, full-height Xfinity flick, Samsung Turn on and exact transfer dictionary are preserved. [Combined validation](../audit/reproductions/atv-remote-0.3.12-validation.json), [IPA metadata](../audit/reproductions/atv-remote-0.3.12-ipa-validation.json), [frozen inputs](../audit/reproductions/atv-remote-0.3.12-source-hashes.json).

Download [ATV-Remote-0.3.12-unsigned.ipa](../Build/ATV-Remote-0.3.12-unsigned.ipa), 5,533,206 bytes. SHA-256: `bb306f5d56166d1ee6080e475748f2ff343b308683d66c85284f0b36eeac1db7`. Actual placement and compact-height scrolling need an iPhone check; no TVs were contacted.
