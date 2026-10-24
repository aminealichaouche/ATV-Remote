# ATV Remote 0.3.35 (38) validation

Settings now puts the dropdown immediately left of each TV name and the connection action on the right, with compact status dots/spinners. Saved TVs start collapsed and expand into single navigation rows with inline arrows; a blue Add a TV plus row opens a separate form. Rename/Re-pair/Remove live inside Manage TV. The Add TV scanner captures a fresh IP/MAC draft when opened, preventing a stale or empty IP after manual entry.

Apps has native search across starred, downloaded and included apps. Only bundle com.comcast.cim.x2 is renamed Xfinity Stream; other apps called Stream remain unchanged. Star and launch identity continue to use bundle IDs. The Shortcuts toolbar uses a transparent outline SF Symbol.

Setup exports omit room groups, and the real import entry point validates legacy files before removing their room assignments. Rooms-only legacy files receive an actionable error. TV profiles, optional Samsung access, exact selected Apple TV star lists, and layout/pad settings still transfer. Apple controller identities remain excluded as in 0.3.34. Existing local room bindings are preserved.

The foreground monitor checks every three seconds and retries eligible failed/disconnected selected TVs, throttled against the previous attempt. Established and pending sessions and explicit disconnect holds are preserved. Switching navigation target explicitly requests its connection if offline. Backgrounding retains established sockets; iOS suspension/termination can still end them. Reopening restores saved pairings. A paired Apple TV can fall back to its saved IP/port when Bonjour misses it, while still verifying its pinned accessory identity; discovered updated endpoints remain preferred.

Rooms have visible deletion actions and confirmation. Deleting the final room leaves No room, retaining TV profiles and stars across cold relaunch.

## Native verification

250 hosted iOS simulator unit tests passed with zero failures. New cases cover app-name isolation, search across sections, absent-app filtering, saved-endpoint fallback permission and ambiguity, room-free encrypted star transfers, malformed/rooms-only legacy payloads, and empty-room persistence. An older power-refresh test used a scheduler-dependent fixed yield count; its fixture now uses a bounded timed wait. Its initial failure is retained in the audit log.

Nine distinct native UI checks passed: actual starring plus search and export/import into a fresh receiver, cold star persistence, retry cadence and navigation requests, healthy background return, compact settings alignment, collapsed/expanded saved TV navigation and Add TV, last-room deletion with retained TVs after cold relaunch, immediate saved IP/MAC wake targeting, scanner draft retention, and transfer selection without rooms. (Compact saved-TV/Add TV navigation is one check.) The corrected batch passed eight cases; the final deletion case passed separately after the test waited for the native list/dialog animation. Production source hashes match between these runs and the delivered archive. Synthetic TVs and installed-app inventories replace network actions. No TV commands were sent.

The star test selected Xfinity Stream's star in Apps, filtered it with search, created a real encrypted export, imported that export into a fresh receiving fixture, preserved Receiver Room, and confirmed the star after another cold launch. It did not merely import a prepopulated star fixture.

Screenshots of settings, saved TVs and app search were visually reviewed. Initial UI failures and corrected runs remain in audit/reproductions rather than being discarded.

## Artifacts

- Unsigned IPA: Build/ATV-Remote-0.3.35-unsigned.ipa; saved bundle ID, minimum iOS 27, arm64 iPhoneOS, no DEBUG fixtures. All packaged files byte-match the unsigned archive.
- Signed archive: Build/ATVRemote-0.3.35-TestFlight.xcarchive; saved developer team, embedded profile, strict signature verification successful. Optimized Release build; no DEBUG fixtures. No upload performed.
- [Combined evidence](../audit/reproductions/atv-remote-0.3.35-validation.json), [unit tests](../audit/reproductions/atv-remote-0.3.35-unit-final.json), [corrected UI batch](../audit/reproductions/atv-remote-0.3.35-ui-corrected.json), [deletion check](../audit/reproductions/atv-remote-0.3.35-ui-deletion-wait.json), [signature](../audit/reproductions/atv-remote-0.3.35-signed-archive.json).

Physical Wi-Fi reconnection and concurrent independent-phone control still require a hardware retest. The app cannot keep a socket alive after iOS terminates its process; this release restores connections without a manual Connect tap when the app runs again.
