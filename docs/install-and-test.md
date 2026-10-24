# Install and test ATV Remote

This native build requires **iOS 27.0 or later**. Build `Build/ATV-Remote-3.5.4-unsigned.ipa` with `python3 scripts/build-ipa.py` for sideload signing, or use a signed archive for TestFlight. Version 3.5.4 (50) puts Exit and a blue Share/Import button at the top of Transfer setup. 3.5.3 added reset Apple TV recovery through Re-pair and a clearer Rooms list. Since 3.5.2 it includes optional room assignments by default, keeps wireless TV credentials local to each phone, and uses one Share setup button for AirDrop or Save to Files. The Wi-Fi/VPN restriction remains removed. Saved TV pairings, rooms, stars, layouts and other preferences are kept. Your bundle ID is unchanged. See [3.5.4 validation](atv-remote-3.5.4-validation.md).

## Upload to TestFlight with Xcode

Normal Xcode builds now enable signing. Your developer team and bundle ID are read from the untracked `App/Signing.local.xcconfig` (`DEVELOPMENT_TEAM = YOURTEAMID` and `PRODUCT_BUNDLE_IDENTIFIER = com.example.atvremote`), so they are never committed; without it the bundle ID defaults to `io.github.atvremote`. The generator moves both values there from an older project when missing and preserves signing style and provisioning settings. The unsigned sideload script explicitly disables signing only for its own command-line build. Those unsigned IPAs/archives do not contain a signing team and should not be used for TestFlight.

A signed 3.5.4 (50) archive is built locally at `Build/ATVRemote-3.5.4-TestFlight.xcarchive`. Its signature verifies, a provisioning profile is embedded, and archive metadata contains the saved developer team and bundle ID. It is development-signed; Xcode's App Store Connect upload flow handles distribution signing. This archive has not been uploaded.

1. Double-click that archive in Finder to open it in Xcode Organizer. Select it and confirm Team is populated. For future builds, open RoomRemote.xcodeproj, select your paid team under the app target's Signing & Capabilities with Automatically manage signing enabled, choose Any iOS Device (arm64), then Product → Archive.
2. If needed, create an iOS app record in App Store Connect → Apps → + → New App: name S/ATV Remote, the bundle ID from `App/Signing.local.xcconfig`, primary language English and a unique internal SKU such as atv-remote. Use an existing record if it already matches this bundle.
3. In Organizer choose Distribute App → App Store Connect → Upload. Use automatic signing and follow the prompts to create/select a distribution certificate if required. Review the destination app and upload.
4. After processing, open that app's TestFlight tab. Follow any requested build information prompts, create an Internal Testing group, add your own App Store Connect account and the build, then install with TestFlight on your iPhone. External testers use the separate external-testing flow and may require beta review.

