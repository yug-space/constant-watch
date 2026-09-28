"""Mount and test the actual disk image without installing or accessing user journals."""
from pathlib import Path
import plistlib
import subprocess
import sys
from ds_store import DSStore

image = Path(sys.argv[1]).resolve()
result = plistlib.loads(subprocess.check_output(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(image)]))
volumes = [entry for entry in result['system-entities'] if entry.get('mount-point')]
assert len(volumes) == 1
volume = Path(volumes[0]['mount-point'])
try:
    assert (volume / 'Applications').is_symlink()
    assert (volume / 'Applications').readlink() == Path('/Applications')
    with DSStore.open(str(volume / '.DS_Store'), 'r') as settings:
        view = settings['.']['icvp']
        assert view['iconSize'] == 128 and view['textSize'] == 16
        assert view['backgroundType'] == 2
        assert settings['Constant Watch.app']['Iloc'] == (245, 345)
        assert settings['Applications']['Iloc'] == (655, 345)
    assert (volume / '.background.tiff').is_file()
    app = volume / 'Constant Watch.app'
    metadata = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert metadata['LSMinimumSystemVersion'] == '14.0'
    assert (app / 'Contents/Resources/Third-party notices.txt').stat().st_size > 1000
    architecture = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/ConstantWatch')], text=True).strip()
    assert architecture == 'arm64', architecture
    subprocess.run([sys.executable, str(Path(__file__).with_name('smoke-package.py')), str(app)], check=True)
    print('PASS: mounted read-only DMG, Applications link, licenses, architecture, bundled service and MCP')
finally:
    subprocess.run(['hdiutil', 'detach', str(volume)], check=True)
