# Claude DeepSeek Gateway

Claude DeepSeek Gateway is a macOS app that lets Claude Desktop and Claude Code talk to DeepSeek through a local Anthropic-compatible gateway.

Install the app, paste your DeepSeek API key, save once, and Claude can use the local gateway models without manual config editing.

## What You Get

- A native macOS manager for starting, stopping, and monitoring the local gateway.
- Automatic Claude Desktop and Claude Code configuration sync.
- Claude-visible model names:
  - `claude-opus-4-7`
  - `claude-sonnet-4-6`
  - `claude-haiku-4-5`
- DeepSeek routing behind the scenes:
  - Haiku requests route to `deepseek-v4-flash`
  - Other requests route to `deepseek-v4-pro[1m]`
- A bundled `vision-provider` MCP server so Claude agents can inspect saved image attachments through your configured vision provider.
- Local logs, request history, issue views, and runtime diagnostics.
- A per-user macOS LaunchAgent so the gateway keeps serving Claude after the manager window is closed.

## Requirements

- macOS 14.4 or later
- A DeepSeek API key
- Optional: a vision provider API key if you want Claude agents to inspect image attachments

You do not need LiteLLM, uv, or a separate gateway service.

## Install

1. Download the latest `ClaudeDeepSeekGateway-*.dmg` from GitHub Releases.
2. Open the DMG.
3. Drag `Claude DeepSeek Gateway.app` into Applications.
4. Open the app.

macOS may ask you to confirm opening the app because it is distributed outside the App Store.

## First Setup

1. Open `Claude DeepSeek Gateway.app`.
2. Open Settings.
3. Paste your DeepSeek API key.
4. Keep the local address as `127.0.0.1` and the port as `4000` unless you know you need a different port.
5. Click `Save, Sync, and Start`.
6. Restart Claude Desktop if it was already open. Start a new Claude Code session if you use Claude Code.

Saving settings installs or updates the local runtime, starts the LaunchAgent, refreshes Claude model discovery, syncs Claude Desktop, and updates Claude Code settings.

## Vision Setup

Vision is optional. The gateway does not automatically send every chat message to a vision model. When Claude receives an image attachment, the gateway saves the image locally and gives Claude an MCP tool path it can inspect when needed.

To enable image inspection:

1. Open Settings.
2. Choose a Vision Provider.
3. Paste the provider API key in Credentials.
4. Set the vision model and base URL.
5. Click `Save, Sync, and Start`.

Common DashScope/Qwen values:

```text
Vision Provider: dashscope
Vision Model: qwen3-vl-flash
Vision Base URL: https://dashscope.aliyuncs.com/compatible-mode/v1
```

Use the DashScope endpoint that matches the region of your API key.

## Daily Use

The main window shows:

- `Overview`: gateway health, endpoint, request rate, and recent requests.
- `Requests`: recent traffic forwarded through the gateway.
- `Issues`: warnings, failed requests, and configuration problems.
- `Logs`: structured runtime events.
- `Configuration`: quick access to the full Settings window.

Most users only need Settings when changing API keys, models, provider URLs, or Claude sync state.

## Settings

Important settings:

- `DeepSeek API Key`: used by the gateway when forwarding text requests to DeepSeek.
- `Local Gateway Key`: a local bearer token used between Claude and the gateway.
- `DeepSeek Endpoint`: defaults to `https://api.deepseek.com/anthropic`.
- `Advertised Models`: the model names Claude sees.
- `Haiku Target` and `Default Target`: the DeepSeek model names used after routing.
- `Vision Provider`, `Vision Model`, and `Vision Base URL`: optional image inspection provider settings.

The local gateway key is separate from your provider API keys. Claude clients only receive the local gateway key.

## Privacy And Security

- The gateway binds to `127.0.0.1` by default.
- DeepSeek and vision provider API keys are stored locally in `~/.config/claude-deepseek-gateway/secrets.env`.
- Request forwarding rewrites the top-level `model` field for DeepSeek routing.
- Image attachments are cached locally under `~/Library/Caches/ClaudeDeepSeekGateway/attachments`.
- Structured logs avoid storing large image base64 payloads.

## Troubleshooting

If Claude cannot see models or cannot connect:

1. Open the app and check that the gateway status is running.
2. Click `Save, Sync, and Start` again from Settings.
3. Fully quit and reopen Claude Desktop.
4. Make sure no other process is using the selected port.
5. Check the `Issues` and `Logs` tabs.
6. Run the local doctor:

```bash
~/bin/claude-deepseek-gateway-doctor.sh
```

The doctor checks runtime files, local auth, the health endpoint, model discovery, token counting, Claude Desktop sync, Claude Code settings, and the bundled MCP symlink.

## Files The App Manages

Configuration:

```text
~/.config/claude-deepseek-gateway/proxy_settings.json
~/.config/claude-deepseek-gateway/secrets.env
```

Runtime:

```text
~/bin/claude-deepseek-gateway-start.sh
~/bin/claude-deepseek-gateway-proxy.sh
~/bin/claude-deepseek-gateway-doctor.sh
~/.config/claude-deepseek-gateway/deepseek_anthropic_alias_proxy
```

Logs:

```text
~/Library/Application Support/ClaudeDeepSeekGateway/proxy.log
```

LaunchAgent:

```text
~/Library/LaunchAgents/local.zen.ClaudeDeepSeekGateway.proxy.plist
```

Claude MCP symlink:

```text
~/.claude/mcp/vision-provider
```

## Updating

Download the newest DMG, replace the app in Applications, open it, and click `Save, Sync, and Start` once. Your existing keys and settings stay in the local configuration files.

## Uninstall

1. Quit the app.
2. Remove `Claude DeepSeek Gateway.app` from Applications.
3. Remove the LaunchAgent if it is still installed:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.zen.ClaudeDeepSeekGateway.proxy.plist
rm -f ~/Library/LaunchAgents/local.zen.ClaudeDeepSeekGateway.proxy.plist
```

4. Optional: remove local configuration and logs:

```bash
rm -rf ~/.config/claude-deepseek-gateway
rm -rf ~/Library/Application\ Support/ClaudeDeepSeekGateway
rm -rf ~/Library/Caches/ClaudeDeepSeekGateway
rm -f ~/bin/claude-deepseek-gateway-start.sh
rm -f ~/bin/claude-deepseek-gateway-proxy.sh
rm -f ~/bin/claude-deepseek-gateway-doctor.sh
```
