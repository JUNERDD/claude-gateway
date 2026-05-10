# Changelog

## 1.0.22 - 2026-05-10

### Added

- Added cache metrics to the overview page: Cache Reads, Cache Writes, and Cache Hit Rate tiles.
- Added DeepSeek cache field extraction (`prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`) with automatic hit rate formula selection for DeepSeek vs Anthropic providers.

### Changed

- Moved update available notification from sidebar footer to a prominent top banner for better discoverability.

### Fixed

- Fixed update checker not detecting new releases due to missing User-Agent header and pre-release-only tag edge case.

## 1.0.21 - 2026-05-10

### Added

- Automatically merge default sandbox network domains into Claude Code settings.json during sync, enabling subagent GitHub access without manual sandbox config.

## 1.0.20 - 2026-05-09

### Changed

- Increased log table row height (28→34) and cell spacing for better readability.
- Fixed CI release build to clean `.build` cache before packaging, preventing stale artifacts in release DMGs.

## 1.0.19 - 2026-05-09

### Added

- Added automatic update checker with manual check, auto-check toggle, and Updates settings pane.
- Added prefix-based model route matching for more flexible upstream routing.

### Changed

- Simplified dashboard metrics by removing trend comparisons and showing the active time range instead.
- Enhanced DeepSeek V4 Pro prompt with Orchestrator-Executor work mode guidance for Pro+Flash subagent workflows.
- Removed "Recent Requests" section from the overview page.

## 1.0.18 - 2026-05-09

### Changed

- Enhanced DeepSeek V4 Pro Claude Code prompt with detailed API limitation notices, available tool guidance, context accumulation tips, and effort-level awareness.

## 1.0.17 - 2026-05-09

### Added

- Added provider compatibility profiles, including a DeepSeek V4 Pro + Claude Code recipe with a provider-neutral append prompt path.
- Added Claude Code append prompt file generation and provider profile environment recommendations during sync.
- Added DeepSeek-aware onboarding defaults, local endpoint editing, model route confirmation, and a DeepSeek-only Vision configuration step.

### Changed

- Collapsed gateway settings and secrets into one `config.json` file with app import/export support.
- Rebranded public documentation and website surfaces to Claude Gateway.
- Reframed the public narrative around provider-neutral custom Anthropic-compatible upstreams, with provider-specific details moved to examples or historical release notes.
- Added provider compatibility diagnostics for thinking round-trip, Anthropic beta header, and tool block errors.

### Fixed

- Fixed onboarding quit behavior so Cmd+Q and menu-bar Quit dismiss the setup sheet instead of reopening it.
- Fixed Vision provider requests so the gateway uses the configured `visionProviderAPIKey` when no matching environment variable is set.
- Updated model route removal to act on the selected route instead of every route with the same alias.

## 1.0.16 - 2026-05-08

### Added

- Added menu bar controls for gateway status, start/stop actions, page shortcuts, Settings, and Quit.
- Added configurable system prompt prefix/suffix injection with token estimate coverage.

### Changed

- Kept the macOS app alive when the main window closes and reopened the existing window from the Dock or menu bar.
- Redesigned the public website header, route diagram, and setup sections.

### Fixed

- Escaped the setup terminal copy so the website passes strict linting.

## 1.0.15 - 2026-05-08

### Added

- Added the Vercel-ready public website for Claude Gateway.
- Added CI coverage for website linting and production builds.

### Changed

- Release packaging now creates and uploads a stable `ClaudeGateway-latest.dmg` asset.
- Dashboard metrics now reuse cached log records so rolling chart windows refresh even when the log tail is unchanged.

### Fixed

- Corrected website setup copy to use the default `127.0.0.1:4000` endpoint and macOS 14.4 minimum.

## 1.0.14 - 2026-05-07

### Added

- Added a first-run onboarding sheet for setting credentials, syncing Claude clients, and starting the gateway.
- Added Help menu access for reopening onboarding after the first run.
- Added a local connectivity probe response for minimal non-streaming `.` requests.
- Added Claude Desktop MCP config sync support for `claude_desktop_config.json`.
- Added MIT License for open-source distribution.
- Added public reporting guidance for rights, policy, platform, or compliance concerns.

### Changed

- Refined onboarding into a simple native macOS sheet without full-window visual effects.
- Expanded README installation, setup, troubleshooting, privacy, and development documentation.
- Included runtime repair status in the save/sync/start result.

