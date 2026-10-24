# ``SwiftATV``


Room Remote final review additionally limits power/audio/focus snapshot streams to the newest value and bounds unauthenticated SRP server public keys to 384 bytes and salts to 64 bytes before BigInt work. Two focused regressions cover these changes; the initial 488-test full-suite evidence is retained separately.
A Swift library for discovering, pairing with, and controlling Apple TV and
AirPlay devices.

## Overview

This Room Remote fork resolves pinned local dependencies on Apple platforms only. Companion framing/event queues, OPACK decoder depth/work, and RTI archive allocation are bounded; overflow closes the connection. Pair-verify preserves accessory signature verification and additionally requires M4 state 4. Encryption/write ordering is serialized on the NIO event loop. The app activates Companion only; the public upstream API remains intact.

Cancelling a Companion held button after button-down succeeds attempts one
bounded release on its original handler, then reports cancellation. Cleanup
never retries the press or reconnects. A closed session can prevent release.

SwiftATV is a Swift port of [pyatv](https://github.com/postlund/pyatv). It
exposes a unified ``AppleTVDevice`` interface that routes each command to the
highest-priority protocol that supports it. MRP provides protobuf-based direct
remote control, actively refreshed metadata, push updates, power, audio,
output-device mutation, and HAP pairing; AirPlay 2 can pair with HAP and tunnel
MRP traffic, including output-device mutation, when direct MRP is unavailable;
Companion provides modern app, keyboard text input/focus, best-effort touch,
power, audio-volume, and remote-control support. Connection setup is
deterministic for implemented control protocols and follows
``ConnectOptions/protocols`` for both setup attempt order and facade routing.
By default SwiftATV tries direct MRP, then AirPlay-tunneled MRP, then
Companion, and returns as soon as one usable protocol connects unless
``ConnectStrategy/allAllowed`` is requested. Companion-only
discoveries with reusable HAP credentials can still attempt AirPlay-tunneled MRP
on the default AirPlay port. The result
describes the primary protocol, active protocols, enriched setup attempts, and optional
setup diagnostics. ``ConnectOptions/requestTimeout`` bounds protocol TCP
connects and setup exchanges so a stalled service can fail and let fallback
continue. ``ConnectOptions/runtimeRequestTimeout`` bounds post-connect MRP and
Companion command request/response exchanges.

The facade tracks lifecycle per protocol. Closing or failing a non-primary
secondary protocol unregisters only that protocol; the device emits
`connectionLost` when the primary or last active protocol closes. Capability
availability is state-backed, so optional Companion and MRP surfaces are
reported unavailable until setup, events, or successful requests prove them
usable. Output-device list and mutation capabilities become available when direct
MRP or AirPlay-tunneled MRP reports route state.

``ATVSettings/clientIdentity`` describes the local controller or app identity
sent during pairing and protocol setup, including the stable Companion Rapport
identifier sent in `_systemInfo`. It must not be copied from the target Apple
TV's identifiers. ``ATVSettingsVault`` is a pure Codable helper for storing
settings under every known device identifier and merging alias records as
discovery data changes.

Discovery resolves Bonjour TXT records with each live service, merges services
by stable device identifiers, including Companion-only TXT identifiers, and can
optionally return scan diagnostics for non-fatal browser, resolver, or empty-TXT
failures. Filtered and unfiltered scans include sleep-proxy discovery so
sleeping devices can be marked with ``AppleTVConfiguration/deepSleep`` when
Bonjour provides a usable device identifier.

SwiftATV requires Swift 6.3 or newer.

All public methods are typed-throws (`async throws(ATVError)`), so you can
catch `ATVError` exhaustively without worrying about stray NIO or CryptoKit
errors leaking through.

```swift
import SwiftATV

let devices = try await ATVClient.scan(timeout: 5)
guard let device = devices.first else { return }

let connection = try await ATVClient.connect(device)
let atv = connection.device
try await atv.remoteControl.home()
try await atv.remoteControl.play()
await atv.close()
```

> Important: SwiftATV is pre-1.0. The API may change as protocol internals
> evolve. Pin a release version or exact revision in
> your `Package.swift` and review the [CHANGELOG](https://github.com/jakejarvis/swift-atv/blob/main/CHANGELOG.md)
> before upgrading.

## Topics

### Getting started

- ``ATVClient``
- ``ConnectOptions``
- ``ConnectStrategy``
- ``ConnectResult``
- ``ConnectAttempt``
- ``ConnectCredentialSource``
- ``ProtocolSetupDiagnostic``
- ``defaultProtocolRequestTimeout``
- <doc:GettingStarted>

### Discovery

- ``ATVScanner``
- ``BonjourServiceType``
- ``ATVScanResult``
- ``ATVScanDiagnostic``
- ``ATVScanDiagnosticKind``
- ``AppleTVConfiguration``
- ``ServiceInfo``
- ``EffectivePairingStatus``
- ``ServiceConnectability``
- ``ServiceConnectabilityStatus``
- ``DeviceInfo``

### Device control

- ``AppleTVDevice``
- ``RemoteControl``
- ``PowerController``
- ``AudioController``
- ``ATVMetadata``
- ``PushUpdater``
- ``DeviceEvent``
- ``KeyboardController``
- ``TouchController``
- ``AppsController``
- ``UserAccountsController``
- ``CapabilityProvider``
- ``MediaCommandController``
- ``Capability``
- ``CapabilityInfo``
- ``CapabilityState``
- ``RemoteCapability``
- ``MediaRemoteCommand``
- ``MediaCommandInfo``
- ``MediaCommandOptions``
- ``MetadataCapability``
- ``PushCapability``
- ``StreamCapability``
- ``PowerCapability``
- ``AudioCapability``
- ``AppsCapability``
- ``AccountsCapability``
- ``KeyboardCapability``
- ``TouchCapability``

### Pairing and authentication

- ``PairingHandler``
- ``PairingResult``
- ``PairingCodeDirection``
- ``CompanionPairingHandler``
- ``CompanionPairVerifyHandler``
- ``MRPPairingHandler``
- ``AirPlayPairingHandler``
- ``HAPPairSetupHandler``
- ``HAPPairVerifyHandler``
- ``HAPCredentials``

### Protocols

- ``ATVProtocol``
- ``ATVSettings``
- ``ATVSettingsVault``
- ``ATVSettingsVaultRecord``
- ``ClientIdentitySettings``
- ``ProtocolSettings``
- ``AirPlaySettings``
- ``CompanionSettings``
- ``MrpSettings``
- ``AirPlayVersion``
- ``MrpTunnelMode``
- ``CompanionService``
- ``CompanionProtocolHandler``
- ``CompanionConnection``
- ``CompanionKeyboard``
- ``CompanionRemoteControl``
- ``CompanionApps``
- ``CompanionUserAccounts``
- ``CompanionPower``
- ``CompanionAudio``
- ``CompanionTouch``
- ``CompanionCapabilities``
- ``CompanionMediaCommands``
- ``MRPService``
- ``MRPConnection``
- ``MRPPlayerState``
- ``MRPRemoteControl``
- ``MRPMetadata``
- ``MRPPushUpdater``
- ``MRPPower``
- ``MRPAudio``
- ``MRPCapabilities``
- ``MRPMediaCommands``
- ``MRPFrameType``
- ``MRPMessageType``
- ``MRPConnectionState``
- ``MRPVarint``

### Support types

- ``OPACK``
- ``TLV8``
- ``ChaCha20Cipher``

### Errors

- ``ATVError``
- ``TimeoutContext``
- ``ConnectionAttemptError``

Room Remote Apps compatibility fix: `CompanionApps` registers the documented
`TVRCSessionStart` request with `ProtocolVersionKey: "1.2"` before list/launch
requests on its original session handler. A controller-scoped coordinator shares in-flight registration, caches success/known unsupported, and allows only a scoped registration timeout to be retried on a later explicit Apps call. Only a `No request handler` rejection
or a timeout specifically for that optional registration is tolerated; other
protocol/authentication/connection/cancellation failures propagate. App-list
responses require a real `_c` dictionary of unique bundle IDs and display names.
Launch acknowledgements validate `_ec`/`_ed`/`_eu` and `_rT: 8` error envelopes;
invalid replies never become empty-list/success results. Twelve focused tests
cover request ordering, primary-documented replies, error envelopes, optional
registration, and terminal errors without contacting a television.

Primary references: [pyatv protocol documentation](https://pyatv.dev/documentation/protocols/#companion),
[merged compatibility change #2855](https://github.com/postlund/pyatv/pull/2855),
and [reported app-launch error envelope #2868](https://github.com/postlund/pyatv/issues/2868).
This local implementation still needs retesting on the user's physical TV.
