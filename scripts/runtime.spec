# -*- mode: python ; coding: utf-8 -*-
import os
from pathlib import Path
ROOT = Path(SPECPATH).parent
from PyInstaller.utils.hooks import collect_submodules
from PyInstaller.utils.hooks import collect_all
from PyInstaller.utils.hooks import copy_metadata

datas = []
binaries = []
hiddenimports = []
datas += copy_metadata('mcp')
datas += copy_metadata('fastapi')
datas += copy_metadata('anyio')
datas += copy_metadata('pydantic')
hiddenimports += collect_submodules('uvicorn')
datas.append((str(ROOT / 'src/constant_watch/static'), 'constant_watch/static'))


a = Analysis(
    [str(ROOT / 'scripts/runtime-entry.py')],
    pathex=[str(ROOT / 'src')],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['pytest'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='constant-watch',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch='arm64',
    codesign_identity=os.environ.get('CODE_SIGN_IDENTITY', '-'),
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='constant-watch',
)

app = BUNDLE(coll, name='Runtime.app', bundle_identifier='local.constantwatch.runtime', version='0.1.0', info_plist={'LSUIElement': True, 'LSMinimumSystemVersion': '14.0'})
