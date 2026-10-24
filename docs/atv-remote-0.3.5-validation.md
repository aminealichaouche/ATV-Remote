# ATV Remote 0.3.5 app stars and grouping

Version 0.3.5, build 8, adds independently saved app stars for each Apple TV, groups its installed apps, and lets the user copy stars from another saved Apple TV.

## Behavior

Apps shows **Starred**, then **Downloaded**, then **Included**, omitting empty sections. The star button and launch button are separate 44-point targets. An app moves into Starred without remaining duplicated in its original section. Section ordering uses current display names with the bundle identifier as a deterministic tie-breaker.

Included uses an exact, case-sensitive allowlist from [Apple's published tvOS bundle IDs](https://support.apple.com/guide/deployment/bundle-ids-for-apple-tv-apple-apps-depcdd66fe58/web). Companion supplies names and identifiers without installation-origin metadata. This classification is an inference from the primary reference; unknown identifiers remain Downloaded. The [classification audit](atv-remote-app-classification-audit.md) documents the identifiers, protocol response, conservative fallback, and source links. The frozen vendor adapter is unchanged.

Stars are local preferences keyed by saved Apple TV identity and exact bundle ID. Room changes, names, re-pairing, app relaunch, and storage recovery preserve them. Removing a TV clears its preferences. Older registries migrate without changing devices, rooms, or pairing identities. Empty/missing favorites fields decode as empty. Preferences remain bounded and reject invalid owners, malformed app IDs, and excessive entries.

**Apps → Import stars from another Apple TV** opens a source dropdown with a native back button. The destination list must load successfully first. The screen previews saved-star and installed-match counts; confirmation adds the source's IDs to the destination's existing stars. The source is unchanged and need not be online. Imported stars are independent after copying. Apps not returned by the destination are hidden; installing one later and reloading makes it appear starred. No remembered source names, synthetic rows, or missing-app launch targets are created.

Stars are published only after an atomic registry write succeeds. A save failure preserves the previous registry and displays the error. List, toggle, import, and launch operations remain scoped to the current Apps presentation and selected Apple TV. Reload/list errors do not erase preferences or make an unsuccessful inventory eligible for import.

The app icon, bundle ID, Keychain identity, device client names, registry path, and encrypted TV/room/pairing transfer format remain unchanged. That sharing file does not include local app-star preferences. All 0.3.4 connection, room, and Settings changes are retained.

## Validation

- **92 actual-source core XCTest cases passed, zero failures**: the prior 72 plus 12 registry favorites tests and eight app-library tests. Coverage includes backward decoding, per-TV independence, exact IDs instead of display names, idempotent merge with latent missing apps, source preservation, invalid owners, limits, device removal, real registry-file save/load and interrupted-import recovery, installed-only sections, later installations, exact included classification, and ordering/deduplication. All 19 harness source/test hashes stayed unchanged. [Test record](../audit/reproductions/atv-remote-0.3.5-core-tests.json), [test log](../audit/reproductions/atv-remote-0.3.5-core-tests.log).
- **Native simulator build-for-testing passed**, exit 0 in 26.55 seconds. The new source and unit tests, app, and existing three UI test methods compile and link. No UI tests were executed, and no simulator boot was requested. These existing UI methods cover Settings navigation, room setup, and transfer; they do not verify star taps at runtime. [Compilation log](../audit/reproductions/atv-remote-0.3.5-ui-compile.log).
- **iPhone archive and unsigned IPA validation passed**: arm64, iPhoneOS, iOS 27 minimum, version 0.3.5/build 8, stable bundle ID, valid ZIP, preserved executable permissions, and no signature/profile. Every packaged file matches the device archive. All 31 recorded source/test/build inputs and 19 core-harness inputs match their frozen hashes. [Archive log](../audit/reproductions/atv-remote-0.3.5-device-archive.log), [IPA metadata](../audit/reproductions/atv-remote-0.3.5-ipa-validation.json), [combined validation](../audit/reproductions/atv-remote-0.3.5-validation.json), [source snapshot](../audit/reproductions/atv-remote-0.3.5-source-hashes.json).
- **Icon package checks passed**: raster icons and Assets.car exactly match the previously verified remote icon from 0.3.3; primary icon references remain valid. No new physical launcher inspection was performed.

Core testing uses actual app source symlinks in a macOS XCTest harness. No physical iPhone installation, TV connection, pairing, or live Keychain operation was performed. The star/import screen and live app list still need checking on the user's iPhone. [Installation and physical checks](install-and-test.md).

Download [ATV-Remote-0.3.5-unsigned.ipa](../Build/ATV-Remote-0.3.5-unsigned.ipa), 5,238,837 bytes. SHA-256: `694517da325f584ada8538c51769fc701362c08f073be1bf0d7384c018b2e34e`. Sign and install as an update with the existing sideload identity when possible to retain setup.
