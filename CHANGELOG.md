# Changelog

## 1.0.2 - 2026-05-06

### Added

- Added a per-user LaunchAgent so the gateway stays available to Claude Desktop after the manager window is closed.
- Added automatic Claude-3p active config synchronization for gateway URL, auth scheme, local key, and visible model list.

### Changed

- Saving settings now starts/restarts the LaunchAgent-backed gateway automatically.
- The manager window auto-starts the gateway on launch when a DeepSeek API key is already configured.
- Documentation now treats the Claude Desktop config snippet as a fallback instead of the normal setup path.

## 1.0.1 - 2026-05-06

### Changed

- Reworked installation documentation around release DMG installation.
- Moved source-build instructions into the development path.
- Clarified why Claude Desktop still needs a gateway config snippet.

### Added

- DMG packaging script at `scripts/package_dmg.sh`.

## 1.0.0 - 2026-05-06

Initial release.

### Added

- macOS SwiftUI manager app named Claude DeepSeek Gateway.
- Native Swift local gateway binary bundled inside the app.
- First-run runtime installer for scripts, settings, and local gateway binary.
- Settings UI for DeepSeek API key, local gateway key, endpoint, advertised models, and model mapping.
- Claude Desktop compatibility endpoints:
  - `/health/liveliness`
  - `/v1/models`
  - `/v1/messages`
  - `/v1/messages/count_tokens`
- Model-name-only request rewriting:
  - `haiku` models route to `deepseek-v4-flash`
  - all other models route to `deepseek-v4-pro[1m]`
- Default official Claude model aliases:
  - `claude-opus-4-7`
  - `claude-sonnet-4-6`
  - `claude-haiku-4-5`
- Local doctor script for runtime verification.

### Removed

- Runtime dependency on LiteLLM.
- Runtime dependency on Python or uv.
- Non-official `[1m]` Claude model aliases from default advertised models.
