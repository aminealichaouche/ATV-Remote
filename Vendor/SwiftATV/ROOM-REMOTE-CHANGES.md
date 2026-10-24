# Room Remote vendor changes


Room Remote final review additionally limits power/audio/focus snapshot streams to the newest value and bounds unauthenticated SRP server public keys to 384 bytes and salts to 64 bytes before BigInt work. Two focused regressions cover these changes; the initial 488-test full-suite evidence is retained separately.
This is the Room Remote local Apple-platform fork of upstream revision
`2cc34befa6826f3824846a73d0a1f674ee7688fe`. All dependency manifests resolve
only to pinned sibling folders (see `../revisions.json`). Linux builds are not
supported by this fork: system CryptoKit replaces the Linux Crypto dependency.
The app enables only Companion; retained AirPlay/MRP sources are compiled for
upstream API compatibility but are not connection fallbacks in Room Remote.

Companion inputs are limited to 1 MiB per frame, 2 MiB pending receive data,
64 queued frames/events/delegate deliveries, OPACK nesting depth 32, 32,768
OPACK nodes, and 16 MiB-equivalent scalar-comparison work. Overflow closes the
connection. RTI archives are limited to 256 KiB and 4,096 object-table entries;
Foundation handles binary-plist deserialization, with 16-byte session UUIDs
and 64 KiB maximum text context. Outbound encryption and write enqueueing run
on one event loop to preserve nonce order. Pair-verify requires explicit M4
state 4 in addition to the existing accessory identity/signature validation.

Runtime-only SwiftProtobuf manifest omits protoc executables and package plugins.
Checked-in generated MRP Swift is retained. No upstream release/build scripts
are used. Original dependency sources and license notices are preserved.
`UPSTREAM-PYATV-LICENSE.md` preserves the ported reference implementation's MIT
notice. There is no change to the library's public API.

Validation: 488 tests passed on the macOS host (395 XCTest and 93 Swift Testing,
including ten new RoomRemoteSecurityTests). Companion fake-device integration
tests use local loopback sockets; no real televisions were contacted.

The first native build still needs physical Apple TV PIN pairing and actual
command tests. Protocol maintenance is a community implementation; compiling
or passing fixture tests does not certify compatibility with every tvOS release.

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

ATV Remote 0.3.1 maps its Home action to Companion Menu hold (HID 5 down,
one second, up), the Back/Menu gesture documented by Apple for the tvOS Home
Screen. The separate library Home/TV action retains its existing semantics.
Cancelling a hold after button-down succeeds attempts exactly one bounded
release on the captured original handler before propagating cancellation;
it never retries button-down, reconnects, or routes cleanup to another TV.
Closing the original session can prevent that best-effort release. Three
encrypted loopback regressions check real HID ordering/timing and cancellation
during the hold or release acknowledgement. Physical Home Screen behavior
still needs testing on the user's Apple TV.

References: [Apple tvOS 27 navigation guide](https://support.apple.com/en-ca/guide/tv/atvbe55a4b4e/27/tvos/27)
and [maintained pyatv Companion hold implementation](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/companion/__init__.py).


## ATV Remote 0.3.38 foreground liveness

`CompanionService.verifyConnection(timeout:)` is a new public, timeout-bounded check on the existing authenticated handler. It repeats the required `_systemInfo` exchange using the same saved client identity, and sends no HID, session, touch, app-launch or power commands. It is used once when the app returns to the foreground. FetchAttentionState is intentionally avoided: upstream reports unsupported/silently dropped replies on recent tvOS (https://github.com/postlund/pyatv/issues/2845). Three Swift Testing cases use the authenticated loopback fixture to verify identity/session reuse, a missing-response deadline, and cancellation without reconnecting.
