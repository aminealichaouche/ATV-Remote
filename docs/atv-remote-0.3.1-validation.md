# ATV Remote 0.3.1 Home correction

The user reported that tapping Apple TV Home opened the Apple TV streaming app. Version 0.3.0 mapped Home to the physical TV/Home key, whose destination is configurable on the television. Version 0.3.1 maps app Home to Back/Menu Hold. [Apple’s tvOS 27 navigation guide](https://support.apple.com/guide/tv/navigate-apple-tv-4k-atvbe55a4b4e/27/tvos/27) documents holding Back/Menu to reach the Home Screen. The [maintained pyatv control API](https://pyatv.dev/development/control/) supports this gesture through Menu Hold.

The actual Companion operation is HID Menu code 5 down, wait one second, then code 5 up. Back stays a short Menu press. Samsung Home and the configurable native TV/Home key are unchanged. The app sends this gesture for one tap of its Home button; the user does not need to hold it or change the TV-button setting. Source routing retains the selected TV identity and connection generation.

Holding the button now includes cancellation cleanup: after an acknowledged button-down, cancelling during the wait or release acknowledgement attempts one key-up on the original handler with a one-second timeout. It never repeats button-down, reconnects, or chooses another TV. Release is best effort if the original session has already closed. Short taps and double taps keep their previous behavior.

Version 0.3.1, build 4, preserves the bundle identifier, rooms, Keychain service, pairing identities, encrypted transfer format, and all [0.3 layout/Apps/power changes](atv-remote-0.3-validation.md). Install as an update with the same sideload signing/app identity to retain setup where the signer permits it.

## Validation

- **12 affected CompanionService XCTest cases passed**, including three new encrypted loopback regressions: held Menu versus short Back ordering/timing, cancellation during the hold, and cancellation while the first release acknowledgement is withheld. They verify HID Menu code 5, one original connection, and no repeated button-down. No physical television was contacted. [Log](../audit/reproductions/atv-remote-0.3.1-home-protocol-tests.log), [result and tested source hashes](../audit/reproductions/atv-remote-0.3.1-home-protocol-validation.json).
- **Unsigned iPhone archive and IPA checks passed**: arm64, iPhoneOS, iOS 27 minimum, version 0.3.1/build 4, ATV Remote visible name, valid ZIP, executable permissions preserved, no signature/profile. Frozen source hashes match after the build. [Archive log](../audit/reproductions/atv-remote-0.3.1-device-archive.log), [IPA metadata](../audit/reproductions/atv-remote-0.3.1-ipa-validation.json), [source snapshot](../audit/reproductions/atv-remote-0.3.1-source-hashes.json).
- No UI layout changed in this patch. Simulator UI automation was not repeated after the prior startup failure; no new UI pass is claimed. The 55 core and 33 Apps/Companion checks documented for 0.3 are historical validation, not rerun totals for this patch. Physical Apple TV behavior still needs retesting.

Download [ATV-Remote-0.3.1-unsigned.ipa](../Build/ATV-Remote-0.3.1-unsigned.ipa), 4,080,089 bytes. SHA-256: `87d316e65cf79a91707bd81d8a5f5035025909c08e4f90df5459da7a169f45b5`. Sign with the existing sideloading tool and install as an update.

To retest, leave the Apple TV TV-button setting set to the streaming app, open an app or a nested Settings page, and tap ATV Remote Home once. Its expected destination is the app grid after about one second. Back should still go one screen back.
