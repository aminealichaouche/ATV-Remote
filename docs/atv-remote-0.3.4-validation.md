# ATV Remote 0.3.4 selection and Settings update

Version 0.3.4, build 7, addresses the status-row spacing, unnecessary reconnects, room context in Settings, and missing submenu back navigation.

## Changes

- The two TV status dots share a vertical column. TV names align immediately before them with six points of spacing. Conditional Connect, Enter code, and Review TV actions sit at the far right; reserved action width prevents connection changes from moving the name/dot columns. Connecting or awaiting TV approval shows a disabled action with a small spinner.
- Selecting the same TV returns before cancellation, epoch changes, or disconnect. Reselecting the same room with its saved pair also returns without changing sessions. Changing rooms reconnects only devices whose identities changed, including when rooms share one or both TVs. Reselecting a room after a temporary override still restores its saved pair. Explicit Connect and Re-pair retain their retry behavior.
- Settings uses the current room's name as its top title. Its first Apple TV and Samsung TV dropdowns are grouped under **Room group TVs**. Temporary overrides still require **Save this pair** to change saved assignments.
- Manage TVs, Manage rooms, and Transfer setup share the Settings navigation stack and have native top-left back buttons. Transfer opened from Manage TVs returns there first. Done closes Settings. Existing standalone sheets and pairing flows remain available.

The blue-and-white remote app icon is retained. Bundle ID, Keychain identity, device protocol client names, registry storage, and encrypted transfer format remain unchanged.

## Validation

- **72 actual-source core XCTest cases passed, zero failures**, using the macOS harness with symlinks to the app's source and test files. Six new room-selection planning cases cover unchanged selection, temporary overrides, shared TVs, navigation fallback, invalid references, and missing rooms. This is core-unit execution; it does not execute SwiftUI or connect to physical TVs. [Core test record](../audit/reproductions/atv-remote-0.3.4-core-tests.json), [test log](../audit/reproductions/atv-remote-0.3.4-core-tests.log).
- **Native simulator build-for-testing passed** for the updated app, unit tests, and all three UI test methods. The UI checks cover the room title/group header and submenu back paths. No simulator tests were executed or simulator boot requested during this run. Runtime UI validation remains for the iPhone test. [Compilation log](../audit/reproductions/atv-remote-0.3.4-ui-compile.log).
- **iPhone archive and unsigned package validation passed**: arm64, iPhoneOS, iOS 27 minimum, version 0.3.4/build 7, `local.roomremote.ios`, valid ZIP, preserved executable permissions, no signature/profile. Every packaged file matches the device archive. Frozen build inputs and actual core-test inputs still match their recorded hashes. [Archive log](../audit/reproductions/atv-remote-0.3.4-device-archive.log), [IPA metadata](../audit/reproductions/atv-remote-0.3.4-ipa-validation.json), [combined validation](../audit/reproductions/atv-remote-0.3.4-validation.json), [source snapshot](../audit/reproductions/atv-remote-0.3.4-source-hashes.json).
- **Icon package checks passed**: the compiled raster icons and Assets.car exactly match the verified remote icon from 0.3.3, and the primary icon references are unchanged. This is byte verification against the previously visually inspected icon; no new physical launcher inspection was performed. [Prior icon inspection](atv-remote-0.3.3-validation.md).

Download [ATV-Remote-0.3.4-unsigned.ipa](../Build/ATV-Remote-0.3.4-unsigned.ipa), 5,201,570 bytes. SHA-256: `dec04162b814d51085785ddf3779ead8537b96ea2b6a2f0a59249eb31d75e6ff`. Sign and install as an update using the existing sideloading identity when possible to retain setup. [Installation and physical checks](install-and-test.md).
