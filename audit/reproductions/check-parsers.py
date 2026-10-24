#!/usr/bin/env python3
"""Compile the two previously reviewed Foundation-only parsers at pinned commits.

No packages, plugins, global installs, device connections, or network requests.
Upstream sources are read from separate local clones; they are not redistributed
here. This is a targeted parser comparison, not a package or device test suite.
"""
import argparse
import json
from pathlib import Path
import resource
import subprocess
import tempfile

PINNED = {
    "swift-atv": (
        "2cc34befa6826f3824846a73d0a1f674ee7688fe",
        "Sources/SwiftATV/Support/OPACK.swift",
        "OPACK.decode",
    ),
    "itsytv-core": (
        "052d9a9a0416d577119316ea813aa3b822b408e5",
        "Sources/ItsytvCore/Protocol/OPACK.swift",
        "OPACK.unpack",
    ),
}


def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, required=True,
                        help="Directory containing swift-atv and itsytv-core clones")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    template = Path(__file__).with_name("parser-harness.swift").read_text()
    results = {"toolchain": subprocess.check_output(["swiftc", "--version"], text=True).strip(),
               "scope": "Isolated OPACK sources; Foundation only; SwiftATV error type stubbed",
               "libraries": {}}
    with tempfile.TemporaryDirectory(prefix="remote-parser-audit-") as temp:
        scratch = Path(temp)
        for library, (revision, relative_path, decode) in PINNED.items():
            clone = args.sources / library
            actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=clone, text=True).strip()
            if actual != revision:
                raise SystemExit(f"Unexpected commit for {library}: {actual}")
            # git show ignores any uncommitted working-tree changes.
            source = subprocess.check_output(["git", "show", f"{revision}:{relative_path}"],
                                             cwd=clone, text=True)
            work = scratch / library
            work.mkdir()
            (work / "OPACK.swift").write_text(source)
            (work / "main.swift").write_text(template.replace("__DECODE__", decode))
            compile_sources = [str(work / "OPACK.swift"), str(work / "main.swift")]
            if library == "swift-atv":
                stub = work / "ATVError.swift"
                stub.write_text("public enum ATVError: Error { case invalidData(String) }\n")
                compile_sources.append(str(stub))
            binary = work / "harness"
            subprocess.run(["swiftc", "-module-cache-path", str(scratch / "ModuleCache"),
                            *compile_sources, "-o", str(binary)], check=True,
                           capture_output=True, text=True, timeout=120)
            tests = {}
            for case in ["normal", "largeLength", "truncatedArray", "trailingBytes"]:
                run = subprocess.run([str(binary), case], capture_output=True, text=True,
                                     timeout=10, preexec_fn=no_core)
                tests[case] = {"exit_code": run.returncode, "stdout": run.stdout.strip(),
                               "stderr_first_line": run.stderr.splitlines()[:1]}
            results["libraries"][library] = {"revision": revision, "tests": tests}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
