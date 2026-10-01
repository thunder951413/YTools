#!/usr/bin/env python3
"""Reject network, dynamic-code, and shell entry points in product sources.

The one intentionally networked feature is the encrypted Jianguoyun WebDAV
clipboard synchronizer.  Its allowance is deliberately tied to the two
implementation files and their fixed endpoint, rather than to a directory.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


SWIFT_SYNC = Path("Sources/YTools/Services/ClipboardCloudSyncService.swift")
WINDOWS_SYNC = Path("src/YTools.Windows/Services/ClipboardCloudSyncService.cs")
SETTINGS_ENDPOINT = Path("src/YTools.Windows/UI/SettingsWindow.xaml.cs")
MAC_ACTION_DISPATCHER = Path("Sources/YTools/Services/ActionDispatcher.swift")
ENDPOINT = "https://dav.jianguoyun.com/dav/"

# These checks target executable source text. Comments are removed first so a
# security explanation or a documentation string cannot create a false alarm.
FORBIDDEN = {
    ".swift": (
        r"\bURLSession\b",
        r"\bNWConnection\b",
        r"\bWKWebView\b",
        r"\bWebKit\b",
        r"\bdlopen\s*\(",
        r"\bNSAppleScript\b",
        r"\bProcess\s*\(",
        r"\bprocess\.(?:arguments|executableURL)\s*=",
        r"\bNSTask\b",
        r"/bin/(?:sh|bash|zsh)",
    ),
    ".cs": (
        r"\bHttpClient\b",
        r"\bWebClient\b",
        r"\bTcpClient\b",
        r"\bUdpClient\b",
        r"\bNetworkStream\b",
        r"\bSocket\s*\(",
        r"\bWebDAVClient\b",
        r"\bnew\s+Client\s*\(",
        r"\bAssembly\.Load(?:From|File)?\s*\(",
        r"\bActivator\.CreateInstance\s*\(",
        r"\bAppDomain\.(?:CurrentDomain\.Load|CreateDomain)\s*\(",
        r"(?:cmd|powershell)\.exe",
        r"/bin/(?:sh|bash|zsh)",
    ),
}


def without_comments(text: str, suffix: str) -> str:
    """Keep string literals, but mask comments while preserving line numbers."""
    result: list[str] = []
    index = 0
    quote: str | None = None
    while index < len(text):
        current = text[index]
        following = text[index + 1] if index + 1 < len(text) else ""
        if quote is not None:
            result.append(current)
            if current == "\\" and index + 1 < len(text):
                result.append(text[index + 1])
                index += 2
                continue
            if current == quote:
                quote = None
            index += 1
            continue
        if current in {"\"", "'"}:
            quote = current
            result.append(current)
            index += 1
            continue
        if current == "/" and following == "/":
            end = text.find("\n", index)
            if end == -1:
                break
            result.append("\n")
            index = end + 1
            continue
        if current == "/" and following == "*":
            end = text.find("*/", index + 2)
            end = len(text) if end == -1 else end + 2
            result.append("\n" * text[index:end].count("\n"))
            index = end
            continue
        result.append(current)
        index += 1
    return "".join(result)


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def allowed_network(path: Path, text: str) -> list[str]:
    """Validate the only two explicit network allowances and return errors."""
    errors: list[str] = []
    url_literals = re.findall(r"https?://[A-Za-z0-9._/~:-]+", text)
    if path == SWIFT_SYNC:
        if ENDPOINT not in text:
            errors.append("Swift sync service must retain the fixed Jianguoyun DAV endpoint")
        if not re.search(r"URLSession\(configuration:\s*\.ephemeral,\s*delegate:\s*CloudRedirectPolicy\(\),\s*delegateQueue:\s*nil\)", text):
            errors.append("Swift sync service must retain its ephemeral no-redirect URLSession")
        if not re.search(r"session\.bytes\s*\(for:\s*request\)", text):
            errors.append("Swift sync service may only send its validated URLRequest through session.bytes(for: request)")
        session_tokens = list(re.finditer(r"\bURLSession\b", text))
        constructor_tokens = list(re.finditer(r"\bURLSession\s*\(", text))
        delegate_tokens = list(re.finditer(r":\s*URLSession\b", text))
        allowed_starts = {match.start() for match in constructor_tokens}
        allowed_starts.update(match.start() + match.group(0).rfind("URLSession") for match in delegate_tokens)
        if len(constructor_tokens) != 1 or len(delegate_tokens) != 1 or {match.start() for match in session_tokens} != allowed_starts:
            errors.append("Swift sync service may contain exactly one URLSession constructor and one delegate type annotation")
        if any(url != ENDPOINT for url in url_literals):
            errors.append("Swift sync service contains a non-fixed HTTPS endpoint")
    elif path == WINDOWS_SYNC:
        if 'Server = "https://dav.jianguoyun.com"' not in text or 'BasePath = "/dav/"' not in text:
            errors.append("Windows sync service must retain the fixed Jianguoyun DAV endpoint")
        if not re.search(r"\bWebDAVClient\b", text):
            errors.append("Windows sync service may only use its existing WebDAVClient transport")
        if len(re.findall(r"\bWebDAVClient\b", text)) != 1 or len(re.findall(r"\bnew\s+Client\s*\(", text)) != 1:
            errors.append("Windows sync service may contain exactly one WebDAVClient import and one Client construction")
        if any(url != "https://dav.jianguoyun.com" for url in url_literals):
            errors.append("Windows sync service contains a non-fixed HTTPS endpoint")
    elif path == SETTINGS_ENDPOINT:
        # This is descriptive UI text, not a transport. It may name only the
        # same audited endpoint used by the synchronizer.
        if any(url != ENDPOINT for url in url_literals):
            errors.append("settings may describe only the fixed Jianguoyun DAV endpoint")
    elif url_literals:
        errors.append("network endpoint is not allowed in this product source")
    if path == MAC_ACTION_DISPATCHER:
        if (
            'let executable = "/usr/bin/pmset"' not in text
            or 'process.executableURL = URL(fileURLWithPath: executable)' not in text
            or 'process.arguments = ["displaysleepnow"]' not in text
            or len(re.findall(r"\bProcess\s*\(", text)) != 1
            or len(re.findall(r"\bprocess\.executableURL\s*=", text)) != 1
            or len(re.findall(r"\bprocess\.arguments\s*=", text)) != 1
        ):
            errors.append("macOS ActionDispatcher may only retain its fixed pmset display-sleep command")
    return errors


def scan(root: Path) -> list[str]:
    errors: list[str] = []
    for relative_root in (Path("Sources"), Path("src")):
        directory = root / relative_root
        if not directory.exists():
            continue
        for path in sorted(directory.rglob("*")):
            if path.suffix not in FORBIDDEN or any(part in {"bin", "obj"} for part in path.parts):
                continue
            source = path.read_text(encoding="utf-8")
            relative = path.relative_to(root)
            code = without_comments(source, path.suffix)
            errors.extend(f"{relative}: {message}" for message in allowed_network(relative, code))
            for pattern in FORBIDDEN[path.suffix]:
                for match in re.finditer(pattern, code):
                    token = match.group(0)
                    if relative == SWIFT_SYNC and token == "URLSession":
                        continue
                    if relative == WINDOWS_SYNC and token in {"WebDAVClient", "new Client("}:
                        continue
                    if relative == MAC_ACTION_DISPATCHER and (
                        token == "Process(" or token.startswith("process.arguments") or token.startswith("process.executableURL")
                    ):
                        continue
                    errors.append(f"{relative}:{line_number(code, match.start())}: forbidden API `{token}`")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = scan(args.root.resolve())
    if errors:
        print("Security scan failed:", file=sys.stderr)
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Security scan passed: only the fixed Jianguoyun WebDAV synchronizer is network-enabled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
