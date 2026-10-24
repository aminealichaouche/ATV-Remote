# ATV Remote 0.3.25 consistent room editor

Version 0.3.25, build 28, gives the Samsung TV and Apple TV dropdowns one shared layout. The TV type appears above the selected name and a separate smaller IP address. Both menus fill the row width and place their chevrons at the same right edge, so long names cannot force only one selector into a different position. None remains available for either slot. Each selector edits its room draft; the existing Save and Cancel handlers remain unchanged.

Only the room-editor view and version generator changed from 0.3.24 among the 64 frozen source/resource/script inputs. Drivers, room assignment logic, Auto selection, pairing, star preferences and transfer code are byte-identical to that release.

The unsigned arm64 iPhoneOS archive and native simulator test build passed. All 15 existing UI cases compiled; the existing room-group creation/save/selection and invalid-address rejection case actually passed, with one test and zero failures. The room editor screenshot was captured during that case in dark mode and visually reviewed. It shows empty draft slots; a populated-device screenshot and physical TVs were not tested. No new tests were added for this layout change. The prior 206-unit-test result belongs to 0.3.24; the unit suite was not rerun here. [UI report](../audit/reproductions/atv-remote-0.3.25-ui-runtime.json), [room editor screenshot](../audit/reproductions/atv-remote-0.3.25-room-editor.png), [combined validation](../audit/reproductions/atv-remote-0.3.25-validation.json).

All 12 packaged files byte-match the archive, the ZIP passed its integrity check, and all frozen inputs remained unchanged after verification. The app remains unsigned, with display name ATV Remote, bundle ID `local.roomremote.ios`, and minimum iOS 27. DEBUG fixtures are absent from the executable.

Download [ATV-Remote-0.3.25-unsigned.ipa](../Build/ATV-Remote-0.3.25-unsigned.ipa), 5,767,940 bytes. SHA-256: `fd09bdfee7466c3ae1107a6b2cb83223e9f2b18de8cd311a9ed0eac142ba1d6b`. Sign and install as an update with your existing sideloading tool.
