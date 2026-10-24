#!/usr/bin/env python3
"""Bounded local probes of reviewed Apple TV pure parsers; no package or network.

Usage: python3 audit/reproductions/apple-parser-repro.py /path/to/appletv-remote
Only inspected pure Foundation/CryptoKit source files are compiled. The logger import is
replaced with a no-op stub. Each parser probe runs in a fresh subprocess with a
two-second limit. This does not establish actual-TV/iOS compatibility.
"""

import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import tempfile


def child_limits():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
    repo = Path(sys.argv[1]).resolve()
    core = repo / "Sources/AppleTVProtocol"
    files = ["OPACK.swift", "TLV8.swift", "CompanionFrame.swift", "MRPMessage.swift"]
    with tempfile.TemporaryDirectory(prefix="apple-parser-repro-", dir="/private/tmp") as tmp:
        task_dir = Path(tmp)
        copied = []
        fingerprints = {}
        for name in files:
            source = (core / name).read_text()
            fingerprints[name] = hashlib.sha256(source.encode()).hexdigest()
            target = task_dir / name
            target.write_text(source.replace("import AppleTVLogging\n", ""))
            copied.append(str(target))
        (task_dir / "Stub.swift").write_text("""
import Foundation
enum Log {
    struct Sink {
        func fail(_ message: String) {}
        func trace(_ message: String) {}
        func report(_ message: String) {}
    }
    static let opack = Sink()
    static let companion = Sink()
}
""")
        (task_dir / "main.swift").write_text("""
import Foundation
let probe = CommandLine.arguments[1]
switch probe {
case "opack-valid":
    print(OPACK.decodeDict(Data([0xe1, 0x41, 0x6b, 0x09]))?["k"] as? Int == 1)
case "opack-open-valid":
    print(OPACK.decodeDict(Data([0xe1, 0x41, 0x6b, 0xef, 0x03])) != nil)
case "opack-open-unterminated":
    print(OPACK.decodeDict(Data([0xe1, 0x41, 0x6b, 0xef])) as Any)
case "opack-15-roundtrip":
    let pairs = (0..<15).map { ("k\\($0)", $0 as Any) }
    let encoded = OPACK.pack(Dictionary(uniqueKeysWithValues: pairs))
    print(OPACK.decodeDict(Data([0xe1, 0x41, 0x6b]) + encoded) as Any)
case "mrp-valid":
    print(Data([0x0a, 0x01, 0x61]).protobufBytesField(fieldNumber: 1) == Data([0x61]))
case "mrp-length-overflow":
    print(Data([0x0a] + Array(repeating: 0xff, count: 9) + [0x01]).protobufBytesField(fieldNumber: 1) as Any)
case "tlv-truncated":
    do { _ = try TLV8.decode(Data([0x06])); print("accepted") }
    catch { print("rejected: \\(error)") }
case "companion-oversized":
    var frame = Data([0x08, 0x10, 0x00, 0x01])
    do { _ = try CompanionFrame.read(from: &frame); print("accepted") }
    catch { print("rejected: \\(error)") }
default:
    fatalError("unknown probe")
}
""")
        task_env = os.environ.copy()
        task_env["CLANG_MODULE_CACHE_PATH"] = str(task_dir / "module-cache")
        task_env["SWIFT_MODULECACHE_PATH"] = str(task_dir / "module-cache")
        binary = task_dir / "probe"
        build = subprocess.run(
            ["/usr/bin/swiftc", "-module-cache-path", str(task_dir / "module-cache"),
             *copied, str(task_dir / "Stub.swift"), str(task_dir / "main.swift"),
             "-o", str(binary)],
            capture_output=True, text=True, timeout=60, env=task_env,
        )
        print(json.dumps({"source_sha256": fingerprints, "compile_exit": build.returncode}))
        if build.returncode:
            print(build.stderr[-3000:])
            return 1
        probes = ["opack-valid", "opack-open-valid", "opack-open-unterminated",
                  "opack-15-roundtrip", "mrp-valid", "mrp-length-overflow",
                  "tlv-truncated", "companion-oversized"]
        for probe in probes:
            try:
                run = subprocess.run([str(binary), probe], capture_output=True,
                                     text=True, timeout=2, preexec_fn=child_limits,
                                     env=task_env)
                print(json.dumps({"probe": probe, "exit": run.returncode,
                                  "stdout": run.stdout[:300],
                                  "stderr_first_line": run.stderr.splitlines()[:1]}))
            except subprocess.TimeoutExpired:
                print(json.dumps({"probe": probe, "outcome": "TIMEOUT", "limit_seconds": 2}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