### Fixed

- Prevented onboarding completion from triggering background dashboard layout churn through the main status banner.

## 1.0.13 - 2026-05-07

### Added

- Added a bundled `vision-provider` Claude MCP server and sync-time symlink installation into `~/.claude/mcp`.
- Added generic Vision Provider settings (`auto`, `dashscope`, `gemini`, or `openai-compatible`) for agent-initiated image inspection.
- Added local image attachment caching so Anthropic image blocks can be handed to Claude agents as `vision_describe` MCP calls.
- Added test coverage for image attachment bridging, MCP sync, runtime status parsing, vision provider settings, and structured vision logs.

### Changed

- Reworked the main window sidebar, toolbar, and configuration surface into a simpler monitor/settings split.
- Rebuilt the Settings window around native macOS tabs and grouped forms.
- Made configuration fields consistent: fixed-width inputs, left-aligned labels, and hover-only field help.
- Rewrote the README for app users instead of source-build developers.

### Fixed

- Added hover tooltips for icon-only toolbar and field-help controls.
- Prevented long configuration values from stretching Settings input fields.
- Kept image base64 out of token-count estimates and structured logs.

## 1.0.12 - 2026-05-07

### Fixed

- Allowed unauthenticated health checks on `/` and `/health/liveliness` while keeping gateway API endpoints protected by the local bearer key.

### Changed

- Reduced startup and log-view stalls by moving service checks and large log parsing off the main UI thread.
- Avoided repeated log parsing when the persistent log file has not changed.
- Improved large log-detail rendering and proxy log-write throughput.

## 1.0.10 - 2026-05-07

### Changed

- Centered empty states inside dashboard cards and request tables.
- Reduced empty-state title size so empty cards read as supporting states instead of page-level headings.

## 1.0.9 - 2026-05-07

### Added

- Added a native macOS split-view main window with real navigation for overview, requests, issues, logs, endpoint, model mapping, credentials, Claude integration, and runtime.
- Added dashboard metrics sourced from structured gateway logs, including request history tables and issue views.

### Changed

- Reworked configuration screens with full-width native controls, consistent card padding, and clearer section spacing.
- Improved log browsing with search and level filtering.
- Raised the minimum macOS version to 14.4 for newer SwiftUI table and inspector components.

## 1.0.8 - 2026-05-06

### Added

- Added structured proxy log events for DeepSeek requests, responses, model rewrites, upstream status, and request duration.
- Added expandable DeepSeek request parameter details in the app log view.

### Changed

- Replaced the raw log console with a scan-friendly event timeline.

## 1.0.7 - 2026-05-06

### Added

- Added automatic Claude Code `~/.claude/settings.json` synchronization for local gateway base URL, bearer token, and first-run default model.
- Extended doctor output with Claude Code gateway configuration checks.

### Changed

- Improved sync warnings so already-matched Claude Desktop configLibrary entries are not reported as missing.

## 1.0.6 - 2026-05-06

### Changed

- Rebuilt the DMG background as a static generated image around real Finder icons instead of drawing fake app/folder cards.
- Sized the DMG background to the Finder content area instead of the outer window bounds, preventing scrollbars and background cropping.
- Embedded the DMG background inside the app bundle so the installer no longer needs a visible top-level `.background` folder when Finder shows hidden files.

## 1.0.5 - 2026-05-06

### Changed

- Reworked the DMG as a styled drag-install window with fixed icon placement, background artwork, and install guidance.
- Changed DMG packaging to build into a temporary staging app instead of pre-installing into `~/Applications`, so testing the DMG follows the real production install path.

## 1.0.4 - 2026-05-06

### Added

- Added a visible Settings action to synchronize Claude Desktop configLibrary on demand.
- Added detailed sync diagnostics for updated, created, already-matched, backed-up, cache-refreshed, and warning states.
- Added automatic backup of changed Claude configLibrary JSON files before overwriting them.

## 1.0.3 - 2026-05-06

### Added

- Added configLibrary discovery that reads `_meta.json`, scans internal JSON config files, and ignores temporary/backup files.
- Added automatic creation of a default Claude-3p configLibrary entry when no usable entry exists.
- Added automatic refresh of Claude's gateway model cache when settings are saved or the gateway is started.
- Extended doctor output with configLibrary discovery and stale gateway model cache checks.

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

- macOS SwiftUI manager app named Claude Gateway.
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
