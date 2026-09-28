import re

PATTERNS = [
    (re.compile(r"\b(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})\b"), "[REDACTED TOKEN]"),
    (re.compile(r"(?i)\b(password|passwd|api[_ -]?key|access[_ -]?token|secret)\s*[:=]\s*[\"']?[^\s\"']+"), r"\1: [REDACTED]"),
    (re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*"), "Bearer [REDACTED]"),
    (re.compile(r"-----BEGIN [^-]*PRIVATE KEY-----[\s\S]*?(?:-----END [^-]*PRIVATE KEY-----|$)"), "[REDACTED PRIVATE KEY]"),
]


def redact(text: str) -> str:
    for pattern, replacement in PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def merge_text(ax: str, ocr: str) -> str:
    seen, lines = set(), []
    for line in (ax + "\n" + ocr).splitlines():
        line = line.strip()
        key = " ".join(line.casefold().split())
        if key and key not in seen:
            seen.add(key)
            lines.append(line)
    return "\n".join(lines)[:12000]
