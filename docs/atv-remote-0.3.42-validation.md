# ATV Remote 0.3.42 (45) validation

**Only Available on Wi-Fi** appears immediately below Universal stars and defaults on when no value has been saved. It permits any Wi-Fi or a destination tunnel route to a saved Apple TV, matching the user's choice to avoid SSID/location access. Turning it off restores unrestricted attempts. The setting is local to this iPhone, remembered across launches, and does not alter Samsung connection behavior.

Apple TV connection entry points, including retries and room switches, wait for an eligible path. Re-pair checks eligibility before removing credentials. Foreground network updates and the existing three-second monitor close ineligible Apple TV sessions in all retained rooms and permit selected TVs to reconnect when an eligible route returns. Manual disconnect holds are preserved. Existing dots remain while the first network snapshot is pending; new attempts and commands wait for it. Network-monitor generation checks reject old callbacks.

## Route detection and limits

The monitor uses public [NWPath interface information](https://developer.apple.com/documentation/network/nwpath). A numeric private destination is associated with a nonblocking UDP socket without sending a datagram; getsockname selects its local source and getifaddrs maps that source to a unique active interface. A matching Wi-Fi interface or conservative numeric tunnel name permits an attempt. An unrelated utun merely existing does not. The normal authenticated Companion session remains responsible for proving the TV's identity and connection success.

This is best-effort routing information, not a WireGuard provider/status API or a security kill switch. Apple's [loadAllFromPreferences API](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager/loadallfrompreferences%28completionhandler%3A%29) reads configurations belonging to the calling app; this app does not manage WireGuard's configuration. A UDP route hint can differ from TCP policy in unusual per-app VPN setups, tunnel names/visibility may vary, and a route alone does not prove that the VPN peer is responding. No private proxy-dictionary keys, VPN management capability, Wi-Fi entitlement or location permission is added. Normal system VPN On Demand rules remain in effect.

[WireGuard's routing description](https://www.wireguard.com/) explains the role of allowed IPs; the home tunnel must route the TV's saved private address. Existing saved-IP/Companion-port fallback supports a previously paired TV when Bonjour discovery does not traverse the VPN. Physical iPhone/WireGuard behavior still needs a retest. Turning this setting off provides the previous connection behavior if iOS does not expose a usable route hint.

## Verification

266 hosted iOS unit tests passed. Four new checks cover pending/unknown paths, direct cellular denial, Wi-Fi/local Wi-Fi routing, destination tunnel classification, disabled-policy behavior and actual loopback source-interface selection. A bound loopback UDP receiver observes no datagram from the route lookup; malformed hostnames/URLs return no result rather than invoking DNS.

Three native UI checks cover default-on placement below Universal stars, cellular blocking of both manual retries and room changes, closing retained Apple TV sessions while Samsung remains connected, VPN and Wi-Fi recovery, turning the setting off and remembering it after cold launch; retained room round trips/background return; and healthy indicators with Home control after background return. Their network transitions and TVs are synthetic. The initial settings check tapped the switch row label and observed no value change; its corrected run targets the native switch thumb and waits for the update, matching the existing Universal stars check. Production sources were unchanged. The initial failure evidence is retained. No physical VPN validation is claimed.

[Settings screenshot](../audit/reproductions/atv-remote-0.3.42-network-settings.png) visually checked for wording, default-on state and placement below Universal stars.

## Artifacts

- [Unsigned IPA](../Build/ATV-Remote-0.3.42-unsigned.ipa): arm64, minimum iOS 27, existing bundle, DEBUG fixtures excluded; sign using the user's sideloading tool.
- [Signed TestFlight archive](../Build/ATVRemote-0.3.42-TestFlight.xcarchive): existing team, embedded profile and strict signature verification checked; not uploaded.

[Combined build, test, source and package evidence](../audit/reproductions/atv-remote-0.3.42-validation.json).
