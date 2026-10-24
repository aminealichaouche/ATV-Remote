# Xfinity Stream restart shortcut audit

Initial audit on 2026-10-12; 0.3.22 follow-up on 2026-10-13. The first-preset sections describe the earlier confirmation-based implementation; the final section describes the current release. This is a local source and primary-reference review; no television was connected or controlled during the audit.

## What is supported

Apple documents force quitting through the app switcher: double-press the TV button, navigate to the intended app, and swipe upward. Back/Menu exits the switcher. The app can then be opened again. This establishes a real remote gesture workflow, rather than a direct application-termination command. [Apple TV force-quit guide](https://support.apple.com/guide/tv/force-quit-an-app-atvb39f389ec/tvos).

The locally vendored Companion implementation exposes the necessary commands: `remoteControl.home(action: .doubleTap)` sends the TV/Home HID button (7), `touch.swipe(...)` sends touch press/move/release events, `remoteControl.menu(action: .singleTap)` sends Back/Menu (5), and `apps.launchApp(bundleID:)` launches a specific installed bundle. The app's ordinary Home button deliberately uses Menu hold to reach the Home Screen; that mapping must not be reused for the shortcut's app-switcher step. [Primary Companion protocol reference](https://pyatv.dev/documentation/protocols/#companion).

No direct force-quit-by-bundle-ID command or app-switcher focus query is exposed by the app's Companion-only transport. The primary pyatv application-close feature request remains open; its author reports a button-based workaround. This supports the feasibility of remote gestures, but does not establish a way to verify a specific process was terminated. [pyatv issue 2349](https://github.com/postlund/pyatv/issues/2349).

## Identifying Xfinity Stream

Apple's public App Store lookup with `entity=tvSoftware` returns app 731629156, title Xfinity Stream, bundle ID `com.comcast.cim.x2`, tvOS version 1.16.1, and minimum tvOS 18.2. The tvOS entity matters: the default software lookup returns the iPhone version instead. A compact timestamped record and full-response hash are retained at [xfinity-stream-tvsoftware-metadata.json](../audit/reproductions/xfinity-stream-tvsoftware-metadata.json). [Apple tvOS metadata](https://itunes.apple.com/lookup?id=731629156&country=us&entity=tvSoftware), [official App Store listing](https://apps.apple.com/us/app/xfinity-stream/id731629156?platform=tv).

The preset should fetch the selected Apple TV's current launchable-app list and require that exact ID. If absent, show that Xfinity Stream is not installed and send no launch or dismissal gesture. A display-name match alone is unnecessary and less precise. Matching the installed app by verified bundle ID also keeps this independent of each TV's star configuration.

## Recommended first preset

Ship one native built-in preset named **Restart Xfinity Stream** in the app. The top-right Shortcuts control opens that preset; no external shortcut file, server, or Apple Shortcuts installation is required.

1. Bind the entire run to the selected Apple TV's identity and connection generation. Require a connected Companion session, available touch-swipe capability, and a touch controller before launching anything.
2. Fetch the installed app list, require `com.comcast.cim.x2`, launch it, allow the launch animation to settle, double-press the TV button, then allow the switcher animation to settle.
3. Pause with a simple **Close and reopen** button and an instruction to confirm Xfinity Stream's card is centered on the TV. If needed, use the normal remote to move the card into focus before confirming.
4. After confirmation, send one upward swipe, allow dismissal to settle, exit the switcher using Back/Menu, and relaunch the same bundle ID on the same original TV.

The confirmation is needed because neither a successful launch acknowledgement nor an elapsed animation delay proves which card is currently selected. Another controller, a system overlay, or an unexpected UI state can change focus. A blind automatic dismissal could close another app. Waiting alone does not solve this.

Capability gating can use `service.capabilities?.capabilityInfo(.touch(.swipe)).state == .available` plus `service.touch != nil`. `CompanionService.setup()` sets both from successful `_touchStart`; optional touch-setup failure preserves ordinary button control but makes this gesture unavailable.

Do not queue other app-changing commands while preparing or completing the workflow. Abort on app backgrounding, sheet closure, changed TV selection, lost connection, cancellation, or an error. In particular, never retry a dismissal gesture automatically or reconnect and continue its remaining steps. Cancellation must be checked between every awaited step; the run must never switch to a different Apple TV.

## Touch implementation and outcome limits

The vendor currently interpolates within 0–1000 coordinates, sends an initial press, waits 16 ms between events, and sends a final release. Its initial press-to-move delay avoids the specific timing flaw described in the currently open upstream swipe report. That report concerns inconsistent gestures on physical hardware and remains a reason to test this preset on the user's tvOS version. [pyatv swipe issue 2914](https://github.com/postlund/pyatv/issues/2914).

The existing vendor `swipe` helper ignores cancellation of its inter-event sleeps, and the one-way event sender does not check task cancellation. For this workflow, use its existing `touch.action(x:y:mode:)` API with a checked, bounded upward sequence instead of changing the frozen vendor's public API. Check the captured target and generation between frames and use cancellable sleeps. If a press has already been sent, cancellation or an error attempts one release on that original touch controller at the last coordinate, then propagates the error. Cleanup must not send a new press, retry the swipe, or reconnect.

The implementation waits for that original local event write and keeps the driver's operation reservation until it finishes. It does not add a wall-clock deadline to the vendor's one-way NIO writer. Timing out and leaving a release running could let it arrive during a new gesture, so a deadline would also require safely retiring the original connection. A pathologically stalled write can keep the driver busy; explicit reconnection closes the original service. This is a remaining transport limitation, not a claim of bounded hardware acknowledgement.

An upward swipe should move from a larger Y value to a smaller Y value at fixed X, for example `(500, 850)` to `(500, 150)` over a few hundred milliseconds. A release may itself finish an already started gesture; cancellation cannot undo events already delivered. The gesture is sent as events and provides no acknowledgement that tvOS dismissed a card. Launch acknowledgements likewise establish command acceptance, not visual success. A success label such as **Xfinity Stream reopened** accurately describes completion of the workflow's launch request; it must not claim a verified process termination.

Meaningful local checks should cover installed-ID matching, no commands for a missing app or unavailable touch, ordered prepare/confirm/close/relaunch stages, one dismissal per confirmation, cancellation, errors, and selection/session changes. Local tests can establish ownership and command ordering. Physical testing must verify that the app switcher opens, Xfinity's card is selected or can be selected, the swipe dismisses it once, and relaunch returns to Xfinity Stream.

## Local files reviewed

- `Vendor/SwiftATV/AGENTS.md` and its frozen-fork requirements.
- `Vendor/SwiftATV/Sources/SwiftATV/Protocols/Companion/CompanionProtocol.swift` HID values.
- `Vendor/SwiftATV/Sources/SwiftATV/Protocols/Companion/CompanionInterfaces.swift` remote, app, touch, and capability implementations.
- `Vendor/SwiftATV/Sources/SwiftATV/Protocols/Companion/CompanionService.swift` session and touch setup.
- `App/Sources/AppleTVDriver.swift` generation-bound send/list/launch ownership.

## 0.3.10 follow-up: incomplete dismissal

The user reported that the shortcut did not swipe up fully. Local source review confirms `_touchStart` advertises 1000 × 1000 and `_hidT` clamps both coordinates to 0…1000, matching [pyatv’s protocol documentation](https://github.com/postlund/pyatv/blob/master/docs/documentation/protocols.md) and [Companion implementation](https://raw.githubusercontent.com/postlund/pyatv/master/pyatv/protocols/companion/api.py). The previous (500, 850) → (500, 150) gesture covered 70% of that height over twenty 16 ms waits; its last movement was a release rather than a held endpoint. No coordinate-range mismatch was found.

Version 0.3.10 tunes this to one full-height flick: press at (500, 1000), twelve upward holds at 16 ms intervals through (500, 0), then wait 16 ms and release at that same endpoint. This increases distance and nominal speed, delivers the full movement before release, and keeps the initial press-to-move delay. The [upstream timing report](https://github.com/postlund/pyatv/issues/2914) identifies missing initial delay and endpoint instability as gesture problems; our previous code already had the initial delay. This change addresses the observed short dismissal with a stronger single gesture rather than claiming that timing report proves the cause.

[Apple’s current force-quit guide](https://support.apple.com/guide/tv/force-quit-an-app-atvb39f389ec/tvos) still directs the user to select the intended card and swipe upward. This guide does not specify a programmatic travel/speed threshold. The selected full-height flick is an implementation inference and needs retesting on the user’s Apple TV. It is not automatically repeated: a successful first dismissal would put a different card next in focus. The centered-card confirmation, original-session checks, passive cancellation and cleanup, and Back/launch ordering remain unchanged; no targeted process-kill API or dismissal acknowledgement was added.

The updated runner tests require a held endpoint and matching release, one press, monotonically upward in-range coordinates, thirteen cancellable waits, and exact relaunch. Two new tests cancel just before release or fail the release write; both perform cleanup only on the original endpoint and stop before Back or launch. These tests substitute transport and waits; they establish ordering and ownership, not hardware dismissal. See [0.3.10 validation](atv-remote-0.3.10-validation.md).

## 0.3.22 follow-up: one-pass macro and other apps

The user explicitly removed the Xfinity card-confirmation step. The current preset runs prepare and finish sequentially after one tap: fresh app list, exact-ID launch, one-second wait, TV double-tap, 600 ms wait, one 208 ms full-height flick, 500 ms wait, Back, 300 ms wait, exact-ID relaunch. There are no previous/next-card controls or second confirmation. This uses the inferred default focus of the newly launched app. Neither acknowledgement nor delay proves focus; another controller or overlay could cause the swipe to dismiss a different card. Physical testing remains necessary. Success now says **Xfinity Stream restart sent** below both shortcut controls.

**Restart current app** asks the user to identify the current app from that selected TV's installed list, then uses the same macro for the chosen bundle ID. A macro alone cannot recover an unknown ID after dismissing its card. Companion has no Metadata implementation in [pyatv's primary metadata documentation](https://pyatv.dev/development/metadata/); the [interface documentation](https://pyatv.dev/api/interface/) distinguishes the currently playing app from the currently active app. Playing-media or last-launched metadata is therefore not used as foreground identity. No additional protocol, credential or server is added. The choices are bound to the original TV/epoch and refreshed before macro effects. Invalid identifiers, missing apps and unavailable swipe support fail before launch or touch.

The driver reserves the original session for the complete run, checks cancellation and current identity between all awaits, blocks other command work, and never reconnects and continues or repeats a swipe. A failed/partial touch gets only one original-sender release. The existing scoped Companion HID timeout recovery may refresh the connection for future actions, but the run remains stopped. Tests verify one-pass sequencing, exact generic target relaunch, missing-app rejection, observer failure, cancellation and original-touch cleanup. They cannot prove a tvOS card dismissal.

Home's new double-tap and hold bindings use the TV button, distinct from the existing single Home's Menu hold. Apple documents [TV double-press for open apps](https://support.apple.com/en-bh/guide/tv/atvb701cadc1/tvos) and [TV hold for Control Center](https://support.apple.com/en-euro/guide/tv/atvb0a416871/tvos). Native gesture failure dependencies suppress duplicate single-tap dispatch, with captured type/device/epoch checks and VoiceOver actions. No vendor code is changed.
