#!/usr/bin/env python3
"""Reject network, dynamic-code, and shell entry points in product sources.

Two features are intentionally networked: the encrypted Jianguoyun WebDAV
clipboard synchronizer and the opt-in AI translator. Each allowance is tied to
its implementation file (not a directory): the synchronizer to its fixed
endpoint, the translator to its provider presets and the validated,
user-configured endpoint.
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
WINDOWS_ACTION_DISPATCHER = Path("src/YTools.Windows/Services/ActionDispatcher.cs")
ENDPOINT = "https://dav.jianguoyun.com/dav/"
SWIFT_TRANSLATION = Path("Sources/YTools/Services/AITranslationService.swift")
WINDOWS_TRANSLATION = Path("src/YTools.Windows/Services/AITranslationService.cs")
TRANSLATION_PRESETS = {
    "https://api.openai.com/v1",
    "https://api.deepseek.com/v1",
    "https://dashscope.aliyuncs.com/compatible-mode/v1",
    "https://api.moonshot.cn/v1",
    "https://open.bigmodel.cn/api/paas/v4",
    "https://openrouter.ai/api/v1",
    "https://api.anthropic.com",
    "http://localhost:11434/v1",
}

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
        r"\bSocketsHttpHandler\b",
        r"\bHttpClientHandler\b",
        r"\bHttpMessageInvoker\b",
        r"\b(?:Http|Ftp|File)?WebRequest\b",
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
        r"\bProcess\s*\.\s*Start\b",
        r"\bProcessStartInfo\b",
        r"(?:cmd|powershell)\.exe",
        r"/bin/(?:sh|bash|zsh)",
    ),
}


def without_comments(text: str, suffix: str) -> str:
    """Keep string literals, but mask comments while preserving line numbers."""
    result: list[str] = []
    index = 0
    length = len(text)
    while index < length:
        current = text[index]
        following = text[index + 1] if index + 1 < length else ""

        # C# verbatim string literals: @"...", $@"...", @$"..." ("" escapes a quote).
        if suffix == ".cs":
            verbatim_prefix = 0
            if current == "@" and following == '"':
                verbatim_prefix = 2
            elif current in {"@", "$"} and following in {"@", "$"} and current != following and index + 2 < length and text[index + 2] == '"':
                verbatim_prefix = 3
            if verbatim_prefix:
                result.append(text[index : index + verbatim_prefix])
                index += verbatim_prefix
                while index < length:
                    ch = text[index]
                    result.append(ch)
                    if ch == '"' and index + 1 < length and text[index + 1] == '"':
                        result.append('"')
                        index += 2
                        continue
                    index += 1
                    if ch == '"':
                        break
                continue

        # Swift / C# raw string literals: ###"..."###, ###"""..."""###, """..."""
        hashes = 0
        probe = index
        if suffix == ".swift" and current == "#":
            while probe < length and text[probe] == "#":
                hashes += 1
                probe += 1
        elif suffix == ".cs" and current == "$":
            while probe < length and text[probe] == "$":
                probe += 1
        if probe < length and text[probe : probe + 3] == '"""':
            quote_run = 3
            while probe + quote_run < length and text[probe + quote_run] == '"':
                quote_run += 1
            closing = '"' * quote_run + ("#" * hashes)
            end_quote = probe + quote_run
            result.append(text[index:end_quote])
            index = end_quote
            close_pos = text.find(closing, index)
            if close_pos == -1:
                result.append(text[index:])
                break
            result.append(text[index : close_pos + len(closing)])
            index = close_pos + len(closing)
            continue
        if suffix == ".swift" and hashes > 0 and probe < length and text[probe] == '"':
            closing = '"' + ("#" * hashes)
            result.append(text[index : probe + 1])
            index = probe + 1
            while index < length:
                if text.startswith(closing, index):
                    result.append(closing)
                    index += len(closing)
                    break
                escape = "\\" + ("#" * hashes)
                if text.startswith(escape, index) and index + len(escape) < length:
                    result.append(text[index : index + len(escape) + 1])
                    index += len(escape) + 1
                    continue
                result.append(text[index])
                index += 1
            continue

        if current in {'"', "'"}:
            quote = current
            result.append(current)
            index += 1
            while index < length:
                ch = text[index]
                result.append(ch)
                if ch == "\\" and index + 1 < length:
                    result.append(text[index + 1])
                    index += 2
                    continue
                index += 1
                if ch == quote:
                    break
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
            end = length if end == -1 else end + 2
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
    elif path == SWIFT_TRANSLATION:
        if not re.search(r"URLSession\(configuration:\s*\.ephemeral,\s*delegate:\s*TranslationRedirectPolicy\(\),\s*delegateQueue:\s*nil\)", text):
            errors.append("Swift translation service must retain its ephemeral no-redirect URLSession")
        if not re.search(r"session\.bytes\s*\(for:\s*request\)", text):
            errors.append("Swift translation service may only send its URLRequest through session.bytes(for: request)")
        if "TranslationEndpointPolicy.requestURL(" not in text or "request.httpShouldHandleCookies = false" not in text:
            errors.append("Swift translation service must validate its endpoint and disable cookies")
        session_tokens = list(re.finditer(r"\bURLSession\b", text))
        constructor_tokens = list(re.finditer(r"\bURLSession\s*\(", text))
        delegate_tokens = list(re.finditer(r":\s*URLSession\b", text))
        allowed_starts = {match.start() for match in constructor_tokens}
        allowed_starts.update(match.start() + match.group(0).rfind("URLSession") for match in delegate_tokens)
        if len(constructor_tokens) != 1 or len(delegate_tokens) != 1 or {match.start() for match in session_tokens} != allowed_starts:
            errors.append("Swift translation service may contain exactly one URLSession constructor and one delegate type annotation")
        if any(url not in TRANSLATION_PRESETS for url in url_literals):
            errors.append("Swift translation service contains an endpoint that is not an audited preset")
    elif path == WINDOWS_TRANSLATION:
        handler = re.search(r"private readonly HttpClient _client = new\(new SocketsHttpHandler\s*\{(?P<body>[^}]*)\}\)", text)
        if handler is None:
            errors.append("Windows translation service must retain its single SocketsHttpHandler-backed HttpClient field")
        else:
            body = handler.group("body")
            for setting in ("AllowAutoRedirect = false", "UseCookies = false", "Credentials = null"):
                if setting not in body:
                    errors.append(f"Windows translation handler must keep `{setting}`")
            if re.search(r"AllowAutoRedirect\s*=\s*true|UseCookies\s*=\s*true", text):
                errors.append("Windows translation service may not re-enable redirects or cookies")
        if len(re.findall(r"\bHttpClient\b", text)) != 1 or len(re.findall(r"\bSocketsHttpHandler\b", text)) != 1:
            errors.append("Windows translation service may contain exactly one HttpClient and one SocketsHttpHandler")
        if not re.search(r"Timeout = TimeSpan\.FromSeconds\(30\)", text) or "MaximumResponseBytes" not in text:
            errors.append("Windows translation service must keep its 30 s timeout and response size cap")
        if "TranslationEndpointPolicy.TryCreateRequestUri(" not in text:
            errors.append("Windows translation service must validate its endpoint")
        client_calls = re.findall(r"\b_client\.(\w+)", text)
        if client_calls != ["SendAsync"]:
            errors.append("Windows translation service may only send through one _client.SendAsync call")
        if any(url not in TRANSLATION_PRESETS for url in url_literals):
            errors.append("Windows translation service contains an endpoint that is not an audited preset")
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
                    if relative in {SWIFT_SYNC, SWIFT_TRANSLATION} and token == "URLSession":
                        continue
                    if relative == WINDOWS_SYNC and token in {"WebDAVClient", "new Client("}:
                        continue
                    if relative == WINDOWS_TRANSLATION and token in {"HttpClient", "SocketsHttpHandler"}:
                        continue
                    if relative == WINDOWS_ACTION_DISPATCHER and (
                        token.startswith("Process")
                    ):
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
    print("Security scan passed: only the Jianguoyun WebDAV synchronizer and the opt-in AI translator are network-enabled.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
