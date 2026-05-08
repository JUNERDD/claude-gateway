# Claude Gateway

Claude Gateway is a macOS local gateway app. It lets Claude Desktop and Claude Code send requests to custom Anthropic-compatible upstream providers through a local endpoint you control.

Think of it as:

```text
Claude Desktop / Claude Code
        |
        |  http://127.0.0.1:4000  +  local bearer key
        v
Claude Gateway
        |
        |  upstream provider API key
        v
Anthropic-compatible upstream API
```

Install the app, paste your upstream API key, choose the upstream endpoint and model mapping, click `Save, Sync, and Start`, and Claude can use the local gateway models without hand-editing client config files.

## Who This Is For

- You want Claude Desktop or Claude Code to use a provider-neutral, Anthropic-compatible upstream.
- You do not want to maintain LiteLLM, uv, or a separate proxy process yourself.
- You want a native window for gateway status, recent requests, issues, logs, and runtime checks.
- Optional: you want Claude agents to inspect image attachments through DashScope, Gemini, or another OpenAI-compatible vision provider.

This is probably not the right tool if:

- You only want to call an upstream provider API directly, without Claude Desktop or Claude Code.
- You expect requests to go to Anthropic's hosted Claude models. The `claude-*` names exposed by this app are local aliases; text requests are forwarded to your configured upstream provider.

## What You Get

- A native macOS manager for starting, stopping, and monitoring the local gateway.
- Automatic Claude Desktop and Claude Code configuration sync.
- Default Claude-visible model names:
  - `claude-opus-4-7`
  - `claude-sonnet-4-6`
  - `claude-haiku-4-5`
- Configurable routing from Claude-visible model aliases to upstream model names.
- A bundled `vision-provider` MCP server so Claude agents can inspect locally saved image attachments through your configured vision provider.
- Local logs, request history, issue views, and runtime diagnostics.
- A per-user macOS LaunchAgent so the gateway keeps serving Claude after the manager window is closed.

## Before You Install

Required:

- macOS 14.4 or later.
- An API key for an Anthropic-compatible upstream provider.
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

1. Download the latest `ClaudeGateway-*.dmg` from GitHub Releases.
2. Open the DMG.
3. Drag `Claude Gateway.app` into `Applications`.
4. Open the app.

If macOS blocks the first launch because the app is distributed outside the App Store, right-click the app and choose `Open`, or allow it from `System Settings -> Privacy & Security`.

### 2. Add Your Upstream Key

1. Open `Claude Gateway.app`.
2. Go to `Settings -> Credentials`.
3. Paste your provider API key into the upstream API key field.
4. Keep the generated `Local Gateway Key`; if it is empty, click `Generate`.

The upstream API key is used only for requests to your configured provider. `Local Gateway Key` is only used between your local Claude clients and the local gateway. Claude clients do not receive your upstream API key.

### 3. Configure The Connection

Go to `Settings -> Connection`. New users should keep the local listen settings:

```text
Listen Address: 127.0.0.1
Port: 4000
Upstream Endpoint: your provider's Anthropic-compatible endpoint
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

In Claude Gateway:

- `Overview` shows the gateway as running.
- `Requests` starts showing requests from Claude.
- `Issues` has no new auth, port, or upstream errors.

In Claude:

- The synced local model names are available.
- After sending a normal text message, the gateway app shows the request in `Requests` or `Logs`.

You can also run the local doctor:

```bash
~/bin/claude-gateway-doctor.sh
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
| `Connection` | Local listen address, port, and upstream Anthropic-compatible endpoint |
| `Credentials` | Upstream API key, optional vision provider key, and local gateway key |
| `Models` | Model names Claude sees and the upstream models they route to |
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

These names are aliases for Claude client compatibility. When the gateway receives a request, it rewrites only the top-level `model` field before forwarding the request to your configured upstream provider.

| Claude requested model | Upstream target |
| --- | --- |
| Any model name containing `haiku` | Your configured lightweight/fast target model |
| All other model names | Your configured default target model |

You can change this in `Settings -> Models`:

- `Model Routes`: explicit mappings from a Claude-visible alias to a provider and upstream model.
- `Default Route`: fallback provider and upstream model for unmatched aliases.

Important: the `claude-*` names do not mean requests are sent to Anthropic's hosted Claude models.

## Provider Recipes

Use any upstream that exposes an Anthropic-compatible messages API. Provider endpoint paths, model names, quotas, and region requirements vary, so use the values from your provider account.

### DeepSeek Example

