# ATV Remote

ATV Remote is a native SwiftUI iPhone app targeting **iOS 27.0 or later**. It connects directly to selected Samsung TVs and Apple TVs on the home network. No always-on computer, cloud account, or relay service is required while using the remote.

The settings gear opens separate **Samsung TV** and **Apple TV** dropdowns, saved room groups, device pairing, navigation, Samsung volume/mute, Apple TV keyboard and installed apps, input-menu access, and explicit power actions. Each room can contain one TV of each type or only one type. Switching an individual dropdown is temporary until the pair is saved.

The latest release is ATV Remote 3.5.3 (49). **Re-pair** now recovers an Apple TV that was factory reset, keeping its name, rooms and stars, and the Rooms list opens each room with a chevron, shows each TV's type, and hides delete until **Edit**. See [3.5.3 validation](docs/atv-remote-3.5.3-validation.md). Room assignments are included by default and reviewed separately from wireless TV credentials, which stay on each phone. One **Share setup** action offers AirDrop and Save to Files; direct files need no phrase. Keyboard/Apps have six extra points of space above them. The larger tool controls and Sources label remain. See [sharing instructions](docs/share-pairings.md), and [app-controls/icon research](docs/apple-tv-app-controls-and-icons-research.md).

- [Upload to TestFlight using the signed archive](docs/install-and-test.md#upload-to-testflight-with-xcode)
- [Install, pair, and test](docs/install-and-test.md)
- [Share TV setup and stars with another iPhone](docs/share-pairings.md)
- [Implemented app design and architecture](docs/app-design.md)
- [Source audit and adoption decisions](docs/source-audit.md)
- [Apple TV project audit](docs/apple-source-audit.md)
- [Samsung project audit](docs/samsung-source-audit.md)
- [Apple TV alternatives audit](docs/alternatives-audit.md)

Native source and Xcode project are in `App/`; reviewed dependencies are in `Vendor/`. The separate interactive design preview uses simulated devices and sends no commands. The native app starts without sample TVs and uses actual protocol connections.

To rebuild with Xcode 27 installed, run `python3 scripts/build-ipa.py`; the unsigned IPA is written to `Build/`, which is not committed. For signed builds, put your team and bundle ID in the untracked `App/Signing.local.xcconfig` (`DEVELOPMENT_TEAM = YOURTEAMID`, `PRODUCT_BUNDLE_IDENTIFIER = com.example.atvremote`); `App/Signing.xcconfig` includes it and otherwise defaults to `io.github.atvremote`. Dependencies are vendored locally. This first test IPA uses Release compilation conditions with optimization disabled; DEBUG fixtures and the UI-test reset option are excluded.

**The new compatibility changes still need a hardware retest.** The user reported Samsung volume/navigation working on the earlier build; physical-device validation has not been performed from this workspace. “S95BD” is preserved as a friendly name, and “S60” is not enough to establish compatibility. Awake Samsung control requires the secure Tizen WebSocket on port 8002. Power-on sends one directed UDP request to the TV's saved IPv4/MAC on the same local subnet; standby network behavior varies. Older Samsung remote protocols remain unsupported. Apple TV uses a community Companion implementation and still needs firmware-specific testing.