[Apple's upload instructions](https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html), [create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/), [add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).

## Sign and install with a sideloading tool

1. Import `ATV-Remote-3.5.4-unsigned.ipa` into your existing sideloading tool. Install it as an update with the same app/signing identity to retain existing setup when your tool permits it.
2. Use that tool's normal **sign and install** workflow with your own signing identity/profile. The supplied package has no Apple signature or provisioning profile and cannot install directly without this step. Follow any device trust or other setup prompts required by your chosen tool.
3. Launch **ATV Remote**. The starting screen has no sample TVs, a Living Room profile, and a **settings gear** next to the room menu. The app bundle identifier before signing is the one in `App/Signing.local.xcconfig`, or `io.github.atvremote` by default.
4. Join your home Wi-Fi. TVs can use Wi-Fi or Ethernet, provided they are on the same reachable home network. Guest networks or client isolation can prevent communication. No computer or relay needs to remain running while you use the remote.
5. Choose **Allow** when iOS asks for Local Network access. If you denied it, open **gear → Manage TVs → Open iPhone app settings**, enable Local Network access, and try again.

Keep a consistent signing identity and app identity when updating if you want the best chance of retaining pairing and room data. If your signing tool changes the app's Keychain access identity, re-pairing may be required. Signing and installation behavior depends on the tool you already use; this package does not include a signer.

## Pair a Samsung

1. Turn on the intended Samsung with its physical remote. Find its local IP address in the TV's network settings. Also record its full hardware model and firmware from the TV settings; a phone's friendly name is not a model verification.
2. In ATV Remote, select the intended **Room**, then open **gear → Manage TVs**. Choose **Samsung TV**.
3. Enter a name such as **Living Room S95BD** and the literal private IP, for example `192.168.1.50`. Do not enter `https://`, a port, or a hostname. Supported IPv6 unique-local addresses are also accepted. You can tap the camera text button beside IP or MAC instead of typing: follow the live scan steps below, then tap **Add and pair Samsung TV**.
4. The app connects to the secure Tizen remote on **port 8002**. On the certificate review screen, check the TV name and IP and confirm that you are on your trusted home network. Expand **Certificate fingerprint** if needed. Tap **Trust this TV and request access**.
5. On that Samsung, approve the **Room Remote …** access prompt (the original protocol name is retained for pairing compatibility). The extra identifier distinguishes this app's saved TV connection. Wait for **Connected** in the Samsung section of Settings before using controls.
6. If the certificate review is not opened automatically, use **Review TV** in the Samsung section of Settings. If approval times out, reconnect and approve the prompt on the television.

The app remembers that TV's certificate fingerprint and authorization token in Keychain. Unexpected certificate changes are rejected. Check the selected address and TV before using **Manage TVs → Re-pair** to deliberately reset trust. A denied prompt, failed TLS connection, or unrelated WebSocket message does not constitute pairing.

This build has no unencrypted port-8001 fallback, legacy Samsung protocol, or Samsung auto-discovery. If a TV lacks the secure port-8002 remote, it cannot use the awake remote adapter. Power-on is a separate request with the setup below. **S95BD** is preserved as a name; **S60** compatibility is unresolved until its full model and actual protocol are checked.

## Scan the TV’s IP and MAC text

1. Open **gear → Manage TVs → Samsung TV**. Tap the camera text icon beside the IP or MAC field. For a saved Samsung, the same icon is beside its IP and MAC fields under **Manage TV**. Allow Camera access when asked.
2. Point at the actual text on the TV’s **Network Status / IP Settings** screen to read its IP, then at **Support → About This TV** for its MAC addresses. You can keep scanning while switching between those TV menus; already detected complete addresses stay available.
3. Tap **Review addresses**. Check the detected values against the TV, choose the Wi-Fi MAC for Wi-Fi or the Ethernet MAC for Ethernet, and correct any unclear characters. Multiple candidates require a choice.
4. Tap **Use these addresses**, or **Use MAC for [TV]** for an existing TV. This fills the fields only. Tap **Add and pair Samsung TV** or **Save** afterward to finish setup.

The scanner reads live text without taking or saving a photo. It does not scan QR codes. Recognition is on-device; manual entry remains available when camera access or live text scanning is unavailable. A MAC-only scan leaves a typed IP unchanged; a scan does not change your TV name or room group. For an existing TV, a detected conflicting IP blocks applying the MAC until the correct target is reviewed or rescanned. OCR can miss or misread characters, so verify both addresses before saving.

## Turn on a Samsung

1. On that television, enable **Power On with Mobile** under **Network → Expert Settings**. On newer models, start from **All Settings → Connections**; older models may use **Settings → General**. [Samsung's setting guide](https://www.samsung.com/au/support/tv-audio-video/power-tv-with-the-smartthings-app/).
2. Find the TV's MAC address in **Support → About This TV** (or Contact Samsung). Use the wireless MAC for a Wi-Fi TV and the wired MAC for an Ethernet TV. [Samsung's MAC guidance](https://www.samsung.com/us/support/answer/ANS10005241/).
3. In ATV Remote, choose the intended Samsung, then open **Power → the gear beside the Samsung name**. Enter its MAC or use the camera text icon beside the field, then tap **Save**. The same editor is available under **gear → Manage TVs → Manage TV**. A MAC can also be entered while adding a new Samsung. Each TV stores its own address; room assignments and pairing remain unchanged. Save validates and normalizes the MAC, writes it before closing the editor, and the next On reads that current saved profile. Scanning changes the draft until you tap Save. Use the inline x to clear the MAC draft, then Save to remove it. Clearing the IP requires entering a valid replacement before saving. Going back without Save discards edits.
4. Keep the TV plugged in and your iPhone on the same local IPv4 network. Tap **Power → On** under the Samsung name, even if its connection dot is gray. **Wake request sent** means the network request was submitted. Its confirmation banner disappears after three seconds without changing the power panel’s layout. Once the TV starts, tap its gray name/icon/dot indicator at the top of the main remote if needed.

The app sends one direct Wake-on-LAN packet to the saved TV IP and MAC. It checks the iPhone's actual subnet mask, rejects broadcast/network/self addresses, and binds the local source. It uses existing Local Network access without a broadcast entitlement, cloud, or home server. Unicast wake depends on standby networking and address resolution; test immediately after off and again after a long sleep. A saved MAC does not guarantee wake on every model. See the [wake audit](atv-remote-samsung-wake-audit.md) for limits. If the TV changes Wi-Fi/Ethernet connection, update its MAC. If its IP changes, update the saved profile as described in troubleshooting.

## Pair an Apple TV

1. Keep the intended Apple TV awake and on the same home network.
2. Select its intended **Room**. Open **gear → Manage TVs**, choose **Apple TV**, and tap **Find Apple TVs**. Allow Local Network access if prompted; discovery takes a few seconds.
3. Select the correct discovered name and address. With several Apple TVs, confirm that the pairing code appears on the television you intended.
4. Enter its four-digit code in ATV Remote and tap **Pair Apple TV**. Wait for **Connected** in the Apple TV section of Settings. If needed, tap **Enter code** to reopen the PIN screen.
5. For an incorrect PIN or failed pairing, tap **Cancel**, then **Connect** to request a fresh code. **Re-pair** removes the selected device's saved credentials and restarts setup. If that Apple TV was factory reset, Re-pair finds it at the same IP address under its new identity and keeps its name, rooms and stars; another saved TV is never taken over. If the reset TV now has a different IP address, use **Remove TV** and add it again.

Pair each Apple TV separately. Names can be changed under Manage TVs without re-pairing. Reconnect matches the saved discovery identity and verifies the paired peer; it does not pick an arbitrary Apple TV if the original one is missing. Apple TV control uses the community Companion implementation, so the actual model and tvOS version remain part of the hardware test.

## Configure rooms and switch TVs

1. The default **Living Room** is ready for assignment. For another room, open **gear → Manage rooms**, choose **Add a room**, enter a name, select saved Samsung and Apple TV devices, and tap **Save**. Either device may be **None**.
2. Select the room from the **Room** dropdown. Its saved Samsung and Apple TV are selected together. The Samsung-only case selects Samsung navigation automatically.
3. Open the gear. The navigation title and TV section both show the current room name, such as **Living Room**. Its separate **Apple TV** and **Samsung TV** dropdowns share a stacked layout with aligned names, addresses, and chevrons. Use either dropdown to override one device temporarily. If the pair differs from the room default, tap **Save this pair for [room]** to retain it. Otherwise, switching away and back to the room restores its saved pair. Settings submenus have a top-left back button; **Done** closes Settings.
4. Adding or pairing a TV saves its profile and selects it temporarily. Existing populated and single-device room groups stay unchanged. A fully empty room can automatically receive its first new Samsung and Apple TV during the same first-setup session. For other additions, choose the intended TVs in Settings and use **Save this pair for [room]**, or edit that room under **Manage rooms**.

The Apple TV / Samsung segmented control changes the navigation destination. Volume and mute always go to the selected Samsung. Reselecting an unchanged TV or room preserves its current sessions, including pending connections. Changing rooms reconnects only the devices whose identities changed. Reselecting the current room after a temporary override restores its saved pair. An offline selection stays selected and its controls remain disabled; tap its gray name/icon/dot indicator at the top of the remote to retry, including while connecting. A spinner beside the dot shows connecting or awaiting TV approval. Switching devices cancels pending work and active touchpad gestures. Leaving the app cancels unfinished controls/setup while keeping established outbound TV connections in memory. Returning does not restart a connected session. If the peer or network dropped the connection, it reconnects automatically unless you explicitly disconnected that TV. Force-quitting or iOS termination ends the sockets; reopening reconnects with saved pairings.

In Settings, **Disconnect** appears on the same line as **Connected**. Tap it to close only that TV’s session: the line changes to **Disconnected** with **Connect**, and Settings stays open. The TV remains selected and paired, and all room assignments and app stars stay saved. A manually disconnected TV stays disconnected when you switch rooms or foreground the app during this app session; tap **Connect** to reconnect it. A new app launch resumes normal automatic connections. Pending connections show **Cancel**; PIN and certificate-review actions retain their setup labels.

## Choose rooms and check connections

Choose a saved room in the top-left Room menu. **Auto is temporarily hidden and disabled in 0.3.39.** Updating from an enabled Auto setting keeps the last saved room and clears Auto, so room selection stays manual across launches. Saved TVs, room assignments and stars stay intact.

Connection events update dots immediately. While active, local transport checks and eligible selected-TV retries run every three seconds. Returning from the background immediately checks retained sessions with a two-second response limit, keeping green until a connection check fails. Healthy sessions are reused when switching rooms. Pending pairing and manual disconnects remain respected. Tap a gray TV name, icon or dot to retry. Green indicates an established remote session; a standby TV can retain its connection. Off commands also schedule a local connection-state read after one second.

## Change the remote layout

Open the gear, then **Remote layout**, and choose **Expanded Apple TV remote** (first and the default when no layout is saved), **Apple TV remote**, or **Alternate**. Below the pad, Back and Home share the top row, with Play/Pause and Mute on the left and one continuous +/− volume rocker on the right. Power appears above the pad at the right. Select **Alternate** for the existing Back/Home/Play row and horizontal volume controls. The old Stacked preference automatically becomes Apple TV remote when updating.

Use the D-pad/touchpad toggle above the pad to choose your navigation surface. The app remembers both this choice and the layout on this iPhone across relaunches and rooms. Alternate and Apple TV remote have a 24-point gap below the pad. Expanded uses the Alternate pad dimensions: a 228-point circular D-pad or a full-width touchpad 228 points high, with 18-point screen margins. It retains 76-point circular buttons, a 76×176-point volume rocker, 36-point horizontal gaps and 24-point vertical gaps. Its pad-to-buttons gap is 32 points. The remote remains non-scrolling when controls fit, with its existing scroll fallback for smaller spaces or larger text. Volume and mute always target the selected Samsung. Remote layout and pad choice can be included in encrypted setup sharing from 0.3.32 onward.

## Star apps and import stars

1. Select the intended room or Apple TV, connect it, and open **Apps**. Tap the star beside an app to star or unstar it. Tapping the app name launches it; the star is a separate button.
2. **Starred** appears first, followed by **Downloaded** and then **Included**. Each installed app appears once. Stars are saved separately for each Apple TV and remain through room changes, app relaunch, TV renaming, and re-pairing.
3. To copy another TV's stars, choose **Import stars from another Apple TV**, select **From Apple TV**, review its saved-star and installed-match counts, and tap **Import stars**. This adds to the current TV's existing stars and leaves the source unchanged. The source TV does not need to connect for the copy.
4. An imported app that this TV does not have stays hidden. If it is installed later, **Reload apps** reveals it as starred. Unstarring an app on one TV does not change the other TV's stars.

App rows show names and separate star controls, with no thumbnails, placeholder tiles or App Store links. The artwork lookup/download/cache feature has been removed. The installed app list still comes from the selected Apple TV.

Included classification uses [Apple's published tvOS bundle identifiers](https://support.apple.com/guide/deployment/bundle-ids-for-apple-tv-apple-apps-depcdd66fe58/web), since the remote protocol does not report installation origin. Unknown identifiers fall under Downloaded. Stars are per-TV app preferences and can be included in encrypted setup sharing from 0.3.32 onward. See the [classification audit](atv-remote-app-classification-audit.md).

## Restart apps

1. Connect the intended **Apple TV** and tap the **Shortcuts icon at the top right**.
2. Tap **Restart Xfinity Stream** to run the bundled preset directly, without a card-confirmation step. Xfinity must be installed on that TV.
3. For another app, tap **Restart current app** and choose the app currently open on your television. Apple TV's Companion protocol does not reliably return the foreground app ID, so this choice identifies the app to reopen. The chooser has a native back button.
4. The macro checks the current installed-app list and swipe support, launches that exact app, opens the switcher, sends one full-height upward flick, exits and launches the same app again. Progress, success and errors appear below both shortcut controls. **Restart sent** records command completion; check the TV for the visible result.

The automatic swipe assumes that the app just launched is the switcher's focused card. Companion cannot confirm card identity or process termination; another controller or overlay could change focus. [Apple documents the switcher-and-swipe gesture](https://support.apple.com/guide/tv/force-quit-an-app-atvb39f389ec/tvos). This macro needs physical testing on your TV. **Done**, backgrounding, changing Apple TVs, lost connection or an error stops it. It never retries the dismissal or reconnects and resumes. See the [implementation audit](atv-remote-xfinity-shortcut-audit.md).

## First hardware checks

| Check | Expected behavior |
|---|---|
| Samsung navigation, volume, mute | The selected Samsung visibly responds; mute toggles |
| Apple TV navigation and playback | Only the selected Apple TV responds. Single Home returns to its app grid after a one-second Back/Menu hold; double Home opens the app switcher; hold Home opens Control Center. Double/hold must not also navigate Home. Back goes one screen back. Test Home with the TV-button setting still set to the Apple TV app. |
| Mixed pair | Apple TV navigation goes to the selected Apple TV while volume goes to the independently selected Samsung |
| Room change, pairing, and app relaunch | Pair additional Family Room TVs while Living Room is selected, then reselect Living Room: its original saved devices must remain. Saved assignments survive relaunch. |
| Unchanged selection | Reselect the connected TV or its unchanged room: there is no reconnect. Rooms sharing a TV preserve that TV's session. |
| Status rows and Settings navigation | Below the room menu, Apple TV and Samsung indicators sit side by side. Each has its icon to the right of the name followed by a green/gray dot. Tap the name or indicator to retry even while connecting; a spinner appears beside the dot during connection/TV approval, with no separate Connect button below; long names truncate on one line. Settings shows the active room name above equally aligned TV selectors; back buttons return from Manage TVs, Manage rooms, and Transfer setup. |
| Live text scan | Camera text buttons appear beside Samsung IP and MAC fields. Scan TV text across both menus, review and choose the active adapter. Applying fills fields without pairing or changing rooms; Cancel leaves them unchanged. Permission denial allows manual entry. |
| Remote layout and pad | Choose Apple TV remote: Back/Home above Play/Mute and one vertical rocker. Choose Expanded: its pad dimensions match Standard in each mode, while the buttons are larger with wider spacing. The pad has more space below it. Choose Touchpad, relaunch and change rooms: both choices remain. Return to D-pad/Standard and relaunch again. Volume still targets Samsung. |
| Disconnect / Connect | Disconnect one connected TV in Settings: its line switches to Connect, Settings stays open, and the other TV remains connected. Reselect its room and background/foreground: it stays disconnected until Connect. Pairing and assignments remain. |
| Offline room/device | It remains selected and reports a connection failure; other selected connected devices stay usable |
| Keyboard | Open a text field on Apple TV, choose Keyboard, then send short text; text is appended to the active field |
| Apps and Inputs | Apps registers a remote session, then requests the selected Apple TV's apps; failures show the TV error and Reload apps. Samsung Inputs opens its source menu |
| App names and stars | All app rows show names without thumbnails or placeholders. Launch and star actions remain separate; switching Apple TVs preserves that TV’s stars. |
| Stars and app sections | Star one downloaded and one included app: both move to Starred, without duplicates. Switching Apple TVs shows that TV's independent stars; relaunch preserves them. |
| Import stars | Copy stars from another saved Apple TV: existing stars remain, source stars stay unchanged, and apps missing from the destination do not appear. Reload after installing a previously missing app shows its imported star. |
| Xfinity shortcut | The room name stays on one line beside gear and Shortcuts. Top-right Shortcuts opens the bundled preset. One tap opens Xfinity and the switcher and continues without confirmation. Restart current app lets you identify another installed app and uses the same macro. The single full-height swipe visibly dismisses that card and Xfinity reopens on the selected Apple TV. Missing Xfinity/swipe support sends no launch or dismissal. |
| Shortcut cancellation | Done, TV selection change, backgrounding, and connection loss stop the run. A canceled or failed run does not continue after reconnect or on another TV; existing stars/room assignments remain intact. |
| Setup transfer | Prepare a transfer: it displays four random words. Send only the encrypted file and separately enter its phrase on another updated iPhone, then review and approve. Capitals, extra spaces and hyphens work. An old file still accepts its old code. Incorrect phrases or modified files reject. |
| Power | Compact On/Off controls operate only their named TV. Samsung On without a MAC opens its editor; the gear opens it too. Configured On works with a gray dot. Off sends one power button to a connected Samsung. Check wake immediately after off and extended standby. |
| Permission and lifecycle | Denial fails without false success; enabling permission recovers; returning from background retains established sessions; missing/failed sessions reconnect unless manually disconnected |

Test the first few navigation/volume commands while both televisions are visible so routing can be checked directly. Repeat with each physical device. **Sent to [name]** means the send succeeded, not proof that the TV performed the action. Single Apple TV Home sends a one-second Back/Menu hold; double tap sends TV double-tap and holding sends TV hold for Control Center. Continuous touch control and held-volume repeat are not available.

For a failure, record the selected device name, full model, firmware/tvOS, iPhone iOS version, action attempted, visible TV result, and exact app error. Do not include PINs or pairing tokens. If discovery fails, check Wi-Fi, Local Network permission, and network isolation, then wake the Apple TV and scan again. If a Samsung connection fails, check its IP and that the TV is on. This build has no address editor: if DHCP changes a Samsung's IP, remove its old entry, add and pair it at the current IP, enter its wake MAC, and update affected room assignments. The wake request does not create a remote session: connect after startup. Keep its physical remote available while testing standby wake compatibility.


## Returning to the app and switching rooms (0.3.39)

Home/app switching preserves all established sessions for TVs you have visited. On return, their green dots stay visible while the app checks the existing authenticated Apple TV channel and Samsung WebSocket. Checks start immediately and have a two-second response limit per TV; failure turns the dot gray, and eligible selected TVs reconnect. Checks run concurrently and send no button, app-launch or power commands. Regular transport checks continue every three seconds while active.

Switching Living Room → Family Room → Living Room reuses each room’s established sessions. Visiting another room does not close a healthy TV connection. Unfinished pairing/connection work and remote commands are still cancelled on a selection change; commands cannot move to the other room. Disconnect, Re-pair, Remove, and IP changes invalidate only the affected TV session. A manually disconnected TV remains disconnected until an explicit connection request.

Force-quitting or iOS terminating the process closes its sockets. A cold launch restores the saved pairings and reconnects selected TVs automatically; it does not show a stale saved green indicator.

## Keep your place when leaving the app (0.3.41)

Leaving the app in the background keeps the current panel, its navigation, edits and search. The scanner stops its camera and keeps address edits in review. Transfer choices, an unlocked import review and a prepared transfer remain available in memory. In-flight TV controls, restart macros and transfer work are canceled rather than automatically replayed. Incomplete app loading can be resumed with Reload. Force-quitting or process termination still starts a new UI session; unsaved drafts are not written to disk.

Under Your TVs, select a saved TV. Its header shows the saved name followed by (Apple TV) or (Samsung). Edit Name and IP address, plus MAC address for Samsung. Inline x icons clear IP/MAC drafts. The bottom Save validates all fields and writes them together; a validation error keeps the editor open and leaves saved values unchanged. Re-pair and Remove TV remain explicit actions.

## Restored connection behavior (3.5)

The Wi-Fi/VPN restriction toggle and its route detection have been removed. The app uses the connection behavior from 0.3.41: attempt selected TV connections normally and let pairing authentication and network availability determine success. The old restriction preference is no longer read and cannot block an update from connecting. No TV setup is removed by this rollback.
