import json
import os
from pathlib import Path
from pydantic import BaseModel, Field
from .platform_support import default_data_dir


class Settings(BaseModel):
    interval_seconds: int = Field(default=10, ge=3, le=300)
    paused: bool = True
    onboarding_complete: bool = False
    purpose: str = "recall"
    model: str = "qwen3.5:0.8b"
    excluded_apps: list[str] = Field(default_factory=lambda: [
        "local.constantwatch.app",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "windows:constant-watch.exe", "windows:constant-watch-service.exe",
        "windows:1password.exe", "windows:bitwarden.exe", "windows:keepass.exe",
        "windows:keepassxc.exe", "windows:lastpass.exe", "windows:credentialuibroker.exe",
        "com.apple.Passwords", "com.apple.keychainaccess", "com.lastpass.LastPass",
    ])
    retention_days: int = Field(default=30, ge=1, le=365)


def data_dir() -> Path:
    path = Path(os.environ.get("CONSTANT_WATCH_DATA", str(default_data_dir()))).expanduser().resolve()
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.chmod(0o700)
    return path


def load_settings(root: Path) -> Settings:
    path = root / "settings.json"
    return Settings.model_validate_json(path.read_text(encoding="utf-8")) if path.exists() else Settings()


def save_settings(root: Path, settings: Settings) -> None:
    temp = root / "settings.tmp"
    temp.write_text(json.dumps(settings.model_dump(), indent=2), encoding="utf-8")
    temp.chmod(0o600)
    temp.replace(root / "settings.json")
