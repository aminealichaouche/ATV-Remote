# Share setup between iPhones

Use **ATV Remote 3.5.2 or later on both iPhones** to share room assignments. Rooms specify which Samsung and Apple TV belong together; they are separate from wireless authorization credentials. Room assignments are included by default. Each phone still authorizes with its TVs independently.

## Send

1. Open **gear → Share or import setup → Share**.
2. Select the TVs. Leave **Room assignments**, **Starred apps**, and **Remote layout & pad** selected to copy that configuration. Only selected TVs appear in the shared rooms. The room-inclusion choice is remembered.
3. Leave **Require a transfer phrase** off for direct sharing, then tap **Create transfer**.
4. Tap the single **Share setup** button. Choose **AirDrop** to send to another phone, or **Save to Files** to save the file normally.

A prepared native ShareLink also supplies content for iOS’s bring-phones-together AirDrop flow. iOS handles proximity detection, recipient selection and acceptance. The app cannot force a recipient or silently send just from a physical tap. Both phones need Wi-Fi and Bluetooth; proximity sharing also needs **Settings → General → AirDrop → Bringing Devices Together**. [Apple’s sharing instructions](https://support.apple.com/en-us/119857), [developer guidance](https://developer.apple.com/videos/play/wwdc2023/102/).

## Receive

1. Accept the AirDrop/open the `.atvsetup` file in ATV Remote. A direct transfer opens the review without a phrase.
2. Review the TVs and each **Room assignment**, including the Samsung/Apple TV names and the resulting room name. Deselect anything you do not want. Excluded TVs are never assigned to a room; rooms with no selected member TV are skipped.
3. Choose whether to copy stars and remote appearance, then tap **Import setup**.
4. Select an imported room and pair the TVs on this iPhone when needed. TV details, IP/MAC settings, stars and layout transfer; authorization tokens/keys do not.

Configured rooms are preserved. Identical room assignments reuse the saved room. An empty room with the same name can be filled, including when the TV profiles were imported earlier. Conflicting mappings are added as a separately named room and shown in the preview. Reimporting the same setup does not duplicate rooms. Existing TV profiles keep their saved name, IP, MAC and local credentials; equal names or IPs alone never merge TV identities.

**Files made by 3.5.1 contain no room assignments.** Update both phones and create a new transfer to send them. Older files remain readable with their prior rooms-local behavior. New files containing room mappings use payload version 4 so an older receiver cannot silently ignore their mappings.

## Stars and protection

**Copy sender’s stars** copies the universal-stars setting/global list and replaces individual lists only for selected Apple TVs. Missing apps stay hidden until installed. Empty lists transfer too. Turn this choice off to keep local stars. Layout/pad copying is independent.

AirDrop encrypts transport. Direct `.atvsetup` files themselves have no password; share them only with someone you trust. To protect a saved/shared file, enable **Require a transfer phrase** before preparing it. The resulting `.roomremote` file uses AES-GCM and salted PBKDF2-SHA256 (600,000 iterations); share its four-word phrase separately. Legacy phrases and original long codes remain readable. The protection choice is remembered. There is no cloud relay or automatic expiry. [AirDrop security](https://support.apple.com/guide/security/airdrop-security-sec2261183f4/web).

Export files use complete iOS file protection in the app’s temporary directory and are removed on explicit dismissal/reset. All incoming data is size/nesting bounded and validated before secrets or excluded legacy room data are discarded. Receiving a file never applies it without confirmation. Imports send no TV control commands. Physical proximity transfer and actual-TV pairing still need device validation.

If a receiving phone previously copied Samsung access, use **gear → Manage TVs → expand Saved TVs → select the Samsung → Re-pair**, then approve that phone. Token sharing is an unconfirmed possible contributor to repeated Allow prompts, not an established cause. Earlier copied Apple TV access should similarly be re-paired on the receiving phone. Re-pair preserves TV details, stars and room assignments. Updates/imports do not automatically erase existing local authorization.
