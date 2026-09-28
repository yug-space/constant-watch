"""Conservative source metadata, screen-noise filtering, and explainable topic labels."""
import re
import unicodedata
from pathlib import PurePosixPath
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode, unquote

UI_LINES = frozenset('file|edit|view|window|help|document actions|back|forward|reload|refresh|close|close tab|new tab|search|address and search bar|toolbar|menu bar|sidebar|zoom in|zoom out|minimize|maximize|share|more|settings|preferences|bookmark this tab|show sidebar|hide sidebar'.split('|'))
GENERIC_TITLES = UI_LINES | {'untitled', 'untitled window', 'chatgpt', 'google chrome', 'safari', 'textedit', 'finder', 'constant watch', 'system settings', 'voiceos', 'whatsapp', 'new chat'}
DOCUMENT_EXTENSIONS = {'.txt', '.md', '.pdf', '.rtf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.ppt', '.pptx', '.pages', '.numbers', '.key', '.html'}
SECRET_QUERY = re.compile(r'token|secret|password|passwd|api.?key|credential|signature|session|authorization|^auth$|^code$', re.I)


def line_key(value):
    return ' '.join(re.findall(r'\w+', unicodedata.normalize('NFKC', value).casefold()))


def clean_screen_text(ax, ocr='', title=''):
    seen, kept, removed = set(), [], 0
    for line in (ax + '\n' + ocr).splitlines():
        line = line.strip()
        key = ' '.join(unicodedata.normalize('NFKC', line).casefold().split())
        if not key:
            continue
        if key in seen or key in UI_LINES or key == ' '.join(unicodedata.normalize('NFKC', title).casefold().split()) or re.fullmatch(r'\d{1,2}:\d{2}:\d{2}', line):
            removed += 1
            continue
        seen.add(key)
        kept.append(line)
    return '\n'.join(kept)[:12000], removed


def safe_source(value):
    """Only observed HTTP(S) or local document URLs; strip credentials and secret query values."""
    try:
        if not value or len(value) > 4096 or any(ord(c) < 32 for c in value):
            return ''
        parts = urlsplit(value)
        if parts.scheme in ('http', 'https') and parts.hostname:
            host = parts.hostname
            if ':' in host:
                host = f'[{host}]'
            if parts.port:
                host += f':{parts.port}'
            query = urlencode([(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if not SECRET_QUERY.search(k)])
            return urlunsplit((parts.scheme, host, parts.path, query, ''))
        if parts.scheme == 'file' and parts.netloc in ('', 'localhost') and parts.path.startswith('/'):
            if PurePosixPath(unquote(parts.path)).suffix.lower() in DOCUMENT_EXTENSIONS:
                return urlunsplit(('file', '', parts.path, '', ''))
    except (ValueError, TypeError):
        pass
    return ''


def document_name(title, source):
    if source.startswith('file:'):
        return PurePosixPath(unquote(urlsplit(source).path)).name
    return re.sub(r'\s+[—–-]\s+(?:Google Chrome|Safari|TextEdit|Firefox|Microsoft Edge)(?:\s.*)?$', '', title, flags=re.I).strip()[:300]


def topic_labels(title, text, source=''):
    found = {}
    # Explicit project names are suggestions, never model-invented labels.
    for match in re.finditer(r'\b[Pp]roject\s+([A-Z][\w-]*(?:[ \t]+[A-Z][\w-]*){0,2})\b', title + '\n' + text[:6500]):
        name = match.group(1).strip()
        if name.casefold() in {'management', 'settings', 'files', 'name', 'atlas constantwatchfirstmoment'}:
            continue
        key = line_key(name)
        found[key] = {'key': key, 'label': name, 'basis': 'Explicit project name in captured text'}
    doc = document_name(title, source)
    stem = re.sub(r'\.(?:md|txt|pdf|docx?|pages|xlsx?|csv|pptx?)$', '', doc, flags=re.I)
    first = re.split(r'\s+[—–|:-]\s+', stem)[0].strip()
    if 2 <= len(first) <= 65 and first.casefold() not in GENERIC_TITLES and len(first.split()) <= 7:
        key = line_key(first.removeprefix('Project '))
        if key and key not in found:
            found[key] = {'key': key, 'label': first.removeprefix('Project '), 'basis': 'Matching document or window title'}
    return list(found.values())[:4]
