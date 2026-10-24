# ATV Remote 0.3.36 (39) validation

Settings → Apps now has Universal stars, enabled by default. All saved Apple TVs use the same app bundle-ID list while it is on. Apps displays only entries in that TV’s installed inventory, and hides Import stars. Turning it off restores each TV’s retained individual list and the import option. The shared list remains saved for switching back; subsequent per-TV edits do not silently change it.

Existing lists seed the shared list once when an older setup is opened. Both the mode and edits are saved atomically in registry storage and UserDefaults before the UI adopts them. Explicitly removing the final shared star persists an empty list, preventing old stars from reappearing on relaunch. Shared stars are bounded to 1,024 valid bundle IDs, matching the previous total per-TV capacity.

Setup payload v3 carries the shared list and mode alongside selected TVs’ individual lists. Star review explains the effect across TVs, and declining stars excludes both the mode and the lists. Older payloads remain readable. The encrypted envelope remains v2, using the existing four-word phrase. Both phones need 0.3.36 or later for new universal-star files. Apple controller identities and room assignments remain excluded.

## Verification

258 hosted iOS simulator unit tests passed, including eight new universal-star tests covering upgrade, installed-app filtering, limits, separate lists, repeated relaunch, empty-list persistence, encrypted transfer, declining stars, and schema validation. An initial run exposed an older test treating payload v3 as unsupported; that test now checks v4. All initial evidence is retained. The first UI run also retained two passing transfer cases and a failed switch interaction: XCTest tapped the row center. The corrected test waits for sheet dismissal and taps the visible switch itself.

Three native UI checks passed with zero failures. Results are recorded in audit/reproductions/atv-remote-0.3.36-ui-reviewed.json. The checks exercise real starring, search, encrypted export/import, old-file import, universal stars across two synthetic saved TVs, persisted off mode, and hiding/showing Import stars. Synthetic inventories and endpoints replace TV commands.

## Artifacts

- Build/ATV-Remote-0.3.36-unsigned.ipa: saved bundle ID, arm64 iPhoneOS, minimum iOS 27, unsigned for the user’s sideloading tool. DEBUG fixtures excluded.
- Build/ATVRemote-0.3.36-TestFlight.xcarchive: optimized Release, the saved developer team, embedded provisioning profile, strict signature verification passed. Not uploaded.
- Native evidence: [unit tests](../audit/reproductions/atv-remote-0.3.36-unit-reviewed.json), [UI checks](../audit/reproductions/atv-remote-0.3.36-ui-reviewed.json), [signed archive](../audit/reproductions/atv-remote-0.3.36-signed-archive.json).

No physical TVs were available for this verification. Existing transport and wake behavior were not changed.

[Combined package and test evidence](../audit/reproductions/atv-remote-0.3.36-validation.json).
