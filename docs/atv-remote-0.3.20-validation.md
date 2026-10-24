# ATV Remote 0.3.20 improves saved-TV spacing and pending retries

Version 0.3.20, build 23, gives each saved TV its own grouped Form card. The padded icon/name/address header uses headline/subheadline text and an eight-point text gap. Samsung power setup has its own navigation row. Rename, Re-pair and Remove have a separate equal-width action row with 44-point targets and vertical padding, avoiding nested navigation/action targets.

The main-screen name, icon and dot remain a single 44-point tap target. Pending attempts are no longer disabled: tapping connects explicitly, canceling the old attempt, advancing its epoch and releasing only that TV’s manual disconnect hold. PIN/certificate states still open their required prompts. Connected status remains informational. A spinner appears immediately to the right of the gray dot while connecting or awaiting TV approval. The selected identity/current state are rechecked when tapped, and no separate Connect row returns.

A DEBUG-only fixture holds automatic connection for two synthetic devices. Apple starts connecting and Samsung awaiting approval. The new UI regression checks both buttons are enabled, taps the Samsung name area, and expects its invalid loopback-address failure from the production connection route. Samsung rejects this endpoint before a socket or Keychain read. The test also checks saved-TV action heights and captures screenshots.

Thirty of 31 core/test inputs match the previous referenced 171-case suite. RemoteStore differs only by two DEBUG fixture blocks; removing those reconstructs the reference source byte-for-byte. Core tests were not rerun. Existing transport, pairing, room assignment, wake, pad geometry and preferences remain unchanged. [Core reference](../audit/reproductions/atv-remote-0.3.20-core-reference.json).

Native iOS 27 build-for-testing passed: all ten UI methods compiled, 44 native inputs unchanged. One simulator regression passed with zero failures: name-area retry dispatch, pending buttons enabled and saved-TV action heights. Both screenshots were exported and visually reviewed. No live TV session was tested. [Compile report](../audit/reproductions/atv-remote-0.3.20-ui-compile.json).

The arm64 unsigned iPhoneOS archive and IPA passed package verification. All 12 packaged files byte-match the archive and all 56 frozen inputs remain unchanged. DEBUG fixtures, artwork types and former separate connection-button identifiers are absent from the executable. The stable bundle identity is `local.roomremote.ios`, display name ATV Remote, minimum iOS 27. [Combined validation](../audit/reproductions/atv-remote-0.3.20-validation.json).

Download [ATV-Remote-0.3.20-unsigned.ipa](../Build/ATV-Remote-0.3.20-unsigned.ipa), 5,688,805 bytes. SHA-256: `f85d882e5a0e15b88d387b2c367423e5d8d6239176cb9ef8f405980f268a5a59`. Sign with your sideloading tool or archive the updated source with your paid team for TestFlight.
