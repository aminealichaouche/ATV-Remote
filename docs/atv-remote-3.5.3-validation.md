# ATV Remote 3.5.3 (49) validation

**Re-pair after an Apple TV factory reset.** Apple TVs are saved by the Companion identity they advertise (`rpMRtID`), which a factory reset regenerates. Re-pair previously deleted the old credentials and then searched for the old identity, so it failed with "not found on Wi-Fi" until the TV was removed and added again. Re-pair now scans first. When the saved identity is gone and exactly one unsaved Apple TV advertises at the saved IP address, the saved entry moves to that identity, keeping its name, room assignments and starred apps, and the PIN shown on the TV completes pairing. A TV that is already saved is never taken over, ambiguous matches are ignored, and manually entered Apple TVs keep the previous behavior. A reset TV that moved to a different IP address still needs Remove and add.

**Rooms list.** Each saved room opens its editor from a full-width row with a trailing chevron. Delete buttons are hidden until **Edit**; **Done** ends editing, and editing ends automatically when no rooms remain. Swipe to delete is unchanged. Each assigned TV shows its type, for example "Living Room TV (Samsung)" and "Living Room (Apple TV)".

**Signing and identifiers.** The developer team and bundle ID are no longer stored in the generated project. They are read from the untracked `App/Signing.local.xcconfig` through the committed `App/Signing.xcconfig`, which defaults the bundle ID to `io.github.atvremote`; existing builds keep their bundle ID. The direct Share setup file type is now `io.github.atvremote.direct-setup` with MIME `application/vnd.atvremote.setup`; files keep the `.atvsetup` extension. Sharing between a 3.5.3 phone and an older version should be checked once with AirDrop.

## Verification

Unit tests cover selecting the reset replacement (same address, unsaved, unambiguous, discovered identities only) and moving the saved identity together with its rooms and stars while other TVs stay unchanged. The Rooms UI test checks that delete is hidden until Edit. Physical reset recovery has not been exercised on hardware from this workspace.
