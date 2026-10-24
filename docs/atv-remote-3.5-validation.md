# ATV Remote 3.5 (46) validation

Version 3.5 restores the exact app implementation from 0.3.41 (44), the release before Wi-Fi/VPN detection. All 33 App/Sources files match the earlier signed archive's SHA-256 source manifest byte for byte. App/Tests and App/UITests also match the final 0.3.41 scanner-draft test build. The release version changes to 3.5 and the build number advances to 46.

The 0.3.42 network monitor, destination interface lookup, Wi-Fi/VPN connection gates, Only Available on Wi-Fi setting and related test fixture are removed. Its saved preference is no longer read, so it cannot restrict a user updating from 0.3.42. Earlier TV connection behavior is restored. Existing pairing records, room configuration, app stars and layout choices are not migrated or removed. Auto remains hidden; Expanded remains the default; panels/drafts are retained on background return; Manage TV still saves name/IP/MAC together with inline clear controls.

## Verification

The restored source manifest is recorded in [rollback evidence](../audit/reproductions/atv-remote-3.5-restored-sources.json). The prior release's [0.3.41 validation](atv-remote-0.3.41-validation.md) covers the same implementation, including 262 unit tests and five distinct UI checks. The broader unit suite was not repeated for this exact-source repackaging.

A fresh simulator build and two focused UI checks passed on 3.5: retained room sessions through repeated switches and background return, and Manage TV drafts/inline clear/save behavior through background return and cold relaunch. Source hashes are correlated with the restored release and signed archive. Physical TV/VPN testing was not performed for this packaging change.

## Artifacts

- [Unsigned 3.5 IPA](../Build/ATV-Remote-3.5-unsigned.ipa), for the user's sideloading tool to sign. arm64, minimum iOS 27, DEBUG fixtures excluded.
- [Signed 3.5 TestFlight archive](../Build/ATVRemote-3.5-TestFlight.xcarchive), existing bundle ID and the saved developer team. Strict signature verification and embedded profile checked. Prepared; not uploaded.

[Combined build, test, package and signing evidence](../audit/reproductions/atv-remote-3.5-validation.json).
