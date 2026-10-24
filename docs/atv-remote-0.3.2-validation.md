# ATV Remote 0.3.2 room protection

The user paired Family Room devices while Living Room was selected and found that Living Room’s saved pair was replaced. Both Add paths called `saveAssignments()` after changing the active selection, copying both active TV IDs into the room. Version 0.3.2 removes that automatic save.

Adding or rediscovering a TV saves its profile and selects it temporarily for pairing. Existing full and partial room groups retain their exact saved assignments. Explicit **Save this pair** and room-editor Save still change room assignments.

For the user-approved first-setup exception, a transient initial-setup session starts only for a fully empty room and a truly new device. It can assign the first new Samsung and Apple TV, in either order, while the saved room still matches that session’s expected state. Only the newly added kind is assigned; another active TV is never copied into the room. Additional same-kind devices and duplicate additions end the session, so later Family Room devices cannot accidentally complete an older room. Manual selections/room changes, explicit saves, removal, re-pair/cancel, imports/recovery changes, and background also end the session. After restart or interrupted initial setup, use an explicit room save to add the remaining device.

The registry schema, app/bundle identifier, pairing keys, encrypted transfer format, and room data remain compatible with previous builds. Version 0.3.2 is build 5 and retains the 0.3.1 Home-grid behavior and 0.3 Apps/power/layout changes. Install as an update with the same signing identity.

## Remote screen changes

The remote chooses a non-scrolling content layout when its full vertical size fits the available screen, using [Apple’s ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits). If it does not fit, the same controls appear in a vertical ScrollView with [size-based bounce](https://developer.apple.com/documentation/swiftui/scrollbouncebehavior/basedonsize). This preserves access on smaller screens and with larger text, without dragging or bouncing a fully visible remote.

Immediately below Keyboard / Apps-or-Inputs / Power are compact rows for the selected Apple TV and Samsung. Each has its name on the left, a green dot when connected or gray dot otherwise, and Connect when retry is available. PIN and certificate-review states keep Enter code / Review TV; pending connection or TV approval disables Connect with progress so it cannot cancel setup accidentally. Full names and state are available to VoiceOver. Main feedback text, duplicate gray device captions, and touchpad helper text were removed. Errors remain available in existing alerts, Apps error UI, and detailed Settings.

## Validation

**66 current core XCTest cases passed**, including 11 new room-protection regressions, using actual app source/test symlinks on macOS with local dependencies. No source changed during the run. [Log](../audit/reproductions/atv-remote-0.3.2-core-tests.log), [test totals and hashes](../audit/reproductions/atv-remote-0.3.2-core-tests.json). The production RemoteStore integration was compiled in that run. No physical TV, live Keychain, or UI execution occurred.

The UI received a static source review for 320/390-point widths, 44-point minimum action targets, name truncation, and state-specific retries. Native visual behavior is not yet verified; prior simulator testmanagerd startup failure is recorded in [0.3 validation](atv-remote-0.3-validation.md), and no UI pass is claimed.

**Unsigned iPhone archive and package validation passed**, including compilation of the new native UI: arm64, iPhoneOS, iOS 27 minimum, version 0.3.2/build 5, ATV Remote visible name, no code signature/provisioning profile, valid ZIP, and executable permissions preserved. Frozen build inputs and tested core sources match their recorded hashes after completion. [Archive log](../audit/reproductions/atv-remote-0.3.2-device-archive.log), [IPA metadata](../audit/reproductions/atv-remote-0.3.2-ipa-validation.json), [source snapshot](../audit/reproductions/atv-remote-0.3.2-source-hashes.json).

Download [ATV-Remote-0.3.2-unsigned.ipa](../Build/ATV-Remote-0.3.2-unsigned.ipa), 4,097,990 bytes. SHA-256: `14600e3624adc7469d5650b247c8b58a48f6b0dcc16a0bc3b677582a44ca1ef9`. Sign/install as an update with the existing sideloading tool. This change cannot infer or recover assignments overwritten by an earlier version; it preserves the current saved rooms and prevents future automatic replacement.
