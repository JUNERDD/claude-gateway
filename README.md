# Claude DeepSeek Gateway

Claude DeepSeek Gateway is a macOS local gateway app. It lets Claude Desktop and Claude Code send requests to DeepSeek through a local Anthropic-compatible endpoint.

Think of it as:

```text
Claude Desktop / Claude Code
        |
        |  http://127.0.0.1:4000  +  local bearer key
        v
Claude DeepSeek Gateway
        |
        |  DeepSeek API key
        v
DeepSeek Anthropic-compatible API
```

Install the app, paste your DeepSeek API key, click `Save, Sync, and Start`, and Claude can use the local gateway models without hand-editing client config files.

## Who This Is For

- You want to use DeepSeek from Claude Desktop or Claude Code.
- You do not want to maintain LiteLLM, uv, or a separate proxy process yourself.
- You want a native window for gateway status, recent requests, issues, logs, and runtime checks.
- Optional: you want Claude agents to inspect image attachments through DashScope, Gemini, or another OpenAI-compatible vision provider.

This is probably not the right tool if:

- You only want to call the DeepSeek API directly, without Claude Desktop or Claude Code.
- You expect requests to go to Anthropic's hosted Claude models. The `claude-*` names exposed by this app are local aliases; text requests are forwarded to DeepSeek.

## What You Get

- A native macOS manager for starting, stopping, and monitoring the local gateway.
- Automatic Claude Desktop and Claude Code configuration sync.
- Default Claude-visible model names:
  - `claude-opus-4-7`
  - `claude-sonnet-4-6`
  - `claude-haiku-4-5`
- Default routing:
  - Model names containing `haiku` route to `deepseek-v4-flash`.
  - All other model names route to `deepseek-v4-pro[1m]`.
- A bundled `vision-provider` MCP server so Claude agents can inspect locally saved image attachments through your configured vision provider.
- Local logs, request history, issue views, and runtime diagnostics.
- A per-user macOS LaunchAgent so the gateway keeps serving Claude after the manager window is closed.

## Before You Install

Required:

- macOS 14.4 or later.
- A DeepSeek API key.
- Claude Desktop, Claude Code, or both.

Optional:

- A vision provider API key if you want Claude agents to inspect image attachments.
- Xcode Command Line Tools if you want to build from source or run tests.

Not required:

- An Anthropic API key.
- LiteLLM.
- uv.
- A separate Python gateway service.

## 5-Minute Setup

### 1. Install The App

1. Download the latest `ClaudeDeepSeekGateway-*.dmg` from GitHub Releases.
2. Open the DMG.
3. Drag `Claude DeepSeek Gateway.app` into `Applications`.
4. Open the app.

If macOS blocks the first launch because the app is distributed outside the App Store, right-click the app and choose `Open`, or allow it from `System Settings -> Privacy & Security`.

### 2. Add Your DeepSeek Key

1. Open `Claude DeepSeek Gateway.app`.
2. Go to `Settings -> Credentials`.
3. Paste your DeepSeek API key into `DeepSeek API Key`.
4. Keep the generated `Local Gateway Key`; if it is empty, click `Generate`.

`DeepSeek API Key` is used for upstream DeepSeek requests. `Local Gateway Key` is only used between your local Claude clients and the local gateway. Claude clients do not receive your DeepSeek API key.

### 3. Keep The Default Connection

Go to `Settings -> Connection`. New users should keep:

```text
Listen Address: 127.0.0.1
Port: 4000
DeepSeek Endpoint: https://api.deepseek.com/anthropic
```

Do not change `Listen Address` to `0.0.0.0` unless you understand the security impact. The default `127.0.0.1` only accepts local machine traffic.

### 4. Save, Sync, And Start

Click `Save, Sync, and Start`.

That one action:

- Saves gateway settings and secrets.
- Installs or repairs the local runtime files.
- Starts or refreshes the LaunchAgent.
- Syncs Claude Desktop gateway and MCP configuration.
- Syncs Claude Code `~/.claude/settings.json` and user MCP configuration.
- Refreshes stale gateway model discovery cache files.

### 5. Restart Claude Clients

- Claude Desktop: fully quit and reopen the app.
- Claude Code: start a new Claude Code session.

After that, Claude should be able to use the synced local models. The default model names are `claude-opus-4-7`, `claude-sonnet-4-6`, and `claude-haiku-4-5`.

## How To Tell It Worked

In Claude DeepSeek Gateway:

- `Overview` shows the gateway as running.
- `Requests` starts showing requests from Claude.
- `Issues` has no new auth, port, or upstream errors.

In Claude:

- The synced local model names are available.
- After sending a normal text message, the gateway app shows the request in `Requests` or `Logs`.

You can also run the local doctor:

```bash
~/bin/claude-deepseek-gateway-doctor.sh
```

The doctor checks runtime files, local auth, the health endpoint, model discovery, token counting, Claude Desktop sync, Claude Code settings, and the bundled MCP symlink.

