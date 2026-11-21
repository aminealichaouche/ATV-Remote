# ATV Remote 3.5.7 (55) validation

**Samsung inputs from Sources.** Tapping **Sources** on the Samsung remote opens a menu with **TV** and **HDMI 1–4**, plus **Open source menu on TV** for the previous behavior. A hardware test on the user's Samsung showed `KEY_TV` and `KEY_HDMI` work but direct `KEY_HDMI1`–`KEY_HDMI4` are ignored. Its source menu keeps a fixed order (SmartThings, Connected Devices, TV, HDMI 1…4, USB, Mobile), opens on the current input, and Left stops at the first entry. Choosing an input therefore sends Source, waits 0.8 s for the menu, presses Left eight times (0.1 s apart) to reach SmartThings, Right twice to TV and once more per HDMI number (0.15 s apart), then Enter: about 1.9 s for TV and 2.5 s for HDMI 4. The sequence holds the Samsung command slot and stops if the TV, room or connection changes; sent keys are never replayed. A TV with fewer than four HDMI inputs would land on USB for the missing ones.

**Export compliance.** Info.plist sets `ITSAppUsesNonExemptEncryption` to NO, so App Store Connect no longer asks the encryption question for each upload. The app uses only standard algorithms through Apple's TLS, CryptoKit and CommonCrypto, plus SRP-6a for Apple TV pairing authentication, to support TV control.

## Verification

Unit tests cover each input's key sequence, the pauses between keys, and that every input switches in under 2.75 s. A UI test chooses HDMI 2 from Sources and checks the exact keys sent, then opens the TV's menu. The Xcode 27.2 update left no iOS simulator runtime installed, so these tests have not run in this workspace yet; the signed archive compiles them. The timings need checking on the TV.
