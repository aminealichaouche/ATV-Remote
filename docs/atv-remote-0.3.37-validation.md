# ATV Remote 0.3.37 (40) validation

Apple TV names in Settings and its TV dropdown use a display label: Living Room → Living Room Apple TV. Existing Apple TV or AppleTV labels are preserved without adding another suffix, including case variants. Samsung labels, saved names, identity, pairings and room assignments are unchanged. Accessibility values use the same settings label.

The existing compact-settings UI check passed with zero failures. It asserts Living Room Apple TV for a saved Apple TV named Living Room and Living Room TV for Samsung. It also verifies left menu/right connection alignment and navigation through collapsed saved TVs, Manage TV, and Add a TV. This is a focused label change; no new unit tests or repeated broad suite were added. Universal-star behavior remains as verified in 0.3.36.

Artifacts: Build/ATV-Remote-0.3.37-unsigned.ipa and Build/ATVRemote-0.3.37-TestFlight.xcarchive. The archive uses the existing developer team and has not been uploaded. Native test and signing evidence are in audit/reproductions/atv-remote-0.3.37-*.json.

The native settings screenshot was visually reviewed: the complete Living Room Apple TV label fits on one line with aligned controls. [Screenshot](../audit/reproductions/atv-remote-0.3.37-settings.png).
