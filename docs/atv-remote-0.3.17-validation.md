# ATV Remote 0.3.17 removes app artwork

Version 0.3.17, build 20, removes all app thumbnails, included-app symbol tiles, generic placeholders and App Store info links. Apps displays names with separate star controls. The public artwork fetcher, cache policy/store, thumbnail view and ten obsolete artwork tests are removed from the project. Opening Apps no longer starts artwork requests or reads the old artwork cache. Per-TV stars/imports, installed-only sections, launch identifiers and loading/error handling remain unchanged.

Changes are limited to AppsScreen, removal of the four artwork source/test files, and the version generator. All 31 remaining actual core/test inputs match the passing 0.3.16 suite of 181 cases, with its ten artwork cases removed. These 171 remaining cases are referenced without reexecution; no new tests were added for the feature removal. [Core reference](../audit/reproductions/atv-remote-0.3.17-core-reference.json).

Native iOS 27 build-for-testing passed, with all eight UI methods compiled and all 44 native inputs unchanged. No simulator boot, UI execution, camera or physical TV interaction occurred. [Compile report](../audit/reproductions/atv-remote-0.3.17-ui-compile.json), [log](../audit/reproductions/atv-remote-0.3.17-ui-compile.log).

The arm64 iPhoneOS archive and unsigned IPA passed package checks. All 12 packaged files match the archive and all 56 frozen inputs remain unchanged. Version/build, stable bundle identity, minimum iOS 27, ZIP, executable permission and unsigned code were verified. Artwork cache/lookup/type strings and DEBUG fixtures are absent from the binary. The main remote icon, Shortcuts icon/preset, expanded layout, camera scanner, encrypted transfer dictionary and existing wake controls remain. [Combined validation](../audit/reproductions/atv-remote-0.3.17-validation.json), [IPA metadata](../audit/reproductions/atv-remote-0.3.17-ipa-validation.json), [frozen inputs](../audit/reproductions/atv-remote-0.3.17-source-hashes.json).

Download [ATV-Remote-0.3.17-unsigned.ipa](../Build/ATV-Remote-0.3.17-unsigned.ipa), 5,685,468 bytes. SHA-256: `ef7cf9612f4779b01911f3bc521c2bb989f58d592cb7b359d5a7dffcbf18d59b`. Sign with your sideloading tool, or archive the updated Xcode source with your paid team for TestFlight.

This release does not change Samsung wake. The user’s failed Wi-Fi wake has a separate [research follow-up](samsung-power-on-findings.md), covering physical IR, unicast limitations, Apple-approved broadcast entitlement, HDMI-CEC and SmartThings. No physical wake fix is claimed.
