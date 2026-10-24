# Samsung power-on follow-up

The user reports that a Samsung on Wi-Fi does not wake from ATV Remote, although the app reports a wake request sent. Their replacement physical remote works. Waking the attached Apple TV using the iPhone Remote has not yet been tested. This report is research and source inspection, not a physical-network diagnosis or a confirmed wake fix.

## Physical remote versus iPhone

Samsung’s Smart Remote troubleshooting guide checks the power button by looking for its infrared transmission through a phone camera. Its older Smart Control guide explicitly separates Bluetooth controls from infrared power. This supports infrared as the likely explanation for a inexpensive replacement remote’s successful power button; the exact replacement model was not provided. A normal iPhone app cannot drive a general-purpose infrared TV transmitter. Face ID infrared hardware is not an app-programmable TV remote emitter. Copying the physical remote’s IR code would require additional IR-emitting hardware.

[Samsung Smart Remote troubleshooting](https://www.samsung.com/ph/support/tv-audio-video/troubleshooting-smart-remote-control/), [Samsung Smart Control power/IR explanation](https://www.samsung.com/uk/support/tv-audio-video/how-to-pair-your-smart-control-remote-to-your-2014-model-tv/).

No verified, supported direct iPhone-to-Samsung Bluetooth standby-wake method was established by this research. Bluetooth remote emulation cannot be assumed to replace the infrared power path. No Bluetooth pairing or IR probe was attempted.

## Current implementation’s limit

SamsungWakeSender sends one UDP unicast magic packet to the saved TV IP. The sent message means the local network stack accepted the datagram; there is no TV acknowledgement. The unchanged sender does not transmit a subnet broadcast. Its packet contents and ownership are unit-tested, but those checks do not establish standby delivery on this Wi-Fi network.

Samsung’s IP-control worksheet distinguishes short standby with a potentially active IP server from longer standby that requires Wake-on-LAN. It requires the wireless MAC when using Wi-Fi and warns that network equipment can block wake. Incorrect adapter MAC, disabled Power On with Mobile, standby behavior and network delivery remain possible causes. **Inference:** unicast delivery can fail when the sleeping TV no longer answers address resolution. The user’s sent message alone cannot identify which cause applies.

[Samsung IP-control worksheet](https://image-us.samsung.com/SamsungUS/samsungbusiness/tv-ci-resources/Samsung-IP-Control.pdf), [Samsung mobile-power setting](https://www.samsung.com/au/support/tv-audio-video/power-tv-with-the-smartthings-app/), [prior implementation audit](atv-remote-samsung-wake-audit.md).

The maintained wakeonlan implementation defaults to broadcast. Broadcast is a concrete alternative worth implementing and testing, but physical iOS devices require Apple’s restricted multicast entitlement for UDP broadcast. A paid Developer Program membership permits requesting it; it does not automatically grant it. Merely adding an entitlement key to an unsigned IPA is insufficient. It must be approved for the developer team and included in the signing profile. No entitlement request or broadcast sender was added in this release.

[Wakeonlan source](https://github.com/remcohaszing/pywakeonlan/blob/master/wakeonlan/__init__.py), [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [Apple multicast entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast).

An entitlement request can describe: “ATV Remote (local.roomremote.ios) lets users control their paired Samsung TVs and Apple TVs on their home network. We request multicast networking for bounded, user-initiated IPv4 UDP wake broadcasts targeting the chosen Samsung TV’s saved active-interface MAC. The feature does not scan the Internet or upload network/device information. Existing typed Bonjour services are declared in the app.” Any implementation should retain captured target/subnet validation, cancellation, bounded packet count and request-only feedback.

## Best next test with existing devices

Enable Samsung Anynet+ under All Settings → Connection → External Device Manager. On Apple TV, enable the TV-control option under Settings → Remotes and Devices → Home Theater Control. Turn the Samsung off, then wake the physically connected Apple TV using the iPhone Remote. Compatible HDMI-CEC can carry the power command from Apple TV to Samsung without a Samsung MAC.

Apple documents this TV/receiver-control route. **Inference:** if the built-in iPhone Remote wakes both devices on this installation, the app’s existing Apple TV On command is the next comparison; it already sends Companion wake to the selected Apple TV. Success still needs a hardware test. Room grouping alone does not prove the physical HDMI connection, so an automatic Samsung→Apple TV substitution would be inappropriate without an explicit per-room choice.

[Samsung Anynet+ setup](https://www.samsung.com/ca/support/tv-audio-video/anynet-hdmi-cec-on-your-samsung-tv/), [Apple TV home-theater control](https://support.apple.com/guide/tv/apple-tv-4k-remote-control-receiver-atvbbe2477c9/tvos), [Apple iPhone Remote setup](https://support.apple.com/en-us/108778).

SmartThings is another vendor-supported phone route for compatible TVs, with Samsung account and connectivity requirements. Its public API accepts switch on/off commands but acceptance is not confirmed device execution. It was researched but not integrated, preserving the current app’s direct local operation and existing-device scope. [Samsung SmartThings power-on guide](https://www.samsung.com/ae/support/tv-audio-video/how-to-power-on-your-samsung-tv-with-the-smartthings-app/), [SmartThings command API](https://developer.smartthings.com/docs/service-integrations/control-devices).

The icon-free release removes artwork only. It does not claim to fix Samsung wake, and the direct unicast wake implementation remains unchanged.
