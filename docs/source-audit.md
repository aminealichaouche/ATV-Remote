# Remote App Source Audit and Adoption Decisions

Use a native iOS 27 app with a small original Samsung adapter and a pinned, hardened SwiftATV Apple TV adapter. The app can run directly on the iPhone without a bridge. Neither of the two supplied projects is suitable to adopt unchanged.

The review covers six remote-control implementations, relevant pyatv authentication/protocol sources, dependency and license declarations, selected dependency manifests, and bounded offline tests. Source snapshots are pinned to commits rather than moving README claims. “Audited” here means the stated source-review and validation scope, not a blanket assurance that a project, every dependency, or every firmware combination is secure.

The native controller has now been implemented and its unsigned iPhone IPA built. The upstream findings below remain findings about those pinned snapshots. Local SwiftATV hardening, original Samsung code, app routing checks, and final build evidence are recorded in [native build validation](native-build-validation.md).

## Project decisions

| Project | Decision | Main evidence |
|---|---|---|
| [alokdhir/appletv-remote](https://github.com/alokdhir/appletv-remote/tree/28129f25bb9b466a3c4125b14edf8d7237599929) | Protocol/architecture reference; reject unchanged | Skipped Companion server signature verification; reproducible OPACK hangs and MRP length crash; plaintext/printed credentials; no repository reuse license; macOS app |
| [pedrinho/samsung_remote](https://github.com/pedrinho/samsung_remote/tree/2c561a699045159b6447f8165abcdcb893fdd601) | Protocol reference; reject as app foundation | Pinned published Samsungctl lacks the API called by the wrapper; conflicting requirements; no robust persistent pairing model; inaccurate success reporting; Python CLI |
| [jakejarvis/swift-atv](https://github.com/jakejarvis/swift-atv/tree/2cc34befa6826f3824846a73d0a1f674ee7688fe) | Best Apple TV candidate, conditional on hardening | Actual pairing signature checks, bounded/cancellable requests, failed-decryption closure, strict malformed-input handling, native iOS compile; remaining resource limits and license-notice work |
| [nickustinov/itsytv-core](https://github.com/nickustinov/itsytv-core/tree/052d9a9a0416d577119316ea813aa3b822b408e5) | Reference only | Reproduced length crash; missing identity-signature and short-ciphertext checks; processing continues after decrypt failure; shared-state races; missing LICENSE despite README claim |
| [wdesimini/TVCommanderKit](https://github.com/wdesimini/TVCommanderKit/tree/4c7b27aefe308a1a514f676a8db3cd56ec439f0d) | Native Samsung reference; reject unchanged | Default certificate trust accepts everything; moving Starscream dependency; opaque SmartView discovery binary; queue/lifecycle and command coverage gaps |
| [yuri-rod/smart-tv-remote-swift](https://github.com/yuri-rod/smart-tv-remote-swift/tree/0b78b61a59c153f6b8b7b9010b1a6fbc61cd6670) | Native Samsung reference; reject unchanged | First text frame treated as authenticated; unrestricted certificate acceptance; token/connection races; broad subnet probing; narrow tests pass despite these gaps |

These are adoption decisions for this app, not claims that every feature in a rejected project is unusable. The linked reports include exact code locations, failure conditions, fixes, and qualifications:

- [Linked Apple TV project audit](apple-source-audit.md)
- [Linked Samsung project and native alternatives audit](samsung-source-audit.md)
- [Apple TV alternatives and dependency audit](alternatives-audit.md)

## Important findings

The linked Apple TV implementation explicitly omits verification of the server's pairing signature. Ephemeral encryption and authenticating the client do not establish the identity of the TV peer. The app must verify the correct protocol-specific paired identity before enabling commands. The missing check was established from source; no live impersonation test was performed. [Pinned verification path](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/CompanionPairVerify.swift#L72)

Its OPACK decoder hangs on malformed nested open-ended data and on a nested dictionary produced by its own 15-entry encoder. Its MRP parser traps on a nonrepresentable wire length. These were reproduced with isolated reviewed parser files, without installing dependencies, running project installers, or contacting a TV. A frame size cap exists in one Companion parser, but it does not protect all integer and nested-parser paths. [Pinned nested decoder](https://github.com/alokdhir/appletv-remote/blob/28129f25bb9b466a3c4125b14edf8d7237599929/Sources/AppleTVProtocol/OPACK.swift#L541)

The Samsung Python project pins Samsungctl 0.7.0 while using `samsungctl.Config`, absent from that published release. Its alternate requirements describe an unavailable published beta, while a suggested GitHub fork changes behavior. The wrong fixed default port is an additional portability flaw, but the newer fork can override it; the dependency/API mismatch is the definite failure under the declared published pin. [Dependency and runtime details](samsung-source-audit.md#sam-01--p1-published-dependencies-do-not-match-the-source-api)

Both Samsung Swift candidates accept certificates without authenticating the selected peer. SmartCast also treats any first text message as successful connection, including denial or unrelated events. This app needs device-scoped trust/pinning and an explicit approval/token state machine, not a successful socket upgrade alone. [Native Samsung findings](samsung-source-audit.md#native-swift-candidates)

The Apple TV candidate has concrete strengths in its source and tests, but still needs bounds on frame buffering, recursive decode work, event streams, and app-owned Keychain persistence. Its pyatv-derived protobuf sources also require preserving pyatv's notice. The Python reference itself has authentication omissions in the reviewed paths, so matching it is not sufficient validation. [Candidate details and provenance](alternatives-audit.md)

## Completed validation

| Check | Evidence and limits |
|---|---|
| Supplied Apple parser probes | Eight bounded probes: valid fixtures pass, two OPACK probes time out, oversized MRP length traps, truncated TLV and oversized Companion frame reject. [Results](../audit/reproductions/apple-parser-results.jsonl) |
| Apple alternative parser comparison | Both decode a normal fixture; SwiftATV rejects oversized length, unterminated array, and trailing data; Itsytv crashes or accepts malformed input. [Results](../audit/reproductions/parser-results.json) |
| Supplied Samsung Python probes | Five offline checks establish API incompatibility, bad default propagation, false success, no-argument error, and success exit after failed command. Socket and URL access blocked; no full Python-suite pass claimed. [Samsung validation record](../audit/reproductions/samsung-validation.json) |
| TVCommander helpers | Two inspected Swift source files compiled for URL/key/wake encoding checks; full opaque-binary package not built or certified. |
| SmartCast package | macOS build and all 12 upstream pure tests passed; pairing, certificate authentication, iOS permissions, and hardware behavior remain untested. |
| SwiftATV native build and unit suite | iOS simulator library compilation passed with unchanged implementation sources and an explicit local floor dependency graph. All 478 unique upstream tests passed across the sandboxed suite and an isolated rerun of nine local fake-server tests initially blocked by the sandbox. [Build/test details](alternatives-audit.md#full-package-validation). This does not validate a signed iOS app or actual Apple TV. |
| Interface preview | Device routing, action-only mute, sheets, PIN validation, simulated approval, text clearing, total reconnect, partial Samsung outage, unavailable keyboard, and pad switching passed at widths 320, 390, and 736 in light/dark appearance, with no JavaScript exceptions or horizontal overflow. [UI results](../design/qa/results.json) |

The interface was visually inspected at phone widths. It is a simulation of the proposed native app. It stores no device credentials, contacts no devices, and does not stand in for native SwiftUI accessibility or hardware tests.

## What requires further validation

The six reviewed source trees and selected dependency manifests do not establish a complete transitive vulnerability assessment. No complete SmartView binary audit, penetration test, formal cryptographic proof, independent BigInt/Apple framework audit, App Store assessment, firmware compatibility certification, or physical-TV test was performed. The reports distinguish a static defect, a bounded reproduction, a build, and a hardware claim.

Before hardware compatibility can be claimed, verify Apple PIN pairing and authenticated reconnect on the user's current tvOS; Samsung deny/allow/token rotation and device-specific TLS trust; Keychain persistence/deletion; foreground resume and Local Network denial; exact Samsung hardware model; actual navigation, sound, text/app, and power capabilities. The local implementation now bounds inputs and command ownership. Optional SSDP/broadcast wake would require the correct iOS entitlement and is not implemented. See [remaining hardware validation](app-design.md#compatibility-and-remaining-validation).

## Resulting design

Apple TV navigation and Samsung volume share one screen. Setup pairs each device independently. Power actions are explicit and expire on disconnection. The app keeps secrets in Keychain, redacts diagnostics, verifies peers, and confines each session's network/crypto state to a serial owner. No cloud service or home bridge is required by the proposed architecture.

The native first test build uses the hardened MIT SwiftATV candidate and an original Samsung adapter. Its unsigned IPA is ready for the user's sideloading tool to sign. The next validation step is pairing and observing commands on each physical TV; no physical TV or iPhone hardware test has been performed here.
