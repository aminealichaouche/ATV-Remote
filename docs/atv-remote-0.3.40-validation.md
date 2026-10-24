# ATV Remote 0.3.40 (43) validation

Expanded Apple TV remote is now first in Settings → Remote layout and the default when no layout is saved. Apple TV remote follows, then Alternate, which replaces the Standard display name. Both remote views and shared-preference capture use the same default. Existing raw layout values and preference keys are unchanged: a saved Standard choice becomes Alternate with the same controls, and other saved layouts remain selected. Auto remains hidden and disabled.

## Verification

The simulator build and focused native UI check passed. The check verifies fresh-install Expanded geometry, the default settings value, Expanded above both other menu options, Alternate present and Standard absent, and D-pad/touchpad geometry and saved choices through compact, Expanded and Alternate layouts across cold launches. This is a layout/default change; the broader protocol suite was not rerun and no physical TVs were contacted.

## Artifacts

- [Unsigned IPA](../Build/ATV-Remote-0.3.40-unsigned.ipa) for sideload signing: arm64, minimum iOS 27, DEBUG fixtures excluded.
- [Signed Xcode archive](../Build/ATVRemote-0.3.40-TestFlight.xcarchive): existing bundle and paid team, embedded profile and strict signature verification checked. Prepared for TestFlight; not uploaded.

[Build, UI check, package and signing evidence](../audit/reproductions/atv-remote-0.3.40-validation.json).
