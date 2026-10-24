# Samsung power-on audit

Audited on 12 October 2026 for ATV Remote: direct iPhone-to-TV communication, iOS 27, an unsigned IPA signed by the user's sideloading tool, multiple independent Samsung and Apple TV selections, and no home server or cloud account. No physical TV or user's local network was contacted during this audit.

## Decision

Add an explicit **Turn on Samsung TV** action using a Wake-on-LAN magic packet directed to the selected TV's saved private IPv4 address. Store the active network interface's MAC address separately for each saved Samsung TV. This is a useful, entitlement-free first implementation, with compatibility dependent on the TV's standby networking and the user's LAN. It must report a wake **request**, not claim that the screen is on.

The maintained [SamsungTVWS example](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/example/example.py) separates its normal remote power toggle from a Wake-on-LAN power-on call. This supports the choice of a distinct wake transport when the remote WebSocket is unavailable; it does not establish that every Samsung model supports unicast wake.

## iPhone entitlement boundary

[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) explicitly distinguishes UDP unicast from UDP multicast and broadcast. Sending unicast needs Local Network access, but no multicast entitlement. Broadcast and multicast need the multicast entitlement on iOS. Keep the existing Local Network usage description and handle denied access with a retryable error.

The [multicast entitlement documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast) requires Apple's permission for use. Adding its key to an unsigned IPA does not provide a compatible provisioning profile for the user's sideloading tool. Do not depend on it, fabricate entitlement approval, or assume broadcast will work on a real iPhone because a simulator or Mac accepts it.

The implemented sender uses a UDP unicast endpoint for the selected, validated private IPv4 address and port 9. Before creating the connection it reads the OS interface table with `getifaddrs`, requires an up, broadcast-capable, non-loopback IPv4 interface, and checks the actual contiguous subnet mask. It accepts prefixes `/1` through `/30`, rejects the local device's own address, and fails closed when no eligible local subnet matches. A destination that is a network or broadcast address on any matching eligible interface is rejected, including `.127` on a `/25`. The most specific remaining subnet provides the source IP. The Network framework connection binds that local source address, prohibits cellular interfaces, and disables peer-to-peer networking.

No packet is attempted at `255.255.255.255`, a validated subnet-directed broadcast, or a multicast address. This release requires the TV to be on the iPhone's eligible local IPv4 subnet; routed networks and IPv6-only setups are unsupported. The existing Samsung address validator also conservatively rejects any IPv4 address ending in `.255`, even where that address could be a valid host on a `/23`; this compatibility restriction remains to avoid changing the existing remote adapter's address policy. No LAN scanning, router administration, background listener, or Internet relay is needed.

## Packet and transport

