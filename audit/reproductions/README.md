# Targeted audit reproductions

The Swift scripts require an Apple Swift toolchain; the iOS build also requires an installed Xcode iPhone Simulator SDK. The Samsung Python probe requires Python and its already-inspected local source snapshots. Interface checks use Node, a temporary Playwright installation, and headless Chrome. These scripts do not install their own dependencies, access TVs, sign an app, or produce an IPA.

`check-parsers.py` reads exactly two source files from previously inspected local Git clones, compiles them against Foundation, and runs malformed inputs in separate processes. SwiftATV uses a minimal error-enum stub. A crashing child is recorded as an audit result and core files are disabled. Sources are not redistributed here, particularly because itsytv-core's pinned tree lacks a complete license file.

Example with the source clones created during this audit:

```sh
python3 audit/reproductions/check-parsers.py \
  --sources /private/tmp/remote-alternatives-audit \
  --output audit/reproductions/parser-results.json
```

`check-swift-build.py` validates clean clones against every revision in `dependency-pins.json`, copies SwiftATV to a temporary directory, and changes only four dependency URLs to local paths. Apple dependency manifests use their supported `SWIFTCI_USE_LOCAL_DEPS` mode. No implementation source is changed. The graph is an explicitly chosen set of minimum allowed versions; it is not the graph that an unconstrained upstream package would resolve today.

```sh
python3 audit/reproductions/check-swift-build.py \
  --sources /private/tmp/remote-alternatives-audit \
  --outputs /private/tmp/remote-build-reproduction \
  --mode ios-build

python3 audit/reproductions/check-swift-build.py \
  --sources /private/tmp/remote-alternatives-audit \
  --outputs /private/tmp/remote-build-reproduction \
  --mode macos-tests
```

The initial audit used equivalent recorded commands with separate persistent scratch directories so complete logs could be preserved. Its SwiftPM manifest sandbox failed with “sandbox_apply: Operation not permitted” in this tool environment, so SwiftPM's inner sandbox was disabled; the outer tool filesystem/network restrictions remained in place. No SwiftProtobuf plugin was attached or invoked. The protobuf/abseil submodules were fetched at recorded commits because SwiftPM validates the declared `protoc` product's source availability, even when only the Swift runtime library is consumed.

Passing an iOS simulator library build establishes compile compatibility with that SDK and deployment target. It does not establish PIN pairing, permissions, foreground/background behavior, current tvOS interoperability, or signed iPhone distribution.

The recorded [build validation](build-validation.json) shows a successful iOS simulator library compile and 478 unique macOS tests passing across two runs. Nine tests initially hit the outer sandbox's network-listener restriction; their isolated fake-server rerun passed. Both logs are preserved, including the original environment failures.

Samsung evidence is preserved separately in [samsung-validation.json](samsung-validation.json). `samsung-python-probes.py` preserves the five already-executed offline probes with socket creation and URL access blocked; [captured stdout](samsung-python-probes.stdout.txt) records the actual results. It uses the inspected `pedrinho/samsung_remote` clone at `/private/tmp/tv-remote-audit-samsung` (revision `2c561a699045159b6447f8165abcdcb893fdd601`), the extracted published Samsungctl 0.7.0 archive at `/private/tmp/samsungctl-0.7.0`, and the existing `websocket` Python module. It installs nothing. From this workspace: `python3 audit/reproductions/samsung-python-probes.py`.

`smartcast-commands.sh` records the exact successful SmartCast macOS build/test command against revision `0b78b61a59c153f6b8b7b9010b1a6fbc61cd6670` at `/private/tmp/tv-remote-audit-smartcast`. Its [captured tool-output transcript](smartcast-macos-tests.tool-output.log) records 12 pure unit tests passing; the [initial environment failure excerpt](smartcast-initial-environment-failure.tool-output.log) records why SwiftPM's inner sandbox was disabled. These transcripts were preserved from the completed run, with no rerun during preservation. This is macOS package validation, not an iOS build or device-pairing result.

`tvcommander-encoding-harness.swift` preserves the already-executed offline helper check; [captured stdout](tvcommander-encoding.stdout.txt) records encoding, token-query splitting and the malformed-MAC packet. It compiles only TVCommanderKit's `TVCommanderKit+Models.swift` and `TVCommanderKit+Extensions.swift` at revision `4c7b27aefe308a1a514f676a8db3cd56ec439f0d` with this harness, using `swiftc -module-cache-path /private/tmp/tv-remote-tvcommander-module-cache`. No Starscream/SmartView dependency or full TVCommanderKit package was executed. All source snapshots are external; clone paths must be restored at the stated revisions if temporary storage is removed.

`apple-parser-repro.py` compiles four reviewed pure parser files from the linked Apple TV project and bounds each probe to two seconds. [Results](apple-parser-results.jsonl) include source hashes, hangs, traps, and correctly rejected fixtures. Run `python3 audit/reproductions/apple-parser-repro.py /path/to/appletv-remote` against revision `28129f25bb9b466a3c4125b14edf8d7237599929`. It does not execute the package, pairing, or network paths.

`design-qa.cjs` checks only the authored simulated interface in a fresh headless Chrome session. It expects `playwright-core` 1.58.2 in `/private/tmp/tv-remote-design-qa`, and a rendered standalone preview supplied as its URL argument. It validates routing, sheets, PIN input, partial/total outages, unavailable text entry, and responsive layout in six width/appearance combinations. [UI results](../../design/qa/results.json) and screenshots are preserved in `design/qa`. These are web-preview checks, not native iPhone accessibility or device-control tests.

The [0.3.22 native validation](atv-remote-0.3.22-validation.json) binds the unsigned IPA, source hashes, native test report and simulator results. Commands in its individual JSON reports can be repeated with a local iOS 27 simulator after `build-for-testing`; replace the simulator UUID/result-bundle path for your machine. The unit target executes 185 tests; three named UI cases cover Home dispatch, layout/pad persistence and geometry, and shortcut success/back navigation. Twelve UI methods compile; nine were not rerun. Initial UI failures and subsequent corrected runs are preserved separately. The [release notes](../../docs/atv-remote-0.3.22-validation.md) explain scope and physical-TV limitations. Synthetic UI fixtures exist only in DEBUG and are excluded from the unsigned iPhone IPA.

The [0.3.23 validation](atv-remote-0.3.23-validation.json) records 189 unit tests and two targeted simulator UI cases passing against 49 frozen native inputs. The new UI case backgrounds then reactivates the same process, checks both connected indicators and dispatches Home again using synthetic devices. It does not test physical keepalive, force-quit socket survival or Wi-Fi behavior. Thirteen UI methods compile; eleven were not rerun. The [release report](../../docs/atv-remote-0.3.23-validation.md) explains the preserved-session policy and process-termination limit.

The [0.3.24 validation](atv-remote-0.3.24-validation.json) binds 206 unit tests and four targeted UI tests to 52 native input hashes. Model/race tests substitute effects to check bounded scheduling, first success, cancellation and late-loser disposal. Four Keychain tests use randomly named synthetic records and clean them up. UI checks cover Auto menu/title/persistence, the actual timer reflecting a synthetic observed loss, background retention and Home gestures. Fifteen UI methods compile; eleven were not rerun. No physical TV race, new pairing or network-loss measurement is claimed. The [release report](../../docs/atv-remote-0.3.24-validation.md) describes the polling and multi-room limitations.
