# Apple TV native-library audit

Audit date: 2026-10-12. Requirement: one native iPhone app, communicating directly with the Samsung TV and Apple TV on the home network, with no home server.

**Provisional choice: a pinned, hardened fork of `jakejarvis/swift-atv`, with Companion control first.** `nickustinov/itsytv-core` is smaller and declares iOS support, but concrete parser, authentication handling, concurrency, and license problems make it a poorer starting point. `postlund/pyatv` is a valuable protocol reference rather than the iPhone runtime.

This is a source review plus targeted runtime checks. It is not a security certification, an exhaustive review of all dependencies, or evidence of compatibility with the user's current tvOS version. During this upstream audit, no TV was contacted, credentials entered, app signed, global dependency installed, or IPA produced. The subsequent native implementation and unsigned IPA are described in [build validation](native-build-validation.md).

## Pinned sources

| Repository | Examined revision | Platform evidence | Decision |
| --- | --- | --- | --- |
| [swift-atv](https://github.com/jakejarvis/swift-atv) | `2cc34befa6826f3824846a73d0a1f674ee7688fe`, 2026-04-15, tag `0.4.0` | [Manifest](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/Package.swift) declares Swift 6.3, iOS 16+, macOS 13+, tvOS 16+; Apple builds use CryptoKit | Candidate requiring hardening and hardware verification |
| [itsytv-core](https://github.com/nickustinov/itsytv-core) | `052d9a9a0416d577119316ea813aa3b822b408e5`, 2026-07-02 | [Manifest](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Package.swift) declares Swift 5.10 and iOS 17+; source uses Network.framework, CryptoKit and Security | Reference only pending fixes and complete license |
| [pyatv](https://github.com/postlund/pyatv) | `b277a4c8222ecdcbaab8a24e3e713ca44765adb4`, 2026-06-19, release `0.18.0` | [Project metadata](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/pyproject.toml) requires Python 3.9+; asyncio, Python and native-library dependencies | Protocol reference; embedding Python adds unnecessary iOS packaging work |

Commits were read from fresh public clones, not inferred from search-result dates. Claims below refer to these revisions.

## Reproduced parser results

Only each library's reviewed Foundation-only OPACK source was compiled. SwiftATV's error enum was replaced with a minimal compatible stub for this isolated test. No package dependency was resolved or build plugin run. Each input was tested in a separate process under Apple Swift 6.4.

| Input | swift-atv | itsytv-core |
| --- | --- | --- |
| Normal one-character string | Decodes correctly | Decodes correctly |
| Blob tag `0x94`, followed by eight `0xff` length bytes | Throws “length too large” | Process crashes with SIGTRAP, exit `-5` |
| Endless array containing null, missing terminator | Rejects | Accepts truncated array |
| Null followed by another value | Rejects trailing bytes | Accepts first value and ignores remainder |

The committed [runner](../audit/reproductions/check-parsers.py), [harness](../audit/reproductions/parser-harness.swift), and [results](../audit/reproductions/parser-results.json) make these checks reproducible from clones at the listed commits. They do not test actual pairing, network delivery, tvOS behavior, or a signed iPhone app.

## Findings in itsytv-core

1. **High: malformed network payload can crash the decoder.** `OPACK.readLength` converts an arbitrary UInt64 to Int without a checked conversion; `readBytes` also adds offset and count before validating. The nine-byte payload above reproduces a crash. Reject nonrepresentable lengths and validate using remaining-byte subtraction. [Decoder, lines 377–390](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Protocol/OPACK.swift#L377).

2. **High: authenticated-decryption failure does not terminate frame processing.** `CompanionConnection.processBuffer` logs a decryption error, then still removes the frame and calls `onFrame` with its original ciphertext payload. Its cipher increments the nonce first, so continuing also desynchronizes the session. This was confirmed by source review, not an end-to-end attack demonstration. Drop the frame, fail pending requests, and close the session on authentication failure. [Connection, line 211](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Protocol/CompanionConnection.swift#L211), [cipher, line 26](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Crypto/CompanionCrypto.swift#L26).

3. **High: ciphertext length checks are missing in several crypto paths.** Companion pair-setup, Companion pair-verify, AirPlay pair-verify and Companion transport compute `count - 16` and use it as a prefix length without first requiring at least a 16-byte authentication tag. A short response can reach a negative-length collection operation instead of a recoverable protocol error. This is a static finding; the complete crypto exchanges were not reproduced. [Pair-setup, line 270](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Crypto/PairSetup.swift#L270), [pair-verify, line 105](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Crypto/PairVerify.swift#L105), [AirPlay verify, line 74](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/AirPlay/AirPlayPairVerify.swift#L74).

4. **Medium: pair-setup omits the server identity signature check.** The M6 handler decrypts and stores the server identifier and public key without reading or verifying its Ed25519 signature. Earlier SRP proof verification is present, so this finding does not mean the entire handshake is unauthenticated. Verify M6 before persisting credentials. [Pair-setup, lines 242–291](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Crypto/PairSetup.swift#L242).

5. **Medium: pair-verify success accepts M4 without rejecting an error TLV.** The manager looks at sequence `0x04` and enables encryption; the M4 branch does not inspect the HAP error field. Validate expected message state and errors before considering pairing verified. [Manager, line 726](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Protocol/AppleTVManager.swift#L726).

6. **Medium: shared connection and cipher state has no serialization boundary.** NWConnection callbacks run on a global queue, keep-alive runs on another global queue, and callers mutate pending-response dictionaries, transaction counters, connection references and nonce counters without a lock or actor. This creates potential races and duplicate encryption nonce use under concurrent sends; a dynamic race detector was not run. Move all session state onto one serial queue/actor. [Connection](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Protocol/CompanionConnection.swift), [cipher](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Crypto/CompanionCrypto.swift).

7. **Medium: network resource limits and strict decoding are incomplete.** Companion frames allow a 24-bit payload with no smaller application cap or incomplete-frame deadline. OPACK has no nesting budget, accepts missing endless-container terminators, and ignores trailing data. The latter two were reproduced. Request handlers are retained until response or disconnect with no per-request expiry in the connection class. Bound frames, nesting, outstanding requests, and decode time. [Frame parser](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Protocol/CompanionFrame.swift), [OPACK](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Protocol/OPACK.swift).

8. **Privacy and storage integration:** `CoreLog` marks every message `.public`; verbose mode can log device identifiers, hosts, payload descriptions and media metadata. Some debugging statements run at error/warning level even with verbose disabled. The optional app-icon helper sends bundle IDs/app-name queries to iTunes and downloads artwork URLs, so exclude it from a strictly local app. Keychain storage is present, but uses `WhenUnlocked` rather than `WhenUnlockedThisDeviceOnly`, a fixed upstream service name, and delete-then-add updates that can lose an existing credential if adding fails. Use the app's own Keychain wrapper, atomic updates, local-only accessibility, and private/redacted logs. [Logging](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/LogConfig.swift), [icons](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Utilities/AppIconFetcher.swift), [Keychain](https://github.com/nickustinov/itsytv-core/blob/052d9a9a0416d577119316ea813aa3b822b408e5/Sources/ItsytvCore/Crypto/KeychainStorage.swift).

## What swift-atv actually improves, and what remains

The inspected implementation verifies invalid SRP challenge values (`B mod N == 0`, `u == 0`), the server's SRP proof, the M6 server identity signature, and the server's stored identity/signature during pair-verify. It checks HAP error fields before enabling Companion encryption. Its Companion connection protects shared state, gives request waiters cancellation/timeout handling, and closes on failed authenticated decryption. These are code findings, not assurances derived from README claims. [SRP](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/Sources/SwiftATV/Auth/SRP.swift), [pairing](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/Sources/SwiftATV/Auth/HAPPairing.swift), [Companion verify](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/Sources/SwiftATV/Protocols/Companion/CompanionPairing.swift), [connection](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/Sources/SwiftATV/Protocols/Companion/CompanionConnection.swift).

Remaining adoption work:

- Cap incoming frame sizes and OPACK nesting/object budgets; the inspected recursive decoder has no depth limit. Prevent hostile discovery/pairing peers from exhausting memory or stack.
- Set a bounded buffering policy for event streams and an incomplete-frame timeout; otherwise a fast peer or slow consumer can accumulate work.
- Provide the application's own Keychain persistence. `ATVSettingsVault` is an encodable value container, not encrypted storage, and includes serialized private pairing material. Do not put this JSON in preferences, logs, cloud sync, or diagnostic exports. [Settings](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/Sources/SwiftATV/Settings.swift#L247).
- Add the native app's local-network permission handling, Bonjour declarations, app lifecycle reconnect behavior, and physical-device validation. Upstream CI covers macOS/Linux, not an iOS app. [CI](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/.github/workflows/ci.yml).
- Pin a commit and the complete dependency graph. The upstream manifest specifies version ranges and this checkout does not include `Package.resolved`; using a branch dependency introduces unreviewed changes.
- Start with Companion navigation, keyboard, playback and app launch. Introduce AirPlay/MRP metadata only after direct Companion pairing is proven on the user's Apple TV; validate volume through Samsung independently of Apple TV's audio-output configuration.

## License and provenance

`swift-atv` has an [MIT license](https://github.com/jakejarvis/swift-atv/blob/2cc34befa6826f3824846a73d0a1f674ee7688fe/LICENSE). Its README explicitly describes a pyatv port, and a byte comparison found 11 identical `.proto` files against pyatv 0.18.0. Its license only names its own author. Retain pyatv's [MIT copyright and permission notice](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/LICENSE.md), alongside SwiftATV's notice, for copied/derived material in any distributable fork. An acknowledgment link is not the full upstream notice. Preserve relevant dependency LICENSE/NOTICE files as well.

`itsytv-core`'s README says MIT and links `LICENSE`, but **no license file exists in this pinned tree**. The complete grant and copyright terms must be obtained/clarified before adopting or redistributing its code. Its README claim alone is not a reviewed full license. [Repository/README](https://github.com/nickustinov/itsytv-core/tree/052d9a9a0416d577119316ea813aa3b822b408e5).

The project metadata marks pyatv MIT, and its full notice is present. That makes it a useful reference; it does not make every implementation detail correct. For example, the inspected Companion pairing code reads the server SRP proof without using it in the final check, and pair-setup has an explicit unimplemented M6 signature check. SwiftATV's verification checks are therefore worth retaining instead of blindly matching the Python code. [Companion authentication](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/pyatv/protocols/companion/auth.py#L112), [HAP SRP](https://github.com/postlund/pyatv/blob/b277a4c8222ecdcbaab8a24e3e713ca44765adb4/pyatv/auth/hap_srp.py#L210).

These are notice/provenance observations, not a determination of App Store acceptance or third-party patent/trademark rights.

## Full-package validation

Dependency manifests were inspected before build execution. Validation used the pinned root source in a scratch copy with only its four remote dependency declarations replaced by local paths, with `SWIFTCI_USE_LOCAL_DEPS=1` for Apple transitives. Byte comparison confirmed that no implementation or test sources changed. The SwiftProtobuf build-tool plugin is not attached to SwiftATV's target; generated protobuf Swift sources are checked in. No protoc build/plugin was executed. Manifest review is not a complete security review of the dependencies' implementation.

The explicitly selected graph was SwiftNIO 2.97.1, Swift Crypto 4.3.1, SwiftProtobuf 1.36.1, BigInt 5.5.0, Swift Atomics 1.1.0, Swift Collections 1.1.0, Swift System 1.4.0 and Swift ASN.1 1.2.0. These are minimum allowed versions selected for this offline validation, not the latest graph an upstream version-range manifest would resolve. Exact commits, manifest hashes and applicable notice filenames are in [dependency-pins.json](../audit/reproductions/dependency-pins.json).

| Check | Outcome | Evidence |
| --- | --- | --- |
| SwiftATV library compile for arm64 iOS 16 simulator, using iPhoneSimulator27 SDK and Swift 6.4 | Passed, exit 0, in 45.79 seconds; simulator SwiftATV module exists | [Build log](../audit/reproductions/ios-simulator-build.log) |
| macOS XCTest suite | 386 of 395 passed under the tool sandbox; nine fake-server tests failed because creating a TCP listener returned EPERM | [Initial test log](../audit/reproductions/macos-tests.log) |
| The nine blocked fake-server tests, rerun with the already-built binary outside the network sandbox | All nine passed; no actual TVs contacted | [Rerun log](../audit/reproductions/macos-companion-loopback-tests.log) |
| Swift Testing suite | All 83 tests passed under the sandbox | [Initial test log](../audit/reproductions/macos-tests.log) |

All 478 unique upstream tests passed across these runs. The first run's environment failures are retained in the logs rather than described as a clean single-run result. The builds emitted warnings in older transitive dependencies, including private setters referenced by inlinable functions; these should be addressed when selecting and auditing a production dependency graph. [Recorded outcome and source-integrity check](../audit/reproductions/build-validation.json), [offline build reproduction script](../audit/reproductions/check-swift-build.py).

Neither an iOS library compile nor desktop unit tests demonstrate actual Apple TV compatibility. Required device gates remain: PIN pairing, persisted re-pair verification after app restart, navigation press/release, keyboard input, foreground reconnection after suspension and tvOS reboot/update behavior.
