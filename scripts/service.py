"""Install native app runtime and login startup. Uninstall removes login startup only."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("action", choices=["install", "uninstall"])
args = parser.parse_args()
label = "local.constantwatch.service"
plist = Path.home() / "Library/LaunchAgents" / f"{label}.plist"
domain = f"gui/{os.getuid()}"
if args.action == "uninstall":
    subprocess.run(["launchctl", "bootout", f"{domain}/{label}"], check=False)
    plist.unlink(missing_ok=True)
else:
    root = Path(__file__).resolve().parents[1]
    app = Path.home() / "Applications/Constant Watch.app"
    if not app.exists():
        raise SystemExit("Build and install the native app first: bash scripts/install-app.sh")
    subprocess.run(["launchctl", "bootout", f"{domain}/{label}"], capture_output=True)
    # A LaunchAgent cannot launch code inside macOS-protected Documents folders.
    # Install an independent runtime in Application Support, like a normal local app.
    install = Path.home() / "Library/Application Support/Constant Watch/runtime"
    install.mkdir(parents=True, exist_ok=True, mode=0o700)
    uv = shutil.which("uv")
    if not uv:
        raise SystemExit("Install uv first, then rerun this command.")
    subprocess.run([uv, "venv", "--allow-existing", "--python", "3.12", str(install / "venv")], check=True)
    subprocess.run([uv, "pip", "install", "--reinstall-package", "constant-watch", "--python", str(install / "venv/bin/python"), str(root)], check=True)
    helper = install / "Constant Watch Capture.app"
    shutil.copytree(root / "build/Constant Watch Capture.app", helper, dirs_exist_ok=True)
    logs = Path.home() / "Library/Logs/Constant Watch"
    logs.mkdir(parents=True, exist_ok=True, mode=0o700)
    plist.parent.mkdir(parents=True, exist_ok=True)
    value = {"Label": label, "ProgramArguments": [str(app / "Contents/MacOS/ConstantWatch")],
             "WorkingDirectory": str(install), "RunAtLoad": True,
             "ThrottleInterval": 30, "StandardOutPath": str(logs / "service.log"),
             "StandardErrorPath": str(logs / "service.error.log")}
    with plist.open("wb") as f:
        plistlib.dump(value, f)
    subprocess.run(["launchctl", "bootout", f"{domain}/{label}"], capture_output=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(plist)], check=True)
    print(f"Constant Watch is running and starts at login: {app}")
