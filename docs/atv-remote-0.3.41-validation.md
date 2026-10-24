# ATV Remote 0.3.41 (44) validation

Background return keeps the root presentation and SwiftUI navigation/drafts instead of dismissing everything to the main remote. Installed-app snapshots, search and presentation identity remain. In-flight load/launch requests and remote controls are canceled and invalidated; an incomplete load offers Reload. Shortcuts remain open, with canceled in-progress work marked paused and never automatically replayed. Transfer backgrounding cancels asynchronous work/authentication but keeps choices, import review and a prepared encrypted export in memory. Explicit dismissal still clears transient transfer material and removes its temporary export. The live scanner stops on background and keeps its detected/manually edited addresses in review. Cold-launch navigation/draft restoration is not added: force-quitting or process termination starts a new UI session.

Manage TV shows the saved name followed by (Apple TV) or (Samsung). Name, IP and Samsung MAC are draft fields. Inline x buttons clear IP/MAC drafts; the separate Remove saved MAC action is gone. One bottom Save validates all edits and persists name, IP and MAC together before dismissing. Blank MAC clears the saved MAC; blank/invalid IP and invalid names keep the editor open without changing saved data. Back discards unsaved edits. Saved device identity, pairing keys, rooms and stars stay intact; changed IP addresses retain the existing targeted connection reset behavior.

## Verification

262 hosted iOS simulator unit tests passed. Coverage includes atomic edits with invalid IP/MAC/name, name normalization, persisted MAC removal, existing identity/room/star retention, wake targets and setup sharing.

Five focused UI checks exercise retained Manage TV navigation and name/IP/MAC drafts across background return; Samsung clear followed by Back versus Save and cold relaunch; Apple TV type, name/IP save and reopened values; scanner IP/MAC edits retained across background return and used immediately by wake without restarting; Apps search, enabled star controls and encrypted export/import review across background return; and healthy connection indicators and Home control after return. These use synthetic endpoints and no physical TVs. The last production edit only changes scanner lifecycle resets to retain its draft; its focused UI check was rerun on that final build. Core store/editor/registry source hashes remain identical to the earlier unit and five-case UI runs. [Manage TV screenshot](../audit/reproductions/atv-remote-0.3.41-manage-tv.png) was visually reviewed.

## Artifacts

- [Unsigned IPA](../Build/ATV-Remote-0.3.41-unsigned.ipa), for sideload signing. Minimum iOS 27, arm64, DEBUG fixtures excluded.
- [Signed Xcode archive](../Build/ATVRemote-0.3.41-TestFlight.xcarchive), existing team and bundle, embedded profile and strict signature verification checked. Prepared for TestFlight; no upload performed.

[Combined source, test, package and signing evidence](../audit/reproductions/atv-remote-0.3.41-validation.json).