```text
Upstream Endpoint: https://api.deepseek.com/anthropic
Upstream API Key: your DeepSeek API key
Route: claude-sonnet-4-6 -> deepseek-v4-pro[1m]
Route: claude-haiku-4-5 -> deepseek-v4-flash
Default Route: deepseek-v4-pro[1m]
```

### Custom Provider Example

```text
Upstream Endpoint: https://provider.example.com/anthropic
Upstream API Key: your provider API key
Route: claude-sonnet-4-6 -> provider-sonnet-model
Route: claude-haiku-4-5 -> provider-fast-model
Default Route: provider-sonnet-model
Default Target: provider-default-model
```

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
~/bin/claude-gateway-doctor.sh
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

### Upstream Provider Returns Errors Or No Response

Check:

- The upstream API key is valid.
- `Upstream Endpoint` matches your provider requirements.
- Your provider account quota, rate limits, region, and target model names are valid.
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
- Upstream and vision provider API keys are stored locally in `~/.config/claude-gateway/secrets.json`.
- Claude clients receive the `Local Gateway Key`, not your upstream API key.
- Text requests are forwarded to your configured upstream provider.
- Image attachments are cached locally under `~/Library/Caches/ClaudeGateway/attachments`.
- Images are sent to your configured vision provider only when Claude calls `vision-provider`.
- Structured logs avoid storing large image base64 payloads.

On shared machines, note that secrets are currently stored in local files rather than the macOS Keychain.

## Files Managed By The App

Gateway configuration:

```text
~/.config/claude-gateway/proxy_settings.json
~/.config/claude-gateway/secrets.json
```

Runtime files:

```text
~/bin/claude-gateway-start.sh
~/bin/claude-gateway-proxy.sh
~/bin/claude-gateway-doctor.sh
~/.config/claude-gateway/anthropic_alias_proxy
```

Logs and cache:

```text
~/Library/Application Support/ClaudeGateway/proxy.log
~/Library/Caches/ClaudeGateway/attachments
```

LaunchAgent:

```text
~/Library/LaunchAgents/local.zen.ClaudeGateway.proxy.plist
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

Your API keys and settings are stored in the local configuration directory. Check the release notes for the expected configuration path before replacing an older app.

## Uninstall

1. Quit the app.
2. Remove `Claude Gateway.app` from `Applications`.
3. Remove the LaunchAgent if it still exists:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/local.zen.ClaudeGateway.proxy.plist
rm -f ~/Library/LaunchAgents/local.zen.ClaudeGateway.proxy.plist
```

4. Optional: remove local configuration, runtime files, logs, and cache:

```bash
rm -rf ~/.config/claude-gateway
rm -rf ~/Library/Application\ Support/ClaudeGateway
rm -rf ~/Library/Caches/ClaudeGateway
rm -f ~/bin/claude-gateway-start.sh
rm -f ~/bin/claude-gateway-proxy.sh
rm -f ~/bin/claude-gateway-doctor.sh
```

After uninstalling, Claude Desktop or Claude Code may still contain gateway configuration. If Claude later reports that the local gateway does not exist, restore the `.bak-*` files created by the app or remove the gateway fields and `vision-provider` MCP entry from the relevant Claude config files.

## Development From Source

Common commands:

```bash
swift test
swift build -c release
```

Build and install to `~/Applications/Claude Gateway.app`:

```bash
./build-and-install-app.sh
```

Package a DMG:

```bash
scripts/package_dmg.sh
```

The packaged artifact is written to:

```text
dist/ClaudeGateway-<version>.dmg
```

Source layout:

```text
Sources/                           macOS app, local proxy, and shared gateway logic
Resources/Runtime                  Runtime scripts and default config installed into ~/bin
Resources/ClaudeMCPServers         Bundled Claude MCP server
Tests/                             Unit tests
scripts/package_dmg.sh             DMG packaging script
```

## Glossary

| Term | Meaning |
| --- | --- |
| Upstream API Key | Secret used to call the configured upstream provider API |
| Local Gateway Key | Bearer token used by Claude clients to call the local gateway |
| Advertised Models | Model names Claude clients can see |
| Target Model | Upstream model name the gateway actually forwards to |
| LaunchAgent | macOS per-user background service used to keep the gateway running |
| MCP | Mechanism Claude uses to call local tools |
| `vision-provider` | Bundled MCP server for inspecting locally saved image attachments |

## License

Claude Gateway is open source under the [MIT License](LICENSE).

If you believe this project violates any rights, policy, platform terms, or applicable rules, contact `junerdduser@gmail.com`. I will review the report and address valid concerns.