The standard payload is 102 bytes: six `0xFF` bytes followed by sixteen repetitions of the six-byte destination MAC. This format is documented in [Analog Devices AN-2613](https://www.analog.com/en/resources/app-notes/an-2613.html). It is a protocol reference, not evidence that Samsung uses that particular chip.

The [maintained Python wakeonlan source](https://github.com/remcohaszing/pywakeonlan/blob/master/wakeonlan/__init__.py) constructs the same payload, uses UDP port 9 by default, and permits an explicit host. Its default is broadcast; copy the packet specification rather than its default destination or socket options. No Python dependency or upstream source code needs to ship in the iOS app.

Recommended implementation properties:

- Accept only a six-byte hexadecimal MAC, normalize casing and separators, and reject all-zero, all-FF, multicast, truncated, and extra-byte values. A locally administered unicast MAC can be valid.
- Send a bounded, user-initiated request using Network framework; set a timeout and close the connection afterward. Successful local submission is not a TV acknowledgement.
- Capture the Samsung ID, IP, MAC, and selection generation before starting. Never reroute an in-flight wake to a newly selected TV. Cancel on selection changes or app backgrounding.
- Disable repeat taps while a request is pending. Do not queue remote keys for after wake or automatically replay an ambiguous power toggle.
- Keep the existing certificate-pinned remote connection as the authority for the green connection indicator. A submitted UDP datagram must not mark the Samsung driver connected.

## TV setup and compatibility

Samsung's [official power-on guide](https://www.samsung.com/au/support/tv-audio-video/power-tv-with-the-smartthings-app/) documents **Power On with Mobile** under Network → Expert Settings. For 2022–2026 models the preceding menu is All Settings → Connections; for 2017–2021 it is Settings → General. Its menus and availability vary by model and region. This is evidence for the standby setting, not a requirement to add a Samsung account or SmartThings dependency to ATV Remote.

For manual MAC entry, Samsung's [official network guide](https://www.samsung.com/us/support/answer/ANS10005241/) directs the user to Settings → Support → About This TV or Contact Samsung. Its [network setup article](https://www.samsung.com/my/support/tv-audio-video/set-up-a-network-connection-on-your-samsung-smart-tv/) illustrates distinct wired and wireless MAC addresses. Save the address matching the TV's actual Ethernet or Wi-Fi connection. Changing connection types may require updating this field.

The user's names “S95BD” and “S60” do not establish an exact model code or firmware. Their current working secure remote connection proves awake control, not standby wake support. Present this as per-TV setup and test it on each television. A TV must remain plugged in, connected to the same reachable LAN, and keep its relevant network interface available in standby.

## Limits of directed wake

[Cisco's ARP documentation](https://www.cisco.com/c/en/us/td/docs/routers/ios/config/17-x/ip-addressing/b-ip-addressing/m_arp-config-arp-0.html) explains that IPv4 delivery uses an IP-to-hardware-address mapping and that dynamic mappings expire. **Inference:** a unicast wake request can stop reaching a sleeping TV once the sender or network needs fresh address resolution and the TV's standby interface no longer answers. This must be tested after a long sleep as well as immediately after turning the TV off.

An unchanged saved IP is also necessary. A DHCP reservation can prevent address changes, but it does not guarantee that the sleeping TV answers ARP or accepts unicast magic packets. Isolation between wireless clients, guest networks, different VLANs, and disabled standby networking can prevent delivery. No claim of reliable indefinite wake should be made before a physical test on the user's network.

UDP has no application acknowledgement in this workflow. Suitable completion text is **Wake request sent. Tap Connect when the TV is on.** Transport failure should remain retryable. Even a successful later WebSocket connection proves remote availability, not that the display has illuminated or that the correct HDMI input is active.

## Automatic MAC lookup audit

The upstream [SamsungTVWS REST source](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/rest.py) requests device metadata from `/api/v2/`, but it disables HTTPS certificate verification. Its [connection source](https://github.com/xchwarze/samsung-tv-ws-api/blob/master/samsungtvws/connection.py) chooses HTTPS when configured for port 8002. Use these as endpoint evidence only. Do not adopt the upstream trust bypass or HTTP port 8001 fallback.

Returned metadata is not a reliable active-interface contract. One [upstream Q60 report](https://github.com/xchwarze/samsung-tv-ws-api/issues/105) contains `networkType: wired` alongside a field called `wifiMac`; a [Frame report](https://github.com/xchwarze/samsung-tv-ws-api/issues/108) contains `wifiMac: none`. These are primary observed examples, not a schema guarantee. Do not infer that any value called `wifiMac` must match the active wired adapter.

Manual entry is therefore sufficient and preferable for the first release. If automatic lookup is added, use HTTPS 8002, require the existing saved SHA-256 leaf certificate pin to match, disable redirects and TLS resumption that could bypass the identity check, cap the body and timeout, and avoid printing metadata or pairing tokens. A mismatch must fail closed without replacing the saved pin or silently requesting new trust. An automatically obtained MAC should be an interface-aware candidate that the user can review and correct.

## Apple TV / HDMI alternative

Apple's [official remote guide](https://support.apple.com/en-euro/guide/tv/atvbbe2477c9/tvos) documents turning a connected television on and off with Apple TV when TV/receiver control is enabled. This offers a separate path via the selected Apple TV and HDMI-CEC on a compatible installation. It depends on the actual HDMI connection and TV settings. A room group alone does not establish that its selected Apple TV is physically connected to its selected Samsung.

Do not silently substitute Apple TV wake for Samsung wake. If exposed, identify both targets and make the HDMI relationship user-visible. Keep Apple TV and Samsung selection independence intact.

## Verification required

Implemented tests cover exact packet bytes, MAC normalization/rejection, captured target identity, unicast validation with actual subnet masks and overlapping interface ranges, configured source binding and cellular prohibition, one-shot callback gates, an already-cancelled sender, device-scoped persistence, old-profile decoding, and encrypted transfer preservation. The production sender reads interfaces and validates the subnet before opening a socket. Pure gate tests do not prove actual Network framework timeout, cancellation, or send callbacks on an iPhone; those remain runtime checks. Native compilation checks iOS API availability and Swift concurrency conformance. Record actual test and build outcomes separately in the release validation report.

The user still needs to test wake with the correct MAC and Power On with Mobile enabled: immediately after off, after extended standby, with their usual Wi-Fi/Ethernet setup, and across each saved Samsung. The release should preserve the existing TV IDs, room assignments, pairing tokens, certificate pins, and encrypted-transfer identity format.
