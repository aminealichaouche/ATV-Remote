#!/usr/bin/env python3
"""Recreate the audited offline floor-dependency build in a temporary directory.

Requires already-inspected clones at dependency-pins.json revisions under
--sources/deps, including SwiftProtobuf's pinned submodules. Fetches nothing,
installs nothing, signs nothing, and modifies no upstream checkout.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT_REVISION = "2cc34befa6826f3824846a73d0a1f674ee7688fe"
REMOTE_DECLARATIONS = {
    "swift-nio": "https://github.com/apple/swift-nio.git",
    "swift-crypto": "https://github.com/apple/swift-crypto.git",
    "swift-protobuf": "https://github.com/apple/swift-protobuf.git",
    "BigInt": "https://github.com/attaswift/BigInt.git",
}


def require_revision(path, expected):
    actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=path, text=True).strip()
    if actual != expected:
        raise SystemExit(f"Unexpected commit at {path}: {actual}")
    # Only tracked modifications matter; submodule contents are checked separately.
    changed = subprocess.check_output(["git", "diff", "--name-only", "HEAD"], cwd=path, text=True).strip()
    if changed:
        raise SystemExit(f"Tracked source modified at {path}: {changed}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--outputs", type=Path, required=True)
    parser.add_argument("--mode", choices=["ios-build", "macos-tests"], required=True)
    args = parser.parse_args()
    sources = args.sources.resolve()
    root = sources / "swift-atv"
    require_revision(root, ROOT_REVISION)
    pins = json.loads(Path(__file__).with_name("dependency-pins.json").read_text())
    for name, pin in pins["dependencies"].items():
        require_revision(sources / "deps" / name, pin["revision"])
    for name in ["protobuf", "abseil"]:
        require_revision(sources / "deps/swift-protobuf/Sources/protobuf" / name,
                         pins["dependencies"]["swift-protobuf"][name + "_submodule_revision"])
    args.outputs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="remote-swift-audit-") as temp:
        scratch = Path(temp)
        package = scratch / "swift-atv"
        shutil.copytree(root, package, ignore=shutil.ignore_patterns(".git", ".build", ".swiftpm"))
        manifest = package / "Package.swift"
        original = manifest.read_text()
        adjusted = original
        for name, url in REMOTE_DECLARATIONS.items():
            adjusted, count = re.subn(r'\.package\(url: "' + re.escape(url) + r'", from: "[^"]+"\)',
                                     '.package(path: "' + str(sources / "deps" / name) + '")', adjusted)
            if count != 1:
                raise SystemExit(f"Expected one remote declaration for {name}, got {count}")
        manifest.write_text(adjusted)
        env = os.environ.copy()
        env.update({"SWIFTCI_USE_LOCAL_DEPS": "1",
                    "CLANG_MODULE_CACHE_PATH": str(scratch / "clang-cache"),
                    "SWIFTPM_MODULECACHE_OVERRIDE": str(scratch / "module-cache")})
        command = ["swift", "build" if args.mode == "ios-build" else "test", "--disable-sandbox",
                   "--package-path", str(package), "--scratch-path", str(scratch / "build"),
                   "--cache-path", str(scratch / "cache"), "--config-path", str(scratch / "config"),
                   "--security-path", str(scratch / "security")]
        if args.mode == "ios-build":
            sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
            command += ["--triple", "arm64-apple-ios16.0-simulator", "--sdk", sdk, "--target", "SwiftATV"]
        with (args.outputs / (args.mode + ".log")).open("w") as log:
            run = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=300)
        outcome = {"mode": args.mode, "root_revision": ROOT_REVISION,
                   "dependency_selection": pins["selection"], "exit_code": run.returncode,
                   "command": command, "manifest_change": "Remote declarations replaced by local paths only",
                   "network": "No fetching; tests use fake local protocol peers",
                   "scope": "Compile/tests only; no signing or physical device control"}
        (args.outputs / (args.mode + ".json")).write_text(json.dumps(outcome, indent=2) + "\n")
        print(json.dumps(outcome, indent=2))
        if run.returncode:
            raise SystemExit(run.returncode)


if __name__ == "__main__":
    main()
