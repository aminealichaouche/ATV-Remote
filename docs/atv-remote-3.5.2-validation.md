# ATV Remote 3.5.2 (48) validation

Room-to-TV assignments are now included by default through a remembered Room assignments choice. These mappings are distinct from wireless TV authorization. Samsung tokens and Apple TV controller keys remain local; each phone pairs independently. New room-bearing payloads use version 4 and an explicit room opt-in marker. Legacy files remain readable with their prior rooms-local behavior. Both phones need 3.5.2 and a newly prepared file for room mappings; 3.5.1 did not export them.

Sender selection excludes unselected TVs from rooms. Receiver preview shows the Samsung/Apple TV assigned to each selected room and the resulting room name. Excluded/conflicted TV identities cannot be assigned. Identical rooms are reused, empty matching rooms may be filled, and configured conflicts are added under separate deterministic identities/names. Repeated imports are idempotent. A newly filled or adopted selected room uses the normal driver/epoch handoff, preserving previous healthy sessions and avoiding command routing through an old temporary TV selection. Import does not send launch/HID/power commands.

One Share setup action presents Apple’s share sheet, including AirDrop and Save to Files. The separate Save action was removed at the user’s request. Direct files open an import preview without a phrase; optional phrase-protected files retain AES-GCM/PBKDF2 and legacy decryption. Keyboard/Apps/Sources gain six points of top spacing while retaining their 20% larger sizes. No partial icon set or unverified Xfinity Favorites/channel macro is included. See [the research audit](apple-tv-app-controls-and-icons-research.md).

## Verification

Unit checks cover room mappings through direct and protected files, credential stripping, filling a room after TV profiles were imported earlier, preserving configured-room conflicts, repeated import, selective TV/room filtering, malformed references, and strict version/opt-in consistency. Existing transfer, stars, saved-MAC, selection and connection tests remain.

UI verification covers optional room exclusion and stars import/relaunch, protected sharing and phrase import, the single share sheet’s Save to Files option, room mapping preview/import across both TV brands, preserving the receiver’s configured room, room selection and cold relaunch. Native list prefetching required scrolling before querying later room/star rows. The simulator exposed Save to Files; completing a real Files save and physical proximity AirDrop remain device checks, not claimed as exercised here.

All **271 unit tests passed** on the final sources. Two distinct final-app UI flows passed: protected sharing/import and the complete two-room assignment review/import/selection/cold-relaunch flow. The earlier optional TV/stars-only flow also passed before the final scoped import handoff refinement. Final source hashes, signed archive verification and package metadata are recorded in [machine-readable evidence](../audit/reproductions/atv-remote-3.5.2-validation.json). Public catalog/domain research was read-only and did not access Xfinity accounts or physical TVs.

## Artifacts

- [Unsigned IPA](../Build/ATV-Remote-3.5.2-unsigned.ipa): arm64, iOS 27+, existing bundle ID, DEBUG fixtures excluded.
- [Signed TestFlight archive](../Build/ATVRemote-3.5.2-TestFlight.xcarchive): the saved developer team, signature/profile verified; not uploaded.
- [Sharing instructions](share-pairings.md).
