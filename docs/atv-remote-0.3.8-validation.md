# ATV Remote 0.3.8 room selectors and disconnect

Version 0.3.8, build 11, names the Settings TV section after the selected room, such as **Living Room**. Both selectors now use the same explicit stacked layout: TV type above the selected name and address, with equal trailing chevron columns. Duplicate device-detail rows are removed. Room-name casing is preserved, including custom names.

Each connection line places its state on the left and its action on the right. **Connected → Disconnect** changes to **Disconnected → Connect** when tapped. Pending connection/approval uses Cancel; PIN and certificate review retain their setup actions. Settings stays open so reconnect is available on the same line.

## Behavior and source review

Disconnect advances only the affected kind's selection epoch, cancels its connection/commands and applicable Apple tools, and closes that driver. Older callbacks cannot restore that kind's prior connection state. Quick Disconnect then Connect uses the existing serialized task chain and closes the old driver before opening a new session. Review found no new lifecycle issue; those task/transport conclusions come from source inspection, not live driver tests.

Pairing credentials, selected IDs, room assignments, app stars, and Samsung wake MAC are preserved. `ConnectionIntent` records a transient hold by saved TV ID. Automatic foreground and selection connections respect that hold, including through different rooms sharing the TV. Explicit Connect, Add and pair, or a successful Re-pair releases the requested TV's hold. Samsung wake does not release it. A fresh app launch resumes normal automatic connections. Background cleanup does not create a manual hold.

Same-TV and unchanged-room selection guards still return before cancellation or connection work. Disconnecting one kind leaves the other kind's transport and commands alone. Existing Settings management submenus use the shared NavigationStack with native Back. Main-screen compact connection dots remain in their existing aligned layout.

## Validation

- **140 actual-source core XCTest cases passed, zero failures**, process exit 0. Seven new policy cases cover per-TV holds, independent devices, shared-room IDs, and explicit release. All 25 symlinked production/test inputs matched their frozen hashes before and after execution. [Core record](../audit/reproductions/atv-remote-0.3.8-core-tests.json), [test log](../audit/reproductions/atv-remote-0.3.8-core-tests.log).
- **Native iOS 27 simulator build-for-testing passed**, exit 0 in 23.25 seconds. App, unit tests, and all five UI methods compiled. Existing UI methods now assert exact Living Room and custom room section labels. This was compilation only: no simulator boot or UI test execution. [Compilation log](../audit/reproductions/atv-remote-0.3.8-ui-compile.log).
- **Unsigned iPhone archive and package validation passed**: arm64, iPhoneOS, minimum iOS 27, version 0.3.8/build 11, stable `local.roomremote.ios`, valid ZIP, executable permissions, and unsigned code inspection. All 12 packaged files match the archive. All 46 frozen source/test/resource/build inputs remain unchanged. Main icon raster hashes and compiled digest match the previous remote icon, and the bundled Shortcuts icon, Xfinity preset, and Samsung Turn on label are present. The previous Room group TVs label is absent from the compiled executable. [Archive log](../audit/reproductions/atv-remote-0.3.8-device-archive.log), [IPA metadata](../audit/reproductions/atv-remote-0.3.8-ipa-validation.json), [combined validation](../audit/reproductions/atv-remote-0.3.8-validation.json), [frozen inputs](../audit/reproductions/atv-remote-0.3.8-source-hashes.json).

No real TVs, live Keychain operations, or remote commands were contacted. The new policy tests do not execute RemoteStore's asynchronous task chain or real driver shutdown. Settings rendering, long names, largest accessibility fonts, and actual disconnect/reconnect need an iPhone check. Use [installation and hardware checks](install-and-test.md): disconnect each TV, verify the other stays connected, switch rooms and foreground, then Connect again without re-pairing.

Download [ATV-Remote-0.3.8-unsigned.ipa](../Build/ATV-Remote-0.3.8-unsigned.ipa), 5,478,292 bytes. SHA-256: `c8ee1158b9d19fb85e483d3b992fa3a4eb0402ce576ba652d785afd421f31712`. Sign and install as an update using the existing sideload identity when possible.
