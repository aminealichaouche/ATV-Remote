# ATV Remote power controls audit

Reviewed on 12 October 2026 for 0.3.15. This change edits `PowerScreen.swift` only. It does not change remote commands, wake packet transport, pairing, saved TV identities, room assignments, or MAC persistence. No physical TV or local-network host was contacted.

## Result

Each selected device has a compact row with **On** and **Off** controls. Samsung power-on setup is a 44-point gear beside the TV name. The previous three large Samsung rows and explanatory paragraph are removed. A missing Samsung MAC no longer leaves On disabled: tapping it opens that saved TV’s MAC editor. Saving remains explicit, and the user can return with the native Back button. Opening the editor never sends a wake request.

On with a saved MAC still calls `RemoteStore.wakeSamsung()` once and retains its returned request ID. While a wake is pending, power controls and the setup gear are disabled. Dismissing this screen still cancels only a wake owned by that request ID. Existing captured device ID, IP, MAC, selection epoch, timeout and one-shot sender checks remain in `RemoteStore` and `SamsungWakeOnLAN`.

Samsung Off requires an active remote connection and sends the existing single `.powerToggle` action. The accessibility hint states that this sends the power button once. It remains a toggle at protocol level, rather than a verified discrete-off command; the connected, awake-TV assumption supports the visible Off action, but the app has no display-state acknowledgement. No retries, delayed power keys or `KEY_POWEROFF` fallback are introduced. The existing Samsung driver tests cover the one-click `KEY_POWER` payload and rejection of unsupported discrete power actions.

Apple TV On and Off call the existing `.wake` and `.sleep` actions. They retain the existing connected-device requirement and dismiss the panel after the action. No Samsung MAC is used by either Apple TV action.

## Is a MAC necessary?

For this app’s direct Samsung network wake, **yes**: the magic packet embeds the target adapter’s MAC. It must be the TV’s currently used Wi-Fi or Ethernet adapter. Samsung’s own consumer IP-control worksheet explains that the normal IP server can disappear after standby, identifies WoL as the later power-on path, and instructs controllers to use the matching wired or wireless MAC from About This TV. The document also requires Power On With Mobile and notes that network equipment can block wake. This is general vendor guidance, not a guarantee for the user’s exact TV or this app’s unicast transport. [Samsung Consumer IP Control worksheet](https://image-us.samsung.com/SamsungUS/samsungbusiness/tv-ci-resources/Samsung-IP-Control.pdf).

The app’s live camera text scanner can populate the MAC editor for review, so the user does not have to type the address. Changing the TV between Wi-Fi and Ethernet may require changing the saved MAC. Standby wake still needs testing immediately after power-off and after extended standby. The prior [Samsung wake audit](atv-remote-samsung-wake-audit.md) records the existing unicast, subnet and entitlement limits.

There is a separate possible route without entering a Samsung MAC: wake the Apple TV connected by HDMI to that Samsung, with compatible TV control enabled. Apple documents the Remotes and Devices → Home Theatre Control setting; Samsung calls HDMI-CEC Anynet+. **Inference:** the existing Apple TV wake action may also wake its attached TV when those settings and hardware cooperate. This is not substituted automatically for the selected Samsung, because a room group does not prove the physical HDMI relationship. [Apple TV remote guide](https://support.apple.com/en-ca/guide/tv/atvbbe2477c9/27/tvos/27), [Samsung Anynet+ guide](https://www.samsung.com/ca/support/tv-audio-video/anynet-hdmi-cec-on-your-samsung-tv/).

## Automatic lookup evidence and limits

Samsung’s older Smart View iOS SDK guide explicitly describes obtaining `device.wifiMac` from `getDeviceInfo` after a successful connection and storing it for future wireless wake. That establishes an automatic-MAC mechanism in that SDK; it does not promise an active Ethernet adapter field on every current television, or compatibility with this app’s independently implemented secure remote. [Samsung Smart View enhanced features](https://developer.samsung.com/smarttv/develop/extension-libraries/smart-view-sdk/ios-sender-app/enhanced-features.html).

The maintained SamsungTVWS source requests metadata from `/api/v2/`; port 8002 selects HTTPS. Its REST request disables certificate verification, so its trust behavior is unsuitable for copying into this app. [REST source](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/rest.py), [connection URL source](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/connection.py).

Primary observed metadata also shows ambiguity: one Q60 report has `networkType: wired` and a field named `wifiMac`, while a Frame report returns `wifiMac: none`. These are individual observations, not an authoritative schema. A field name alone cannot safely choose the currently active adapter. [Q60 report](https://github.com/xchwarze/samsung-tv-ws-api/issues/105), [Frame report](https://github.com/xchwarze/samsung-tv-ws-api/issues/108).

The user-provided `pedrinho/samsung_remote` main source discovers name, IP and model and delegates remote commands to helper code. Its README’s named power commands do not establish verified standby wake or automatic MAC discovery for the user’s TVs. The maintained SamsungTVWS WoL CLI itself requires an explicit MAC argument. [pedrinho main source](https://github.com/pedrinho/samsung_remote/blob/master/samsung_remote.py), [SamsungTVWS WoL source](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/cli/wol.py).

No new metadata request, network scan, ARP lookup, cloud dependency or trust bypass is added in this release. Any future lookup should reuse the already trusted TV identity, bound the response and timeout, disable redirects, and present an interface-aware candidate for confirmation. The current camera review and manual editor remain available.

## Validation scope

Source review confirms unchanged wake ownership, explicit missing-MAC navigation, separate List button hit targets through `.buttonStyle(.plain)`, and no repeated commands. The release validation report records actual native compilation and test outcomes. This source review does not exercise the iPhone camera, native visual layout, Samsung standby networking or Apple TV HDMI-CEC behavior.
