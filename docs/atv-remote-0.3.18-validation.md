# ATV Remote 0.3.18 simplifies TV address entry

Version 0.3.18, build 21, fixes the scanner’s manual-entry flow. Samsung power-on setup shows the saved TV IP once as a labelled, read-only row and asks only for its MAC address. The scan sheet receives the current MAC draft. New-TV scan sheets receive both existing IP and MAC drafts; switching to manual entry does not discard them.

Review shows one short MAC adapter hint, no empty-field red error, a Use MAC address button and one Scan again action. Manual MAC entry is also available directly from the live camera screen. Any conflicting detected IP prevents applying a MAC to an existing TV; scanning again clears detected candidates while restoring the original draft. Scanning never edits the saved TV IP or pairs a device.

The added UI regression case exercises opening the scanner from prefilled new-TV fields, choosing manual entry when the camera is unavailable, checking both values, and applying them without pairing. Its camera-unavailable fixture is DEBUG-only. UI execution and live camera interaction have not been performed on this machine.

The 31 core source/test inputs match the previous referenced suite: 171 retained cases, with no core changes or reexecution in this release. Samsung wake transport remains unchanged; this release fixes setup UI, not standby wake delivery.

Native iOS 27 build-for-testing passed: all nine UI methods compiled, 44 native inputs unchanged. No simulator boot or UI execution. [Compile report](../audit/reproductions/atv-remote-0.3.18-ui-compile.json).

The arm64 unsigned iPhoneOS archive and IPA passed package verification. All 12 files byte-match the archive and all 56 frozen inputs remain unchanged. DEBUG fixtures and the former artwork types are absent from the executable. The stable bundle identity is `local.roomremote.ios`, display name ATV Remote, minimum iOS 27. [Combined validation](../audit/reproductions/atv-remote-0.3.18-validation.json).

Download [ATV-Remote-0.3.18-unsigned.ipa](../Build/ATV-Remote-0.3.18-unsigned.ipa), 5,688,429 bytes. SHA-256: `49fe4baa3714c73cb8984f5176d54498b47535053aecd0a905c79a9a43f7b1d4`. Sign with your sideloading tool or archive the updated source with your paid team for TestFlight.
