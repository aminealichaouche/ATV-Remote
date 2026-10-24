# ATV Remote 3.5.1 (47) validation

This release adds direct setup sharing through native SwiftUI ShareLink and typed CoreTransferable file representations. A prepared direct transfer supports iOS proximity AirDrop and the regular share sheet. The receiver opens a validated import preview without entering a phrase. A remembered optional Require a transfer phrase switch retains encrypted files and legacy code/phrase compatibility.

Direct `.atvsetup` files have their own exported UTI, MIME type and versioned envelope. AirDrop protects transport; direct files are clearly described as not password-protected. Exported temporary files use complete iOS file protection and are removed on explicit dismissal/reset. Direct import always requires review/confirmation and cannot send TV commands. The full incoming payload is validated before legacy rooms and credentials are discarded. Both TV brands now pair independently on each phone. Existing saved pairings are preserved; no automatic clearing or migration occurs.

The Samsung investigation confirmed that the previous sharing flow copied and reused the sender’s token and certificate pin. It did not establish that token sharing caused the reported occasional Allow prompts. Samsung’s Access Notification was already off on the user’s TV, so that setting is not a sufficient explanation. Previously imported Samsung access should be replaced using Re-pair on the receiving phone if prompts recur; this preserves TV profiles, stars and room assignments. Hardware confirmation remains necessary.

Keyboard, Apps and Samsung Sources labels/icons and minimum touch heights are 20% larger (12 → 14.4 points; 44 → 52.8 points), with Dynamic Type scaling and equal-width rows retained. Inputs is renamed Sources; its remote command is unchanged. Expanded remains the default, Auto stays hidden, and the reverted Wi-Fi/VPN detection remains absent. No dependency or vendor sources changed.

## Verification

The final simulator build and all 266 unit tests passed. New checks cover direct round-trip configuration/stars/MAC/layout without a phrase, stripping credentials and room groups, preserved local rooms and repeated-import idempotence, legacy encrypted phrase requirements, malformed/unknown/oversized/deeply nested direct files, and matching exported file types.

Four final UI cases passed: phrase-free stars export/import and cold relaunch, navigation switching/retry, Expanded/Alternate layout persistence, and protected sharing cancellation/phrase entry. Three passed in the full release run; the corrected native popover case passed in a focused rerun on unchanged production sources. The signed archive verifies strictly and embeds its provisioning profile; both packages register the direct and protected document types, match version 3.5.1/build 47, and exclude DEBUG fixtures. Source hashes match the final app code. Release artifact verification is recorded in the linked machine-readable report. The earlier UI pass covered legacy selective review and stars/layout re-export. The first native-sharing UI test assumed a Close button; iOS 27 exposes a floating popover instead. The test was updated to dismiss the observed floating popover by tapping outside it, without changing production sharing behavior.

Physical bring-phones-together AirDrop, cross-device file routing, and independent Samsung authorization still need testing on two iPhones and the actual TV. Simulator tests do not establish those hardware behaviors. Both iPhones must install this version for the new direct file type.

## Artifacts

- [Unsigned 3.5.1 IPA](../Build/ATV-Remote-3.5.1-unsigned.ipa), for sideload signing; arm64, minimum iOS 27, DEBUG fixtures excluded.
- [Signed 3.5.1 TestFlight archive](../Build/ATVRemote-3.5.1-TestFlight.xcarchive), using the existing bundle ID and the saved developer team. Prepared, not uploaded.
- [Combined verification evidence](../audit/reproductions/atv-remote-3.5.1-validation.json).
- [AirDrop and import instructions](share-pairings.md).

Primary references: [Apple’s proximity sharing developer guidance](https://developer.apple.com/videos/play/wwdc2023/102/), [AirDrop setup and receiving requirements](https://support.apple.com/en-us/119857), and [AirDrop transport security](https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web).
