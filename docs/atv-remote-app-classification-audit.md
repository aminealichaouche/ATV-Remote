# Apple TV app classification and stars audit

Reviewed on October 12, 2026. This audit reads the existing Companion implementation and primary online documentation. It does not query or control a physical television.

The Companion app-list response gives this app a mapping of bundle identifiers to localized display names. It provides no installation origin or built-in flag. The vendored parser validates that mapping, rejects duplicate or malformed identifiers, and represents each entry as `App(name:identifier:)`; `AppleTVDriver.listApps` carries those values into `RemoteAppInfo`. The public protocol documentation shows the same response shape and launches applications by `_bundleID`. [pyatv Companion protocol documentation](https://pyatv.dev/documentation/protocols/#fetch-application-list-fetchlaunchableapplicationsevent)

## Included apps

Use exact, case-sensitive membership in this list for the **Included** section. Apple documents these tvOS identifiers in its deployment guide. The list includes newer native apps and historical Movies/TV Shows entries; an entry is shown only if the selected Apple TV returns it. The section's membership is an inference from Apple's native-app documentation, rather than a field reported by Companion. [Apple's tvOS bundle identifier reference](https://support.apple.com/guide/deployment/bundle-ids-for-apple-tv-apple-apps-depcdd66fe58/web)

| Reference app name | Exact tvOS bundle identifier |
| --- | --- |
| App Store | `com.apple.TVAppStore` |
| Apple Arcade | `com.apple.Arcade` |
| FaceTime | `com.apple.facetime` |
| Fitness | `com.apple.Fitness` |
| Home Sharing / Computers | `com.apple.TVHomeSharing` |
| Movies | `com.apple.TVMovies` |
| Music | `com.apple.TVMusic` |
| Photos | `com.apple.TVPhotos` |
| Podcasts | `com.apple.podcasts` |
| Search | `com.apple.TVSearch` |
| Settings | `com.apple.TVSettings` |
| Sing | `com.apple.Sing` |
| TV | `com.apple.TVWatchList` |
| TV Shows | `com.apple.TVShows` |

Keep the returned display name for each row. This handles localized names and avoids renaming Computers to Home Sharing just because the deployment guide uses that label.

Do not classify every `com.apple.*` bundle as included. TestFlight is available as a separate App Store download for Apple TV and belongs with downloaded apps. [Apple's TestFlight App Store listing](https://apps.apple.com/gb/app/testflight/id899247664?platform=appleTV)

Do not add `com.apple.tips` merely because that identifier exists on iPhone/iPad. The inspected tvOS reference does not list a Tips app or a tvOS Tips bundle identifier. Likewise, pyatv's older example contains `com.apple.appleevents`, but that observation establishes its name and identifier, not that it was preinstalled. Leave either unverified entry outside the included allowlist. [Apple's iPhone/iPad identifier reference](https://support.apple.com/guide/deployment/bundle-ids-for-iphone-and-ipad-apple-apps-depece748c41/web), [pyatv app-list example](https://pyatv.dev/documentation/protocols/#fetch-application-list-fetchlaunchableapplicationsevent)

All remaining returned apps belong in **Downloaded**, above **Included**. This is a conservative fallback: a newly introduced native app absent from the allowlist can initially appear under Downloaded. The Companion response cannot prove download history, and an old native app reinstalled through device management remains categorized as Included. The app should not add unreturned native entries or guess from display names, capitalization, localized text, or namespace prefixes.

## Per-TV stars and import

Use each stored Apple TV device's stable local identifier as the preference owner and the exact app bundle identifier as the preference value. App display names vary by locale and are not suitable keys. Bundle identifiers from the current list are already the values accepted by the launch operation; the same exact identifier is the suitable match when importing stars between Apple TVs.

A starred row must come from the selected Apple TV's successfully fetched app list. Its name and launch target must come from that current list, never from an app remembered on the source TV. For example, importing a Netflix star from one Apple TV must not create a Netflix row or enable a launch on another TV whose list lacks `com.netflix.Netflix`.

Recommendation: copy star identifiers locally from a user-selected source Apple TV, preserving the destination's existing stars. Keep unmatched star identifiers as hidden preferences so an app appears starred if installed later. This requires no source-TV connection, pairing transfer, app installation, or remote modification. Imports should be a one-time copy: starring or unstarring afterward on one TV must not change the other TV's preferences.

Present visible favorites before the Downloaded and Included sections, with no duplicate app rows. Within each section sort using the current localized display names, with bundle identifier as a deterministic tie-breaker. An included app can still be starred. If a current app-list request fails, keep the failure explicit; do not invent an empty list, infer absence from the failure, or delete saved stars.

## Limits

The allowlist is verified against the current primary reference, but actual launchable apps vary with tvOS version, model, region, restrictions, and installation state. This audit does not establish which apps the user's devices currently expose. The physical-device behavior of list and launch still depends on the already implemented Companion registration and response validation.

There is no need to change the frozen vendor protocol implementation for this feature: application classification, preference storage, filtering, and source-TV import can all operate on its existing validated bundle-ID/name results.
