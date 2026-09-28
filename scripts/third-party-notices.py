"""Collect dependency metadata and available license texts for redistribution."""
import importlib.metadata as metadata
from pathlib import Path
import sys

parts = ["Constant Watch — third-party notices\n", "Python runtime license: https://docs.python.org/3/license.html\n"]
for dist in sorted(metadata.distributions(), key=lambda item: item.metadata.get("Name", "").lower()):
    name = dist.metadata.get("Name", "")
    if name.lower() in {"constant-watch", "pytest", "pytest-asyncio", "pyinstaller-hooks-contrib", "altgraph", "macholib", "iniconfig", "pluggy"}:
        continue
    parts.append(f"\n{'=' * 60}\n{name} {dist.version}\nLicense: {dist.metadata.get('License-Expression') or dist.metadata.get('License') or 'See package notices below'}\n")
    for file in dist.files or []:
        if any(part.lower().startswith(('license', 'copying', 'notice')) for part in file.parts):
            path = Path(dist.locate_file(file))
            if path.is_file():
                parts.append(f"\n{file}\n{path.read_text(errors='replace')}\n")
# The interpreter's complete license is shipped beside the frozen runtime too.
for path in [Path(sys.base_prefix) / 'LICENSE.txt', Path(sys.base_prefix) / 'lib/python3.12/LICENSE.txt']:
    if path.exists():
        parts.append(path.read_text()); break
Path(sys.argv[1]).write_text(''.join(parts))
