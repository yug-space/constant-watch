from pathlib import Path
from PyInstaller.utils.hooks import collect_submodules, collect_data_files, copy_metadata, collect_all
root = Path(SPECPATH).parent
static = root/'src/constant_watch/static'
extra = [(str(p), str(Path('constant_watch/static') / p.relative_to(static).parent))
         for p in static.rglob('*') if p.is_file() and p.name != 'alpine-hero.png']
extra += [(str(root/'src/constant_watch/windows_capture.ps1'), 'constant_watch')]
for package in ['mcp', 'fastapi', 'pydantic', 'anyio', 'pywebview', 'proxy_tools']:
    extra += copy_metadata(package)
extra += collect_data_files('webview')
audio_binaries, audio_imports = [], []
for package in ['faster_whisper', 'ctranslate2', 'av', 'onnxruntime', 'tokenizers', 'soundcard']:
    d, b, h = collect_all(package)
    extra += d; audio_binaries += b; audio_imports += h
a = Analysis([str(root/'windows/entry.py')], pathex=[str(root/'src')], datas=extra, binaries=audio_binaries,
    hiddenimports=audio_imports + collect_submodules('uvicorn') + ['webview.platforms.edgechromium','webview.platforms.winforms'],
    excludes=['pytest','PIL','tkinter','PyQt5','PyQt6','PySide2','PySide6'], optimize=0)
pyz = PYZ(a.pure)
icon = str(root/'windows/constant-watch.ico')
service = EXE(pyz,a.scripts,[('X utf8',None,'OPTION')],exclude_binaries=True,name='constant-watch-service',console=True,icon=icon)
desktop = EXE(pyz,a.scripts,[('X utf8',None,'OPTION')],exclude_binaries=True,name='constant-watch',console=False,icon=icon)
coll = COLLECT(service,desktop,a.binaries,a.datas,name='Constant Watch')
