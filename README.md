# Constant Watch

**Open-source screen memory for macOS and Windows.** Accessibility + OCR → local Qwen3.5 0.8B → continuous daily Markdown → read-only MCP.

The Mac app uses SwiftUI and a menu-bar companion. The Windows app uses a native WebView2 window with Microsoft UI Automation and Windows OCR. Both share the local Python journal and model backend.

[Download installers](https://github.com/yug-space/constant-watch/releases) · [Website](https://constant-watch.yuggupta.chatgpt.site) · [MIT license](LICENSE) · [Contributing](CONTRIBUTING.md)

**Preview requirements:** Apple Silicon / macOS 14+, or Windows 11 Intel/AMD x64. Ollama and the model are separate downloads. The Mac package is signed but not notarized; the Windows installer is unsigned. The transparent desktop orb intro is currently Mac-only.

The default view is **Daily flow**: one chronological journal across apps, with adjacent captures from the same app and window grouped into sessions. A white interface, guided onboarding, and a local landing page introduce the product without sign-up or authentication.

## First run

The welcome opens with a transparent, full-desktop orb-to-logo reveal, followed by a short animated greeting and an optional first name saved on this Mac. **Music on/off** controls a bundled ambient soundtrack; it stops when you leave onboarding. **Replay welcome** reopens the greeting. macOS Reduce Motion disables staged reveals.

1. Choose a use case: recover context, review the day, or connect an assistant.
2. Enable Accessibility and Screen Recording separately. Each permission has a live status and a link to its macOS settings page.
3. Check the local Qwen model, or download it through the app when Ollama is running.
4. Open the practice note. Leave it visible for about 15 seconds, then return to see the actual captured result. Search **Atlas** to find it again.

New installations start paused. **Explore first** opens existing journals with capture paused; **Open my daily flow** completes setup and starts capture. The guide can be reopened from the sidebar or menu bar. Existing saved pause preferences are preserved on upgrade.

Practical uses: recover a detail seen in another app, return to an interrupted project, review the day's research and decisions, export a daily work journal, and supply a connected assistant with searchable context. This is text recall, not an activity-duration tracker or an automatic agent acting on your behalf.

The foreground app is sampled every 10 seconds by default. This is periodic text capture, not a video recorder: brief changes between samples can be missed. Only the foreground app's window is captured, not every display or background app.

## Install the packaged app

Open `dist/Constant-Watch-0.1.0-macOS-arm64.dmg`, drag **Constant Watch** into **Applications**, eject the disk image, and launch the installed app. The package includes its Python interpreter and dependencies; no developer tools or source checkout are required. Apple Silicon and macOS 14+ are required. Ollama and the Qwen model are separate first-run downloads. The DMG does not enable login startup automatically.

The package is Developer ID signed when that identity is available. Check its release report for notarization status; signing alone is not notarization. Upgrading from a build signed with a different certificate may require granting the new app's macOS permissions again.

Build and verify a package:

```sh
bash scripts/package-app.sh
.venv/bin/python scripts/smoke-package.py "$HOME/Library/Caches/Constant Watch/build/Constant Watch.app"
```

Set `CODE_SIGN_IDENTITY` to select a certificate explicitly. Set `CW_NOTARY_PROFILE` to an existing notarytool Keychain profile to submit, staple, and validate notarization during packaging. Outputs include a compressed DMG and SHA-256 checksum. The smoke test uses a temporary journal, starts paused, checks packaged web assets, and exercises the actual bundled stdio MCP server.

## Run from source

Requirements: Apple Silicon, macOS 14+, Xcode Command Line Tools (`xcode-select --install`), [uv](https://docs.astral.sh/uv/), and running [Ollama](https://ollama.com/).

```sh
bash scripts/setup.sh
bash scripts/install-app.sh
```

Open `~/Applications/Constant Watch.app`. The installer starts it and configures login startup. If access is missing, use **Request access**, then enable **Constant Watch** in **System Settings → Privacy & Security → Accessibility** and **Screen Recording**. The native permission card links directly to both settings pages. The native app itself requests and uses both permissions; Python and the command-line helper do not need access for the installed app. Quit/reopen if macOS requests it. If an older development build shows enabled but is not recognized, remove its stale entry and add the installed app again using **Show installed app**. The permission check does not capture text.

```sh
.venv/bin/constant-watch doctor
.venv/bin/constant-watch permissions
```

The native app owns the local Python service. Closing the window leaves the menu-bar app and capture running; **Quit Constant Watch** stops both. Use the menu-bar icon to reopen the journal, pause/resume, show notes in Finder, or copy MCP configuration.

To update the installed app after source changes, quit it, then rerun `bash scripts/install-app.sh`. To refresh only its backend runtime and login startup:

```sh
.venv/bin/python scripts/service.py install
```

This installs a separate runtime under `~/Library/Application Support/Constant Watch/runtime` so launch does not depend on access to the protected Documents directory. Stop a manually running server before installing. A per-data-directory lock prevents two capture loops running together. The native app starts the service as its child and performs all macOS permission checks, Accessibility reads, and OCR capture in its own process. The backend sends jobs over a local bridge authenticated with a fresh per-launch token; it never launches a capture helper in this mode.

To remove login startup (retains journals, app, and runtime), quit Constant Watch first, then:

```sh
.venv/bin/python scripts/service.py uninstall
```

Logs: `~/Library/Logs/Constant Watch/`. **Pause capture** persists across restarts; existing queued summaries can finish while capture is paused. Ollama must also be running for summaries; source capture continues and queued summaries retry when it returns.

The **landing page** is at **http://127.0.0.1:8765** while the app is running. Its interactive example journal uses clearly labeled fictional content and never loads your private history. Native app links use the `constantwatch://` URL scheme. The optional browser journal is at **http://127.0.0.1:8765/journal**. For backend-only development, run `.venv/bin/constant-watch serve` instead of the native app.

## Your data

```text
~/Library/Application Support/Constant Watch/
  settings.json
  memory.sqlite3
  days/
    2026-09-28.md
  apps/
    com.apple.Safari-<stable hash>/2026-09-28.md
    com.microsoft.VSCode-<stable hash>/2026-09-28.md
```

App folders use bundle IDs and a stable hash to avoid unsafe paths and naming collisions. Every observation includes its timestamp, window title, generated summary, separate accessibility/OCR source text, and capture warnings. SQLite is the source of truth; Markdown is rewritten atomically and can be regenerated with `constant-watch rebuild`. Do not edit generated Markdown expecting those changes to persist.

`days/YYYY-MM-DD.md` is the continuously updated cross-app journal. It includes an overview, chronological sessions, summaries, and expandable source evidence. Returning to an unchanged app is preserved as a transition. Consecutive unchanged samples extend the last-seen timestamp; a different app/window or a gap over five minutes starts another session. Time ranges describe observations, not continuous active time. Local session summaries consolidate multiple captured moments and refresh at most once a minute while the session changes; pending updates are indicated. App-specific journals still retain every original observation.

Search covers captured text, titles, and summaries. Select an app and date to download its daily Markdown. Settings control interval (3–300 seconds), exclusions by bundle ID, and retention (1–365 days, default 30). Reducing retention deletes old database records and Markdown exports. Retention is logical deletion, not forensic secure erasure; backups may retain copies.

For command-line operation, override the storage root with `CONSTANT_WATCH_DATA` and the helper executable with `CONSTANT_WATCH_HELPER`. The installed native app uses its own in-process capture core. All clients reading the same journal must use the same data root.

## MCP

Use **Copy MCP configuration** in the native app's settings or menu bar, or `mcp-config.example.json` in this checkout, for a stdio MCP client. Replace the example command with your installed executable path. Generic configuration:

```json
{
  "mcpServers": {
    "constant-watch": {
      "command": "/absolute/path/to/constant-watch/.venv/bin/constant-watch",
      "args": ["mcp"]
    }
  }
}
```

For the installed service, the command can instead be `/Users/YOUR_USER/Library/Application Support/Constant Watch/runtime/venv/bin/constant-watch`. The MCP process reads the shared journal independently of the capture daemon. It does not start capture or expose capture controls.

Tools:

| Tool | Purpose |
| --- | --- |
| `ask_memory` | Questions answered with exact captured excerpts, observation citations, app/time/document/source metadata; optional app/date/topic filters |
| `list_topics` | Suggested groups across apps based on explicit project names and document titles |
| `read_topic` | Chronological, paginated captures for an exact topic key |
| `read_observation` | Verify a citation against original Accessibility/OCR text |
| `read_day_flow` | One complete chronological daily Markdown journal across apps |
| `day_sessions` | Paginated grouped sessions with summaries and source evidence |
| `list_apps` | Applications, bundle IDs, counts, available dates |
| `search_screen_memory` | Full-text AND search; optional app and date filters |
| `recent_activity` | Latest observations; pagination with `before_id` |
| `read_app_day` | Complete daily Markdown for one application |

Resources: `watch://day/{day}`, `watch://apps`, `watch://app/{app_id}/{day}`, and `watch://observation/{observation_id}`. Dates use local `YYYY-MM-DD`. Search/recent tools return at most 50 observations and `day_sessions` at most 50 sessions per call. Complete journals can be large; prefer pagination for high-volume days.

### Ask your day and follow a topic

The native workspace opens with **Ask your day**. Ask about a project or detail, use **Today only** or an app filter, then open **View captured text** to verify the source. **Topics** follows matching names across applications in chronological order. The daily journal and per-app Markdown remain available; daily Markdown also lists suggested threads spanning multiple apps.

Recall currently retrieves and quotes passages rather than generating a new factual answer. It handles question filler, a small set of common aliases, dates, and word prefixes; it is not semantic search and may miss paraphrases. Every meaningful query term must match. Qwen3.5 continues to generate background observation/session summaries using cleaner text and a prompt focused on concrete facts. Older summaries keep their attribution.

Raw Accessibility/OCR text is preserved after existing redaction. A separate searchable representation removes exact duplicate lines and common interface labels without collapsing signs or changed numbers. Existing captures are migrated automatically. Current-document URLs come only from Accessibility document/web-area metadata; unavailable historical links are never guessed. Secret query parameters and URL credentials are removed. **Open source** opens HTTP(S) links; **Reveal document** shows a captured local document in Finder. `constantwatch://observation/123` opens a cited capture in the native app.

Topic labels are deterministic suggestions based on visible names/titles, not confirmed project membership. A screenshot or visible message does not prove an action was completed. Retention removes the associated evidence and search entries; opening an expired citation reports it as unavailable.

Captured content is marked as **untrusted reference data**, not instructions. Any assistant connected to this MCP can read your journal; its own data handling policies apply. MCP registration is deliberately provided as a file so you can choose which assistant receives access.

## Architecture

- **Shared Swift capture core:** AppKit identifies the foreground app; AXUIElement reads its focused window, with depth, node, and time bounds. ScreenCaptureKit captures that app's foreground window in memory, and Apple Vision recognizes text. A focus change during capture discards the sample. No screenshots are saved. The installed app calls this core directly; a separate helper exists only for command-line operation.
- **Native SwiftUI app:** NavigationSplitView app sidebar, real application icons, searchable journal, source disclosure, native date picker and save panel, settings sheet, and MenuBarExtra controls. It starts/stops the Python backend as a child process. No WebView or Electron runtime.
- **Python daemon:** redacts common token/password patterns, merges duplicate AX/OCR lines, detects unchanged text per app and day, stores observations, and exports Markdown. Capture and summary workers run separately so model latency doesn't block sampling. Native bridge requests have bounded queues and deadlines; cancelled or expired results are discarded. Standalone helper processes have a timeout and are terminated on shutdown.
- **Ollama:** Qwen3.5 0.8B is a **0.8B-parameter** model (approximately 1 GB download). Although the model supports images, this app supplies only Accessibility and OCR text. Thinking is disabled for short background summaries. Output is limited to 160 generated tokens per observation, with a 4K context and bounded input. Raw source text is retained even when no model is available. Existing summaries retain their original model attribution when you change the active model; new summaries use the selected model.
- **FastAPI dashboard:** loopback-only, same-origin controls, host validation, no remote fonts or scripts. Captured strings are inserted as text, never executable HTML.
- **Official MCP Python SDK:** pinned to the supported v1 line (`mcp<2`), serving stdio tools/resources. `uv.lock` records the development environment.

## Capture limits and privacy

Password managers are excluded by default. Exclusions are checked before accessibility traversal or image capture. Locked or inactive desktop sessions and windows with detected secure text fields are skipped. Secret-pattern redaction happens before persistence and inference.

These are best-effort protections: some apps expose little accessibility text, may not label sensitive fields correctly, and OCR may still read sensitive information. Incognito/private windows are not automatically detected. Exclude apps whose contents you do not want stored. The app does not send screen content to cloud services; only the initial model/dependency downloads require the network. Local files are permission-restricted, but not separately encrypted. The loopback API is available to other processes on this user account and is not intended for shared-machine or remote deployment.

A 0.8B model can hallucinate or produce weak summaries, especially on dense screens or malicious instructions in captured text. The UI exposes source text for checking. Large windows and accessibility trees are bounded/truncated to limit load. Capture interval is measured after capture work, so slow OCR can lengthen the effective interval. The dashboard avoids re-ingesting its own journal when its title is visible in the foreground window.

## Development and verification

```sh
uv sync --python 3.12 --extra dev
bash scripts/build-app.sh
.venv/bin/pytest -q
```

Tests exercise real SQLite/Markdown persistence, full-text index updates, retention, redaction, chronological session grouping, app-return transitions, consolidated session summaries, pause races, onboarding persistence, separate permission requests, native bridge routing and authentication, cancellation/timeout cleanup, local API access controls, single-daemon locking, and an actual stdio MCP client/server exchange. Screen capture needs a logged-in macOS desktop and its permissions, so tests mock the OS boundary. Run the native app for live validation; command-line `doctor` checks the launching terminal's permission context, which may differ from the native app.

Builds use the sole available Apple Development certificate when one exists, keeping the app identity stable across rebuilds. Set `CODE_SIGN_IDENTITY` to select a certificate explicitly; set it to `-` for ad-hoc signing. With no unique development certificate, builds fall back to ad-hoc signing. The release packaging script bundles the runtime. Developer ID signing and Apple notarization require your own credentials; the development installer does not perform notarization.

Changing signing identity or rebuilding an ad-hoc-signed binary can cause macOS to require a new permission grant. The native onboarding reports the actual permission status and cannot grant it for you. Build staging happens outside Documents to avoid cloud-file-provider metadata interfering with signing.

Implementation references: [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [Ollama chat API](https://docs.ollama.com/api/chat), [Qwen model specification](https://ollama.com/library/qwen3.5:0.8b), [MCP Python SDK v1](https://py.sdk.modelcontextprotocol.io/v1/).

### Day and week reviews

The native app opens to Review: choose a day or week, inspect source-linked highlights, and prepare an editable Markdown status draft. Counts describe captured context, not work duration. Draft outcomes/priorities need your confirmation; drafts are only copied on request and edits are temporary. MCP `read_review(start, end)` and `GET /api/review?start=YYYY-MM-DD&end=YYYY-MM-DD` support inclusive ranges up to 31 days. Counts represent sampled context, not continuous activity duration.

### Replay and public website

Use **Replay orb intro** in the sidebar, application menu, or menu bar to restart the transparent desktop introduction. The shortcut is **⌘⇧R**; `constantwatch://replay` opens the same flow from the website. Replaying preserves capture settings, permissions, journal data, and the preferred name.

The public website source lives in `site/`, with the hosted version at https://constant-watch.yuggupta.chatgpt.site. It contains fictional demonstration text and download links, never the local journal API or captured history. Production hosting configuration is managed separately.

`bash scripts/package-app.sh` builds the app and the branded Retina drag-install DMG. `bash scripts/package-dmg.sh` repackages an already signed app from the build cache. The icon and native wordmark share `native/BrandMark.swift`, matching the seven-sphere reveal. Installer Finder settings deliberately use supported 128-point icons and 16-point labels.

## Windows desktop preview

The Windows edition uses a native WebView2 desktop window, Microsoft UI Automation and Windows OCR, with the same Python journal, Qwen model, and read-only MCP server. Windows 11 x64 is the initial supported target. The Mac SwiftUI app remains available separately.

Run `Constant-Watch-0.1.0-Windows-x64-Setup.exe`. It installs for the current user without administrator access and adds a Start menu shortcut. Python and service dependencies are bundled. Windows 11 normally includes the required Microsoft Edge WebView2 Runtime. Install and open Ollama through the setup guide, then choose **Download local model**. Choose **Start my journal** explicitly to enable capture. Closing the desktop window stops its capture service; minimize it to keep watching.

Windows data lives under `%LOCALAPPDATA%\Constant Watch`. Exclusions use lowercase executable IDs such as `windows:chrome.exe` and `windows:bitwarden.exe`; the app list shows the IDs that were actually captured. Locked desktops, excluded applications, and windows with visible password controls are skipped. UI Automation privacy inspection has a node/time limit; oversized or changing trees are skipped instead of bypassing inspection. OCR operates on the visible foreground-window rectangle in memory and may include overlapping visible windows. Elevated/protected apps may be unreadable. Windows language settings must have an OCR-supported language installed; otherwise accessibility capture continues with an OCR warning.

Copy the MCP configuration from Capture settings or `%LOCALAPPDATA%\Constant Watch\mcp-config.json`. The Windows command is the installed `constant-watch-service.exe` with argument `mcp`. No Mac executable or source checkout is needed. The desktop UI currently provides daily flow, app filtering, source text, search, Markdown export, settings and model setup; the Mac's transparent desktop reveal and native day/week review interface are not ported. Review and recall remain available through the shared API and MCP.

Build on Windows with Python 3.12 and Inno Setup 6:

```powershell
python -m pip install -e ".[dev]" -r windows/requirements.txt
python -m pytest -q
python -m PyInstaller --noconfirm windows/constant-watch.spec
python scripts/third-party-notices.py "dist/Constant Watch/THIRD-PARTY-NOTICES.txt"
python windows/smoke.py
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" windows/installer.iss
```

`.github/workflows/windows.yml` runs these checks on Windows. The Windows preview installer is unsigned; Windows SmartScreen may warn. Uninstalling the program preserves the journal in LocalAppData.

## License and project

Released under the [MIT license](LICENSE). Third-party dependencies retain their own licenses; packaged applications include dependency notices. [Manas Vardhan](https://manasvardhan.com/) is CEO of Constant Watch.
