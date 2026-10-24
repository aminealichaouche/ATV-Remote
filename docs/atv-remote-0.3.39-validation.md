# ATV Remote 0.3.39 (42) validation

Auto is temporarily hidden from the room selector. A single disabled availability flag gates both the menu item and automatic-mode activation. Startup clears the old Auto preference and keeps the saved named room, so an update cannot silently continue automatic room selection. The underlying detection code remains dormant for later work. This change does not edit saved TVs, room assignments, stars, layouts or pairing credentials.

## Verification

The simulator build and two focused native UI checks passed: an old enabled Auto preference falls back to Living Room, Auto is absent from the menu, the named room and connected indicators survive relaunch; repeated room switches and background return still reuse established sessions. These use synthetic TVs and do not contact physical TVs. The broader protocol suite was not rerun for this menu and preference change.

## Artifacts

- [Unsigned IPA](../Build/ATV-Remote-0.3.39-unsigned.ipa), for the user's sideloading tool to sign. Minimum iOS 27, arm64; DEBUG fixtures excluded.
- [Signed Xcode archive](../Build/ATVRemote-0.3.39-TestFlight.xcarchive), version 0.3.39 (42), existing team and bundle. Strict signature verification and embedded provisioning profile checked. No upload performed.

[Build, focused test and package evidence](../audit/reproductions/atv-remote-0.3.39-validation.json).
