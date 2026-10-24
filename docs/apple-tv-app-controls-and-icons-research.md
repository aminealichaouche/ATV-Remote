# Apple TV app controls and icons — October 14, 2026

The requested controls concern Xfinity Stream **running on the Apple TV**: show its live-channel favorites in ATV Remote and tune that TV when a channel is tapped. This investigation does not substitute iPhone playback, AirPlay casting, X1 cable-box APIs or a home-server dependency.

## App-specific controls

The installed-app interface lists bundle IDs and names, and launches an app. The current SwiftATV adapter sends `_launchApp` with `_bundleID`. The current pyatv implementation also supports a URL via `_urlS`; its documentation demonstrates tvOS deep links for apps such as Netflix and Disney+. This is a possible foundation for verified per-app action buttons, but it is not an interface for reading arbitrary app screens or their private favorites lists. [Current source](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/companion/api.py), [app-link documentation](https://pyatv.dev/development/apps/).

Companion exposes Guide and channel increment/decrement HID events. The vendored library implements these as remote-control commands, not as a query for Xfinity favorites or a channel-name/number tuning API. Whether Xfinity honors them in each UI state needs a TV test. A successful transport reply would not prove that the intended channel played. No unverified Guide/Favorites/channel macro was added.

Xfinity’s own Apple TV documentation describes its navigation/sidebar and live TV. It also documents Siri requests such as asking to play CNN through Xfinity Stream. Those instructions establish a user-facing Apple/Siri integration; they do not publish a third-party remote favorites-query or channel-tuning endpoint. The Companion implementation currently has no arbitrary Siri text-request facility. Protobuf voice-message definitions alone do not establish a working voice transport. [TV app overview](https://www.xfinity.com/support/articles/stream-on-apple-tv-overview), [Xfinity Siri integration](https://www.xfinity.com/support/articles/search-stream-apple-devices), [TV app FAQ](https://www.xfinity.com/support/articles/stream-on-apple-tv-faqs).

Public associated-domain checks found only the Xfinity account app’s `/plaid/oauth*` routes on www.xfinity.com, also confirmed through Apple’s association CDN. The checked tv.xfinity.com endpoints did not return parseable association JSON; the tested xfinitystream.app.link endpoint returned 404. These are bounded checks, not proof that Xfinity has no private/developer integration or other domain. No supported channel/Favorites deep link was verified. No Xfinity account credentials, subscription data, private APIs or TV sessions were accessed.

A reliable drawer implementation needs a TV-accepted deep link/command and, for automatic favorites, a supported way to obtain that list. It should capture the selected TV/session and never fall back to a blind navigation sequence after an uncertain launch. A manually curated favorite-channel list could avoid reading account favorites, but still needs verified TV tuning routes. No channel-control UI is shipped in this release.

## App icons: an improved route, incomplete coverage

The Companion list still returns names and bundle IDs, with no icon payload or URL. Current pyatv source does the same, and its maintainer explicitly identifies the absence of built-in apps from App Store lookups. [Maintainer issue](https://github.com/postlund/pyatv/issues/1536), [current parser](https://github.com/postlund/pyatv/blob/master/pyatv/protocols/companion/__init__.py).

Live checks against Apple’s public catalog found a useful improvement: adding `entity=tvSoftware` to an exact bundle-ID lookup returns TV-specific artwork and TV screenshots for Xfinity Stream and Netflix. The ordinary software lookup returned mobile artwork. Xfinity’s TV artwork URL ends in `App_Icon-marketing.lsr/512x512bb.jpg`, distinct from its mobile icon. This was observed on the public endpoint; it is not a guarantee of future API behavior. [Xfinity’s TV listing](https://apps.apple.com/us/app/xfinity-stream/id731629156?platform=tv), [Apple lookup documentation](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/LookupExamples.html).

| Exact bundle ID | TV catalog result |
| --- | --- |
| com.comcast.cim.x2 | One matching Xfinity Stream entry with TV artwork |
| com.netflix.Netflix | One matching Netflix entry with TV artwork |
| com.apple.TVMusic | No entry |
| com.apple.TVPhotos | No entry |
| com.apple.TVSettings | No entry |

There is still no verified source for **every** installed app icon, including built-ins, regional/delisted apps or sideloaded apps. Local caching improves speed and offline availability of icons already obtained; it cannot supply missing artwork. The user’s all-or-none preference remains in force: no app icons, placeholders or external artwork requests were added to the runtime app.

If that preference changes later, the researched TV-specific lookup can underpin a bounded, cached downloaded-app icon provider. It must match exact bundle ID and region, restrict HTTPS origins/redirects, validate image dimensions and size, cache by TV-catalog source/version, and keep app launches independent of artwork failures. It must not silently replace built-in icons with unrelated mobile assets.

## Reproduction evidence

Read-only public queries (no login, bounded bodies/timeouts, two workers) are recorded in:

- [Generic catalog and association responses](../audit/reproductions/atv-remote-3.5.2-public-app-metadata.json)
- [TV-specific catalog responses](../audit/reproductions/atv-remote-3.5.2-tv-catalog-metadata.json)
- [Additional app-link and TV-store checks](../audit/reproductions/atv-remote-3.5.2-xfinity-link-metadata.json)

No physical TV tuning, Siri transport or installed-app-icon extraction was performed.
