# Apple TV Remote Source Audit

Do not adopt the linked Apple TV project unchanged. Its desktop app demonstrates direct Companion control and useful protocol separation, but missing peer authentication, parser failures, credential handling, and unresolved reuse licensing are blockers for this iPhone app.

Source snapshot: [alokdhir/appletv-remote at 28129f25bb9b466a3c4125b14edf8d7237599929](https://github.com/alokdhir/appletv-remote/tree/28129f25bb9b466a3c4125b14edf8d7237599929), committed 30 September 2026. Review date: 12 October 2026.

## Coverage and priority

The reusable `AppleTVProtocol` source was reviewed for pairing, cryptography, frame decoding, HTTP/RTSP, OPACK, MRP, transport lifecycle, and credential storage. Relevant desktop/CLI integration callers, package declarations, tests, and install/release scripts were inspected. The external BigInt implementation and Apple system-framework internals were not comprehensively audited. No app, installer, release binary, broad upstream suite, or device connection was run.

P1 is an adoption blocker; P2 is a material defect to fix before device use; P3 is a lower-impact completeness or portability concern. These priorities are not CVSS scores. Static findings describe the code path and conditions; only the explicitly listed offline parser outcomes were dynamically reproduced.

## Findings

| ID | Priority | Finding and required change |
|---|---|---|
| ATV-01 | P1 | Companion reconnect skips server signature verification. Verify the authenticated device identity and signature with the correct stored protocol-specific key before deriving an authorized session. |
| ATV-02 | P1 | The repository has no tracked license granting reuse of its own implementation. Resolve permission before copying or distributing it. |
| ATV-03 | P1 | OPACK nested open-ended dictionaries can loop forever, including a round trip through the repository’s own encoder. Enforce termination, progress, and nesting/work limits. |
| ATV-04 | P2 | Oversized integer lengths and transaction identifiers can trap rather than return decoding errors. Validate every conversion and addition. |
| ATV-05 | P2 | Pair-setup M6 accepts a returned identity/key without checking its Ed25519 signature. Verify the signed identity before persisting credentials. |
| ATV-06 | P2 | An out-of-order pair-verify completion can publish connected without a verifier or session keys. Require an explicit expected stage and installed authenticated keys. |
| ATV-07 | P2 | Credentials are plaintext files; the AirPlay pairing CLI prints private credentials. Use Keychain and remove secret-bearing diagnostics. |
| ATV-08 | P2 | HTTP/RTSP parsing permits negative body lengths. Reject negative, oversized, overflowing, or incomplete bodies. |
| ATV-09 | P2 | MRP send paths share mutable cipher state across queues. Serialize nonce allocation, encryption, and sends as one session-owned operation. |
| ATV-10 | P2 integration | The product is macOS-only, with desktop UI/IPC/platform assumptions. A reusable core is not proof of an iOS-ready library. Build a platform-isolated adapter and validate on iOS. |

### ATV-01 Companion peer authentication

[CompanionPairVerify.swift:72–83](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/CompanionPairVerify.swift#L72) decrypts the peer’s ephemeral-session identity, then deliberately skips the server signature check. The source’s comment treats client authentication and encryption as sufficient for a personal app; they do not establish that the peer is the paired TV. The declared `signatureInvalid` error is not used here. [verifyM4:110–117](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/CompanionPairVerify.swift#L110) accepts a response without validating the expected state beyond checking an error field.

The risk is peer impersonation if an attacker can redirect or replace the selected local endpoint. This is a security inference from the missing authentication check; no live impersonation or credential attack was performed. Resolve the documented difference between HAP and Companion identities by storing and verifying the correct keys, not by bypassing verification. Add invalid-signature, wrong-identity, missing-signature, and out-of-order-stage rejection tests.

### ATV-02 License and provenance

The pinned tree has no tracked LICENSE or NOTICE file. [README.md:273](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/README.md#L273) credits pyatv’s MIT license; that statement does not grant a license to this repository’s own code. Obtain an explicit license or separate reuse permission and retain any upstream notices. This is an unresolved reuse condition, not a legal opinion or a request to contact the author.

### ATV-03 OPACK termination and encoder mismatch

[OPACK.swift:541–564](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/OPACK.swift#L541) re-scans a decoded nested dictionary to advance its cursor. Its open-ended loop has no end-of-buffer or cursor-progress exit. The decoder can return a dictionary for truncated input, after which `skipValue` at EOF makes no progress and the loop does not terminate. The general encoder uses the open-ended dictionary tag for 15 entries without the required terminator, so a nested 15-entry dictionary created by the implementation itself reaches the same hang.

Both cases timed out in bounded two-second offline probes. Add an explicit terminator requirement, a single decoder that returns bytes consumed, a progress invariant, and a global nesting/work budget. The depth cap in a skip helper does not protect every recursive decode path.

### ATV-04 Numeric conversions

[MRPMessage.swift:200](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/MRPMessage.swift#L200) and [line 237](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/MRPMessage.swift#L237) convert an unsigned wire length to `Int` before proving it fits and before safely adding it to the offset. An oversized length trapped in an isolated parser probe. [CompanionSession.swift:497](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/CompanionSession.swift#L497) similarly casts a decoded transaction `Int` to `UInt32` without range checks. Negative or excessive values can trap in that code path; this second case was established statically.

Use exact checked conversions, subtraction-based remaining-byte bounds, and explicit maximum message sizes. Avoid validating only after arithmetic that can already trap.

### ATV-05 Pair-setup identity validation

[HAPPairing.swift:119–132](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/HAPPairing.swift#L119) stores the M6 identifier and long-term public key without extracting and verifying the accessory signature. The earlier SRP server-proof check is present; the M6 omission is a distinct missing identity-consistency check, not proof that PIN pairing can be bypassed by an arbitrary unauthenticated peer. Validate the protocol’s signed M6 material and fail before saving any credential on mismatch.

### ATV-06 Pairing state transition

[PairingFlow.swift:161–168](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/PairingFlow.swift#L161) uses an optional verifier call, optionally installs keys, and unconditionally publishes connected. A validly tagged unsolicited completion after reset can therefore report connected with no authenticated keys. Require a live verifier, the expected previous step, and both validated keys before transitioning.

The reset test in [PairingFlowTests.swift:125](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Tests/AppleTVProtocolTests/PairingFlowTests.swift#L125) uses a payload whose tag does not identify the state field. It does not exercise the vulnerable completion branch. The assertion itself is sensible; the fixture misses the intended state path.

### ATV-07 Secrets and storage

[CredentialStore.swift:73–85](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/CredentialStore.swift#L73) and [111–123](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/CredentialStore.swift#L111) write serialized secrets as plaintext JSON. The explicit `0600` in the file is for lock-file creation, not for these JSON writes; the JSON mode depends on filesystem behavior and process permissions. Do not treat the README’s file-permission claim as enforcement by the save path.

[Sources/atv/main.swift:558–559](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/atv/main.swift#L558) prints `pyatvString` during ordinary AirPlay pairing. [AirPlayPairing.swift:38–41](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/AirPlayPairing.swift#L38) includes the long-term private key in that string. Captured terminal logs or shared support output can expose it. Replace storage with iOS Keychain and exclude keys, PINs, tokens, raw pairing frames, and typed text from logs/export.

### ATV-08 HTTP and RTSP body validation

[AirPlayHTTP.swift:287–290](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/AirPlayHTTP.swift#L287) and [EncryptedAirPlayRTSP.swift:284–288](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/EncryptedAirPlayRTSP.swift#L284) accept a signed integer Content-Length. A negative value satisfies the available-byte comparison and creates a reversed range. This is a statically identified trap path; no network test was run. Also bound header/body accumulation and reject invalid length syntax instead of treating it as an empty body.

### ATV-09 Cipher and queue isolation

[MRPDataChannel.swift:165–181](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/MRPDataChannel.swift#L165) calls the session encryptor for outgoing commands; [sendReply:279](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/MRPDataChannel.swift#L279) calls the same encryptor from the receive path. The desktop caller dispatches sends on a separate [mrpSendQueue:947](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVRemote/CompanionConnection.swift#L947). [HAPSession.swift:96–102](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/HAPSession.swift#L96) mutates the write counter without a synchronization boundary shared by these callers.

This is a concurrency defect and a potential cipher-nonce/order risk, rather than a dynamically demonstrated nonce reuse. An actor or serial queue must own both encryption and the corresponding send order. Add concurrency validation that proves unique ordered counters across commands and acknowledgements; `@unchecked Sendable` is not synchronization.

### ATV-10 Portability and dependencies

[Package.swift](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Package.swift) declares macOS 13 only. The desktop target uses AppKit, menu-bar UI, Unix IPC, and Mac-specific lifecycle assumptions. Its separate protocol target is useful architecture, but an iOS build and physical-device test are still required. A package manifest declaration alone would also be insufficient to prove portability.

The BigInt dependency allows compatible versions starting at 5.3.0; the tracked [Package.resolved](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Package.resolved) pins 5.7.0 at `e07e00fa1fd435143a2dcf8b7eec9a7710b2fdfe`. This pin is evidence of intended resolution, not a complete dependency-security audit. Install scripts copy into Applications and CLI paths; release scripts sign/notarize and publish. They were read, not executed, and are irrelevant to the new iPhone build.

## Offline validation

The included [parser runner](../audit/reproductions/apple-parser-repro.py) compiles only four reviewed pure parser files, replacing the logging import with a no-op stub. It uses a fresh temporary directory, no dependency installation or package scripts, no sockets, and separate timeout-limited probes. [Recorded results](../audit/reproductions/apple-parser-results.jsonl) include source SHA-256 values.

| Probe | Observed outcome |
|---|---|
| Normal OPACK dictionary | Passed |
| Terminated open-ended nested OPACK dictionary | Passed |
| Unterminated nested OPACK dictionary | Two-second timeout |
| Nested 15-entry dictionary round trip | Two-second timeout |
| Normal MRP bytes field | Passed |
| Oversized MRP length | Swift integer-conversion trap, process exit -5 |
| Truncated TLV8 header | Rejected correctly |
| Companion payload over 1 MiB | Rejected correctly |

Run against the pinned source snapshot: `python3 audit/reproductions/apple-parser-repro.py /path/to/appletv-remote`. It is a bounded behavior check, not a whole-project test suite or a device compatibility test. Peer authentication was assessed from source; no forged-peer probe is part of the delivered validation.

## Adoption decision

Keep this project as an architectural and protocol reference. Its UI, API names, and successful normal fixtures show useful work, but do not override the defects above. Prefer the licensed SwiftATV candidate after app-specific hardening, Keychain integration, immutable dependency selection, and iOS/hardware validation. Use pyatv as a separate protocol reference and preserve its license notice where applicable.
