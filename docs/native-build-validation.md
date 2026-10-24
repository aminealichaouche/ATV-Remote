# Native test build validation

The first Room Remote IPA was built and packaged on 12 October 2026 with Xcode 27.0. It runs directly on an iPhone with iOS 27 or later. It contains the native drivers and starts with an empty device list. Your sideloading tool must sign it before installation.

## Delivered package

- File: [RoomRemote-0.1.0-unsigned.ipa](../Build/RoomRemote-0.1.0-unsigned.ipa)
- Size: 3,847,866 bytes; arm64 iPhoneOS binary; minimum iOS 27.0.
- Bundle identifier: `local.roomremote.ios`; version 0.1.0, build 1.
- SHA-256: `ec2bf314842c4661d66926ef33bb6ca7f590e7301b91a8e2d056a9582a97c44d`.
- Archive succeeded. `codesign` confirms the app is not signed; no provisioning profile is included. ZIP integrity, executable permissions, platform, architecture, and required resources were checked.
- App icon, Local Network description, three Bonjour service declarations, privacy manifest, and third-party notices are bundled.

This hardware-test build uses Release compilation conditions with optimization disabled. The DEBUG-only UI-test reset argument is excluded. Dependencies are vendored locally; no moving package reference or opaque SmartView binary is used. Rebuild with `python3 scripts/build-ipa.py`.

## Checks completed

| Check | Result and scope |
|---|---|
| iPhone archive and IPA | Passed. [Package record](../audit/reproductions/ipa-validation.json), [archive log](../audit/reproductions/native-device-archive.log) |
| Native app unit tests | 22 passed, zero failures, in the iOS 27 simulator: room/device identity, wrong-kind assignment rejection, device removal, stale epochs, command cancellation and replacement, Apple endpoint identity, Samsung input/event/authorization parsing and command encoding. [Log](../audit/reproductions/native-simulator-tests.log) |
| Native UI test | Passed on an isolated iPhone 18 Pro simulator: empty-device start, independent selectors, create and select a room, reject a Samsung URL without saving a TV. No device connection is initiated by the test. Same log; full result bundle in `Build/RoomRemoteQA-final.xcresult` |
| Hardened SwiftATV suite | 488 passed before the final review changes: 395 XCTest and 93 Swift Testing cases. [Log](../audit/reproductions/hardened-swiftatv-suite.log) |
| Final Apple changes | 48 affected tests passed, including two new regressions for bounded state streams and SRP challenge input. These overlap the full suite; they are not 48 additional unique tests. Adapter Swift 6 typecheck and six endpoint-selection checks also passed. [Log](../audit/reproductions/final-apple-regressions.log) |
| Interactive design preview | Multi-room/device behavior checked in six width/appearance combinations, with no JavaScript errors or horizontal overflow. These are simulated UI checks. [Results](../design/qa/multi-room-results.json) |

The first unsigned simulator test attempt stalled during installation. Restarting only the temporary QA simulator and using local simulator signing resolved it. The final simulator run completed successfully. That development signature is separate from the unsigned iPhone IPA.

## Implementation review and fixes

The two supplied repositories were audited as pinned snapshots and rejected for adoption unchanged. The [source audit](source-audit.md) links the findings and reproductions. The native app uses an original Samsung driver and the MIT-licensed SwiftATV candidate with preserved dependency and pyatv notices.

The Apple path verifies pairing signatures and stored accessory identity. Local hardening bounds Companion frames and receive buffers, recursive OPACK depth/nodes/work, RTI input, SRP arithmetic inputs, and event/state streams. Encryption and socket writes share one serial transport owner. Reconnect resolves the saved discovery identity and rejects missing, conflicting, or different TVs. Text send refreshes keyboard focus before sending.

The Samsung path accepts explicit private numeric addresses and secure port 8002. First-use trust requires an explicit certificate review; later connections enforce the saved fingerprint. Only the expected authorized event enables commands. Denial, unrelated frames, malformed tokens, and timeouts cannot become success. Tokens and fingerprints are device scoped in Keychain. Network callbacks and sends validate the active session generation and target.

App review fixed cancellation leaving buttons busy, stale cleanup clearing a newer command, delayed tools addressing a newly selected Apple TV, stale pairing errors, and gestures finishing after a device switch. Requests capture device identities and epochs; Apple navigation and Samsung volume have independent command slots. Credentials use nonsynchronizing, device-only Keychain storage. Room preferences contain no credentials.

Source hashes for the authored app/resources/tests/scripts, current SwiftATV implementation, dependency manifests, and revision record are saved in [native-source-hashes.json](../audit/reproductions/native-source-hashes.json). Vendor changes are described in [ROOM-REMOTE-CHANGES.md](../Vendor/SwiftATV/ROOM-REMOTE-CHANGES.md). A [machine-readable build summary](../audit/reproductions/native-build-validation.json) and exported native UI screenshot in `Build/qa/native-ui` accompany the results.

## Remaining hardware validation

No physical TV, sideloaded iPhone, or live TV pairing was tested. Samsung compatibility requires its secure Tizen WebSocket interface; the friendly labels S95BD and S60 do not establish a full hardware model. Samsung wake, legacy/unsecured fallback, and automatic Samsung discovery are absent. Apple TV uses the community Companion protocol and must be tested on your tvOS version.

Follow [install and test](install-and-test.md) to pair each physical device, check independent routing and room persistence, and observe navigation, volume, keyboard, apps, inputs, and power. Build and offline tests do not establish firmware compatibility, real Keychain behavior after re-signing, Local Network permission recovery, or actual TV response. The audit covers the stated sources and checks; it is not an exhaustive security certification of every dependency.
