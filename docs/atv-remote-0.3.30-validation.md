# ATV Remote 0.3.30 Samsung Home icon

Version 0.3.30, build 33, uses a house Home icon when Samsung navigation is selected, including the Expanded Apple TV remote layout. Apple TV mode keeps the TV-screen icon. The shared Home button receives the selected device kind separately from its connection binding, so the correct icon also appears while disconnected. The Standard and compact Apple TV layouts follow the same rule. Home command routing and single/double/hold recognition are unchanged.

The unsigned arm64 iPhoneOS archive and native simulator app/test compilation passed. Two existing simulator UI cases passed with zero failures: Home single/double/hold suppression and saved Standard/compact/expanded layout geometry and pad preferences. All 19 UI methods compiled; the remaining 17 and unit tests were not rerun for this icon-only change. The cases do not assert the rendered SF Symbol; its mode-dependent selection was source-reviewed and compiled. No physical TVs were used. [UI report](../audit/reproductions/atv-remote-0.3.30-ui-runtime.json), [combined validation](../audit/reproductions/atv-remote-0.3.30-validation.json).

All 12 IPA files byte-match the device archive and ZIP integrity passed. The Home button and remote screen arm64 objects are linked; 67 source/resource/script inputs and 55 native compile inputs remained frozen through validation. DEBUG fixtures are absent. The app retains its bundle ID `local.roomremote.ios`, display name ATV Remote and iOS 27 minimum.

Download [ATV-Remote-0.3.30-unsigned.ipa](../Build/ATV-Remote-0.3.30-unsigned.ipa) (5,855,681 bytes). SHA-256: `81a811ab6492fa1881ca70b53ef72bfeb72914c57f40ecd9c23246b785619959`. Sign and install as an update with your existing sideloading tool.
