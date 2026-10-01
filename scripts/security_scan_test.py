#!/usr/bin/env python3
"""Small fixture tests proving security_scan.py exceptions are path-specific."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCAN = ROOT / "scripts" / "security_scan.py"
ENDPOINT = "https://dav.jianguoyun.com/dav/"


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run(root: Path, expected: int) -> None:
    completed = subprocess.run(
        [sys.executable, str(SCAN), "--root", str(root)], text=True, capture_output=True, check=False
    )
    if completed.returncode != expected:
        raise AssertionError(f"expected {expected}, got {completed.returncode}: {completed.stderr}")


def main() -> int:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        write(root, "Sources/YTools/Services/ClipboardCloudSyncService.swift", f'''let server = URL(string: "{ENDPOINT}")!\nlet session = URLSession(configuration: .ephemeral, delegate: CloudRedirectPolicy(), delegateQueue: nil)\nlet value = try await session.bytes(for: request)\nfunc redirect(_ session: URLSession) {{}}\n''')
        write(root, "src/YTools.Windows/Services/ClipboardCloudSyncService.cs", '''using WebDAVClient;\nclass Sync { const string Server = "https://dav.jianguoyun.com"; void Configure() { BasePath = "/dav/"; var first = new Client(); } }\n''')
        write(root, "Sources/YTools/Services/ActionDispatcher.swift", '''let executable = "/usr/bin/pmset"\nlet process = Process()\nprocess.executableURL = URL(fileURLWithPath: executable)\nprocess.arguments = ["displaysleepnow"]\n''')
        write(root, "Sources/YTools/Other.swift", "// URLSession in a comment must not fail the scan\n")
        run(root, 0)

        write(root, "Sources/YTools/Other.swift", "let client = URLSession.shared\n")
        run(root, 1)
        write(root, "Sources/YTools/Other.swift", "")

        write(root, "Sources/YTools/Services/ClipboardCloudSyncService.swift", 'let server = URL(string: "https://example.invalid/")!\nlet session = URLSession(configuration: .ephemeral, delegate: CloudRedirectPolicy(), delegateQueue: nil)\nlet value = try await session.bytes(for: request)\nfunc redirect(_ session: URLSession) {}\n')
        run(root, 1)
        write(root, "Sources/YTools/Services/ClipboardCloudSyncService.swift", f'''let server = URL(string: "{ENDPOINT}")!\nlet session = URLSession(configuration: .ephemeral, delegate: CloudRedirectPolicy(), delegateQueue: nil)\nlet value = try await session.bytes(for: request)\nfunc redirect(_ session: URLSession) {{}}\nlet bypass = URLSession.shared\n''')
        run(root, 1)
        write(root, "Sources/YTools/Services/ClipboardCloudSyncService.swift", f'''let server = URL(string: "{ENDPOINT}")!\nlet session = URLSession(configuration: .ephemeral, delegate: CloudRedirectPolicy(), delegateQueue: nil)\nlet value = try await session.bytes(for: request)\nfunc redirect(_ session: URLSession) {{}}\n''')

        write(root, "Sources/YTools/Services/ActionDispatcher.swift", '''let executable = "/usr/bin/pmset"\nlet process = Process()\nprocess.executableURL = URL(fileURLWithPath: executable)\nprocess.arguments = ["displaysleepnow"]\nlet bypass = Process()\n''')
        run(root, 1)
        write(root, "Sources/YTools/Services/ActionDispatcher.swift", '''let executable = "/usr/bin/pmset"\nlet process = Process()\nprocess.executableURL = URL(fileURLWithPath: executable)\nprocess.arguments = ["displaysleepnow"]\n''')

        write(root, "src/YTools.Windows/Services/ClipboardCloudSyncService.cs", '''using WebDAVClient;\nclass Sync { const string Server = "https://dav.jianguoyun.com"; void Configure() { BasePath = "/dav/"; var first = new Client(); var second = new Client(); } }\n''')
        run(root, 1)
    print("security_scan fixture tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
