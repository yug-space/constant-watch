# Contributing

Constant Watch is an early desktop preview. Small fixes, reproducible issues, Windows compatibility reports and accessibility improvements are welcome.

## Development

Use Python 3.12. Install with `uv sync --python 3.12 --extra dev`, then run `uv run pytest -q`. The [README](README.md) covers native macOS and Windows builds. Windows packaging runs in GitHub Actions; macOS signing requires your own certificate or ad-hoc signing.

New installations start paused. Use a temporary `CONSTANT_WATCH_DATA` directory and synthetic test windows when testing capture. Do not commit journals, real captured text, personal screenshots, API keys or signing credentials. Keep capture opt-in, preserve exclusions and pause behavior, and retain original evidence alongside summaries.

Before opening a pull request, explain the user-visible change and relevant validation. For platform changes, distinguish unit tests from tests performed on the actual OS. Do not claim OS permission grants or model readiness unless they were checked.

## Website

`site/` contains the public static website source. Preview with `python -m http.server 8780 --directory site`. Release downloads point to GitHub Releases. Changes to this copy do not automatically deploy the hosted website.

## License

Contributions are licensed under the project's MIT license. Include notices for any third-party material you introduce.
