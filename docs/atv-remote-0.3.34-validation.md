# ATV Remote 0.3.34 (37) validation

The user confirmed that Apple TVs displace the first phone when a second phone uses transferred Companion credentials. Samsung accepted both phones. This release stops exporting Apple controller identities and skips them in older imports, while keeping Samsung access sharing, TV profiles, IP/MAC, room bindings, per-TV stars, layout and pad preferences.

New imports show Apple TVs as requiring pairing on this iPhone. Legacy Apple credentials are still fully decoded and validated before being ignored. Both selection and the commit plan exclude them, and RemoteStore never installs them. Existing device identities, names, network settings and pairings are preserved. Already affected phones must use Manage TVs → Re-pair locally for each Apple TV; the new build does not erase saved pairings automatically or revoke anything on the TV.

65 hosted iOS simulator unit tests passed with zero failures, including five new legacy/controller-isolation cases and the transfer, selection, shared-setup and Apple/Samsung credential validation suites. One native UI test passed: import stars and remote appearance, review the independent-pairing notice, cold relaunch, export with Samsung-access disabled for Apple-only selection, and verify zero pairings without a biometric prompt. The final screenshot was visually reviewed. All compiled source inputs remained unchanged during validation.

The unsigned arm64 iPhoneOS IPA is version 0.3.34 (37), minimum iOS 27.0, the saved bundle ID. It needs signing by a sideloading tool. A separate signed archive is prepared for Xcode Organizer and TestFlight upload; no upload is performed by this workflow. The existing logo and signing team are preserved.

[Regression and IPA evidence](../audit/reproductions/atv-remote-0.3.34-validation.json), [signed archive verification](../audit/reproductions/atv-remote-0.3.34-signed-archive.json), [UI screenshot](../audit/reproductions/atv-remote-0.3.34-transfer.png).

Simultaneous physical control after independent pairing has not been tested from this workspace. This release removes the copied-identity conflict; it does not establish a firmware-independent guarantee about the number of TV sessions.
