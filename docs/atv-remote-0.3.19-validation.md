# ATV Remote 0.3.19 simplifies connection indicators and shrinks the expanded pad

Version 0.3.19, build 22, removes the separate Connect/PIN/trust row below each main-screen indicator. Disconnected TV names/icons/dots form one 44-point tap target that retries connection or opens the required pairing/certificate screen. Pending connections disable repeat taps; connected indicators are informational. The action checks the selected device ID and current connection state before dispatching, preventing a stale tap from reconnecting or disconnecting another TV. The indicators retain the side-by-side arrangement, one-line names and green/gray dots. Settings retains explicit connection buttons.

Expanded Apple TV remote uses the Standard navigation pad dimensions: a 228-point circular D-pad with the same internal control sizes/gaps, or a full-content-width touchpad 228 points high with 28-point corners. Regular Apple TV remote retains its 200-point circular pad. Expanded Back/Home/Play/Mute controls remain 76 points, the vertical rocker 76×176 points, horizontal gaps 36 points, vertical gaps 24 points and pad-to-button separation 32 points. The existing UI geometry assertions now check both expanded pad modes against Standard dimensions. Saved layout/pad preferences, gesture cancellation and routing remain unchanged.

The 31 core source/test inputs match the previous referenced suite: 171 retained cases, no core changes or reexecution. Native UI compilation and package checks are recorded separately below. Physical TV interaction and UI execution have not been performed in this release.

Native iOS 27 build-for-testing passed: all nine UI methods compiled, 44 native inputs unchanged. No simulator boot or UI execution. [Compile report](../audit/reproductions/atv-remote-0.3.19-ui-compile.json).

The arm64 unsigned iPhoneOS archive and IPA passed package verification. All 12 packaged files byte-match the archive and all 56 frozen inputs remain unchanged. DEBUG fixtures, artwork types and former separate connection-button identifiers are absent from the executable. The stable bundle identity is `local.roomremote.ios`, display name ATV Remote, minimum iOS 27. [Combined validation](../audit/reproductions/atv-remote-0.3.19-validation.json).

Download [ATV-Remote-0.3.19-unsigned.ipa](../Build/ATV-Remote-0.3.19-unsigned.ipa), 5,683,499 bytes. SHA-256: `3d49cc2ac37beb40b6fe8b25baaaf482fa861bd3f6731439e49ab67e65be9c78`. Sign with your sideloading tool or archive the updated source with your paid team for TestFlight.