## App Tour

Main window:

| Area | Purpose |
| --- | --- |
| `Overview` | Gateway health, endpoint, request rate, and recent requests |
| `Requests` | Recent traffic forwarded through the gateway |
| `Issues` | Configuration problems, warnings, and failed requests |
| `Logs` | Structured runtime events |
| `Configuration` | Quick access to the full Settings window |

Settings:

| Tab | What New Users Should Know |
| --- | --- |
| `Connection` | Local listen address, port, and DeepSeek Anthropic endpoint |
| `Credentials` | DeepSeek API key, optional vision provider key, and local gateway key |
| `Models` | Model names Claude sees and the DeepSeek models they route to |
| `Vision` | Optional image inspection provider, model, and base URL |
| `Claude` | Claude client config snippet and the latest sync result |
| `Runtime` | Local runtime file status and repair action |

## Model Names And Routing

Claude clients see Claude-style model aliases such as:

```text
claude-opus-4-7
claude-sonnet-4-6
claude-haiku-4-5
```

These names are aliases for Claude client compatibility. When the gateway receives a request, it rewrites only the top-level `model` field before forwarding the request to DeepSeek.

| Claude requested model | Default DeepSeek target |
| --- | --- |
| Any model name containing `haiku` | `deepseek-v4-flash` |
| All other model names | `deepseek-v4-pro[1m]` |

You can change this in `Settings -> Models`:

- `Advertised Models`: model names Claude can see.
- `Haiku Target`: DeepSeek model used when the requested name contains `haiku`.
- `Default Target`: DeepSeek model used for all other requested names.

Important: the `claude-*` names do not mean requests are sent to Anthropic's hosted Claude models.

## Vision And Image Attachments

Vision support is optional. Text-only requests work without it.

How it works:

1. Claude receives an image attachment.
2. The gateway saves the image to a local cache path.
3. Claude receives a local attachment path it can inspect.
4. When Claude needs to understand the image, it calls the bundled `vision-provider` MCP tool.
5. `vision-provider` calls your configured vision provider through the local gateway.

Images are not automatically sent to a vision model with every text request. They are sent only when Claude calls the `vision-provider` tool.

### DashScope Example

```text
Vision Provider: dashscope
Vision Model: qwen3-vl-flash
Vision Base URL: https://dashscope.aliyuncs.com/compatible-mode/v1
Vision Provider API Key: your DashScope API key
```

Use the DashScope endpoint that matches the region of your API key.

### Gemini Example

```text
Vision Provider: gemini
Vision Model: gemini-2.5-flash-lite
Vision Base URL: https://generativelanguage.googleapis.com
Vision Provider API Key: your Gemini API key
```

### OpenAI-Compatible Example

```text
Vision Provider: openai-compatible
Vision Model: gpt-4o-mini
Vision Base URL: https://api.openai.com/v1
Vision Provider API Key: your provider API key
```

If you are not using DashScope, choose `gemini` or `openai-compatible` explicitly instead of relying on `auto`.

## Troubleshooting

### Claude Cannot See The Models

Check these in order:

1. Click `Save, Sync, and Start` in the gateway app.
2. Fully quit and reopen Claude Desktop, or start a new Claude Code session.
3. Run the doctor:

```bash
~/bin/claude-deepseek-gateway-doctor.sh
```

4. Open `Settings -> Claude` and check `Last Sync` for warnings.

### Claude Cannot Connect

Check whether the gateway is listening:

```bash
lsof -iTCP:4000 -sTCP:LISTEN -n -P
```

If nothing is listening, go back to the app and click `Save, Sync, and Start`. If another process is using the port, change `Settings -> Connection -> Port`, save and sync again, then restart Claude clients.

### Claude Reports 401 Or Auth Failure

This usually means Claude's local bearer token does not match the gateway `Local Gateway Key`.

Fix:

1. Open `Settings -> Credentials`.
2. Make sure `Local Gateway Key` is not empty.
3. Click `Save, Sync, and Start`.
4. Restart Claude clients.

### DeepSeek Returns Errors Or No Response

Check:

- `DeepSeek API Key` is valid.
- `DeepSeek Endpoint` is still `https://api.deepseek.com/anthropic`, or matches your provider requirements.
- Your DeepSeek account quota, rate limits, region, and target model names are valid.
- `Issues` and `Logs` show the upstream HTTP status and error details.

### Image Inspection Does Not Work

Check:

- `Settings -> Vision` uses the correct provider.
- `Vision Provider API Key` is configured when required.
- `Vision Model` and `Vision Base URL` match the provider.
- Claude clients were restarted after `Save, Sync, and Start`.
- Doctor output shows the `vision-provider MCP Server` installed.

### The Gateway Still Runs After Closing The Window

That is expected. The app installs a per-user LaunchAgent so Claude can keep using the local gateway after the manager window is closed.

