# Four-word transfer phrase audit

Version 0.3.11 replaces the generated eight-group transfer code with four random words. Each new export receives a fresh phrase and encrypted file. The phrase is displayed separately and never placed in the shared file. New files require 0.3.11 or later on both phones; legacy version 1 files still accept their original codes.

## Word selection and strength

The bundled dictionary derives from [EFF’s long wordlist](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt), created by Joseph Bonneau. Its numeric dice labels and four hyphenated entries are omitted, leaving 7,772 unique lowercase ASCII words of at most nine letters. This makes hyphen separators unambiguous without merging `yo-yo` into the distinct `yoyo`. Source hash, modifications and licensing are recorded in [provenance](../design/assets/transfer-wordlist-provenance.json). Attribution and the [CC BY 4.0 policy](https://www.eff.org/copyright) are bundled in ThirdPartyNotices.

Four independent uniform choices provide 4 × log2(7772) = **51.696 bits**, compared with 160 bits in the previous random code. The slow KDF raises guessing cost; it does not restore that entropy. [EFF generally recommends six words](https://www.eff.org/dice). Four is the user-requested ease-of-transfer choice, not an equivalent-strength replacement or an EFF endorsement. The generated phrase should remain separate from its file.

Selection uses SecRandomCopyBytes and UInt32 rejection sampling. Values below 4,294,962,640 map uniformly modulo 7,772; the incomplete final bucket is discarded. Sampling allows repeated words, and their order matters. Random-source errors propagate without a weaker fallback. Tests check the exact boundary and a forced rejected draw; a small sample of distinct generated phrases does not itself prove entropy.

Input is bounded to 128 UTF-8 bytes. ASCII capitals normalize to lowercase; spaces, tabs, CR/LF and hyphens separate words. Exactly four complete dictionary entries are required. Unknown words, non-ASCII characters and other punctuation reject. The fixed dictionary is part of the version 2 compatibility contract.

## Encryption and legacy compatibility

New envelopes contain version 2, `kdf: pbkdf2-sha256`, exactly 600,000 iterations, a fresh 16-byte salt and AES-GCM combined ciphertext. CommonCrypto derives a 32-byte key using PBKDF2-HMAC-SHA256, the normalized phrase, and a salt prefixed with the fixed version/KDF/cost domain. AES-GCM authenticates that domain and salt. The selected work factor follows [OWASP’s PBKDF2-SHA256 guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2); applying it to this local encrypted transfer is an implementation choice, not a claim of compliance certification or memory-hard password hashing.

Envelope decoding checks supported format, version and exact KDF metadata before expensive work. Salt/ciphertext bounds and JSON nesting limits remain. Untrusted iteration counts are never passed to CommonCrypto. Changing version, salt, KDF, ciphertext or cost cannot silently select a weaker scheme. There is no retry through another format after authentication failure.

Legacy version 1 imports keep the exact original Crockford-code decoding, HKDF-SHA256 domain and AES-GCM authenticated data. Version 1 rejects new KDF fields, including null. An independently produced Python HKDF/AES-GCM fixture with public fake TV data verifies this path without relying on the changed exporter. Its SHA-256 is `755d3df6bca28b6aa4adb150c933f6f8df7678ec7c7ed822d7fc50ca1fde836c`.

The decrypted TV/room/pairing payload stays version 1. Existing device identity, certificate pin, copied Apple pairing identity, wake MAC, conflict preservation and explicit import approval rules remain. New exports accept phrases only; older app versions cannot unlock their version 2 envelopes.

## UI lifetime and remaining checks

Encryption and unlocking run in detached tasks. Parent cancellation cancels the child, and checks before and after its synchronous work discard canceled results. Original request UUID guards prevent a closed, backgrounded or superseded screen from publishing a review or writing an export afterward. A CommonCrypto call cannot be interrupted midway; bounded work may finish before its canceled result is discarded.

Only the encrypted file URL enters the share sheet. The phrase stays in temporary sensitive view state and a secure import field. Explicit copying remains local-only with five-minute clipboard expiry. Background/close reset clears the export and phrase; encrypted temporary files use complete file protection. There is no global file/phrase expiry or single-use enforcement. No plaintext credential or phrase logging was found in the changed code.

The actual-source tests cover encryption/authentication, a separate Python key vector, legacy wire compatibility, strict metadata, normalization and generation boundaries. Native UI compilation checks Swift concurrency and both phrase/legacy UI paths. Face ID, AirDrop, clipboard behavior, UI cancellation and actual iPhone performance were source-reviewed or compiled, not executed. The preliminary CommonCrypto proof took about 94–103 ms on this Mac; this does not establish iPhone timing.

[Independent source review](../audit/reproductions/atv-remote-0.3.11-phrase-source-review.json), [release validation](atv-remote-0.3.11-validation.md), [sharing instructions](share-pairings.md).
