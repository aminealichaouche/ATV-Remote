# ATV Remote 0.3.38 (41) validation

Returning from the background preserves established green indicators while immediately checking the existing sessions. Apple TV repeats the required authenticated `_systemInfo` exchange with unchanged client identity; Samsung uses a correlated WebSocket ping/pong. Each check has a two-second response limit, checks run concurrently, and no button, power, session-setup, touch-setup or app-launch commands are sent. A failed response marks only that connection unavailable; selected TVs remain eligible for automatic reconnection. Regular local transport readiness checks continue every three seconds while active.

Apple TV’s optional FetchAttentionState query is deliberately excluded from liveness checks: [upstream reports describe missing replies on recent tvOS](https://github.com/postlund/pyatv/issues/2845). `_systemInfo` already has to succeed during this app’s authenticated setup. Repeating it still needs hardware validation on the user’s firmware.

Room selection retains connected driver actors keyed by TV identity and reuses them when returning. It cancels incomplete setup and commands, not established sessions. State callbacks continue for unselected connected TVs. Per-TV observation tokens reject callbacks and foreground-check results from replaced actors; command epochs still bind input to the selected TV. Auto can reuse a retained healthy room. Explicit Disconnect, Re-pair, Remove and changed IP addresses invalidate only the relevant TV. Existing manual-disconnect holds remain respected.

This lifetime is in-process. iOS termination and force-quitting close sockets. Cold launch restores saved pairings and reconnects selected TVs automatically, without displaying persisted false-green status.

## Verification

261 hosted iOS simulator unit tests passed. Three new Samsung checks use real loopback WebSockets: repeated ping/pong on one socket with zero remote-key text messages, missing-pong deadline and closure, and cancellation without closing an otherwise-ready session. An initial fixture run attempted to use the ephemeral listener’s port before it was ready; the corrected fixture waits for ready and a nonzero port. The initial failure and corrected evidence are retained.

Three Swift Testing checks passed against the authenticated Companion loopback fixture: repeated verification preserves the same socket and client identity without HID/session setup, unanswered verification times out without reconnecting, and cancellation leaves the authenticated connection usable. The public verifyConnection(timeout:) addition is recorded in the vendor change log.

Six distinct native UI checks passed: repeated room round trips retaining actor identity and one connection per TV, retained background return with usable Home control, loss of an unselected room’s connection on immediate foreground verification while the selected room stays connected, tapping the lost TV to reconnect, regular observed-loss updates, automatic retries/navigation requests, and retained Auto-room selection. Background return and room round trips are combined in one case. Five passed in the initial batch; the final case passed after its test query was corrected to handle the accessibility element type of a connected disabled status indicator. Production source hashes are unchanged across these runs. Synthetic TVs replace external endpoints and the state callbacks feed the actual store; identity/count diagnostics let the tests verify actor reuse and exactly one successful setup per visited TV. No physical TVs were contacted. Physical Wi-Fi loss, concurrent room control, and the immediate response checks still need a hardware retest.

## Artifacts

- Build/ATV-Remote-0.3.38-unsigned.ipa — saved bundle ID, minimum iOS 27, arm64 iPhoneOS; sign with the user’s sideloading tool. DEBUG fixtures excluded.
- Build/ATVRemote-0.3.38-TestFlight.xcarchive — the saved developer team, optimized Release. Embedded profile and strict signature verification passed. Prepared for upload; no upload performed.

Evidence: audit/reproductions/atv-remote-0.3.38-unit-listener-ready.json, atv-remote-0.3.38-companion-liveness.json, atv-remote-0.3.38-ui-initial.json, and atv-remote-0.3.38-signed-archive.json.

[Combined evidence](../audit/reproductions/atv-remote-0.3.38-validation.json).