Use the app's stop action if you want to stop the gateway, or remove the LaunchAgent during uninstall.

## Privacy And Security

- The gateway binds to `127.0.0.1` by default, so only the local machine can connect.
- DeepSeek and vision provider API keys are stored locally in `~/.config/claude-deepseek-gateway/secrets.env`.
- Claude clients receive the `Local Gateway Key`, not your DeepSeek API key.
- Text requests are forwarded to DeepSeek.
- Image attachments are cached locally under `~/Library/Caches/ClaudeDeepSeekGateway/attachments`.
- Images are sent to your configured vision provider only when Claude calls `vision-provider`.
- Structured logs avoid storing large image base64 payloads.

On shared machines, note that secrets are currently stored in local files rather than the macOS Keychain.

## Files Managed By The App

Gateway configuration:

```text
~/.config/claude-deepseek-gateway/proxy_settings.json
~/.config/claude-deepseek-gateway/secrets.env
```

Runtime files:

```text
~/bin/claude-deepseek-gateway-start.sh
~/bin/claude-deepseek-gateway-proxy.sh
~/bin/claude-deepseek-gateway-doctor.sh
~/.config/claude-deepseek-gateway/deepseek_anthropic_alias_proxy
```

Logs and cache:

```text
~/Library/Application Support/ClaudeDeepSeekGateway/proxy.log
~/Library/Caches/ClaudeDeepSeekGateway/attachments
```

LaunchAgent:

```text
~/Library/LaunchAgents/local.zen.ClaudeDeepSeekGateway.proxy.plist
```

Claude integration:

```text
~/Library/Application Support/Claude-3p/configLibrary/*.json
~/Library/Application Support/Claude*/claude_desktop_config.json
~/.claude/settings.json
~/.claude.json
~/.claude/mcp/vision-provider
```

When sync needs to overwrite an existing JSON file, the app creates a `.bak-*` backup first.

## Updating

1. Download the newest DMG.
2. Replace the old app in `Applications`.
3. Open the new app.
4. Click `Save, Sync, and Start` once.

Your API keys and settings are stored in the local configuration directory, so replacing the app normally keeps them.

## Uninstall

1. Quit the app.
2. Remove `Claude DeepSeek Gateway.app` from `Applications`.
3. Remove the LaunchAgent if it still exists:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.zen.ClaudeDeepSeekGateway.proxy.plist
rm -f ~/Library/LaunchAgents/local.zen.ClaudeDeepSeekGateway.proxy.plist
```

4. Optional: remove local configuration, runtime files, logs, and cache:

```bash
rm -rf ~/.config/claude-deepseek-gateway
rm -rf ~/Library/Application\ Support/ClaudeDeepSeekGateway
rm -rf ~/Library/Caches/ClaudeDeepSeekGateway
rm -f ~/bin/claude-deepseek-gateway-start.sh
rm -f ~/bin/claude-deepseek-gateway-proxy.sh
rm -f ~/bin/claude-deepseek-gateway-doctor.sh
```

After uninstalling, Claude Desktop or Claude Code may still contain gateway configuration. If Claude later reports that the local gateway does not exist, restore the `.bak-*` files created by the app or remove the gateway fields and `vision-provider` MCP entry from the relevant Claude config files.

## Development From Source

Common commands:

```bash
swift test
swift build -c release
```

Build and install to `~/Applications/Claude DeepSeek Gateway.app`:

```bash
./build-and-install-app.sh
```

Package a DMG:

```bash
scripts/package_dmg.sh
```

The packaged artifact is written to:

```text
dist/ClaudeDeepSeekGateway-<version>.dmg
```

Source layout:

```text
Sources/ClaudeDeepSeekGateway       macOS SwiftUI manager app
Sources/DeepSeekAliasProxy          Local Anthropic-compatible proxy process
Sources/DeepSeekAliasProxyCore      Image bridge and vision provider core logic
Resources/Runtime                   Runtime scripts and default config installed into ~/bin
Resources/ClaudeMCPServers          Bundled Claude MCP server
Tests/ClaudeDeepSeekGatewayTests    Unit tests
scripts/package_dmg.sh              DMG packaging script
```

## Glossary

| Term | Meaning |
| --- | --- |
| DeepSeek API Key | Secret used to call the upstream DeepSeek API |
| Local Gateway Key | Bearer token used by Claude clients to call the local gateway |
| Advertised Models | Model names Claude clients can see |
| Target Model | DeepSeek model name the gateway actually forwards to |
| LaunchAgent | macOS per-user background service used to keep the gateway running |
| MCP | Mechanism Claude uses to call local tools |
| `vision-provider` | Bundled MCP server for inspecting locally saved image attachments |

## License

Claude DeepSeek Gateway is open source under the [MIT License](LICENSE).

If you believe this project violates any rights, policy, platform terms, or applicable rules, contact `junerdduser@gmail.com`. I will review the report and address valid concerns.
