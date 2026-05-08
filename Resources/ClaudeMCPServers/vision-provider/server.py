#!/usr/bin/env python3
import json
import os
import sys
import urllib.error
import urllib.request


SERVER_NAME = "vision-provider"
SERVER_VERSION = "1.0.1"
TRANSPORT_MODE = "newline"


def main() -> int:
    while True:
        message = read_message()
        if message is None:
            return 0
        response = handle_message(message)
        if response is not None:
            write_message(response)


def read_message():
    global TRANSPORT_MODE

    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(b"{"):
            TRANSPORT_MODE = "newline"
            return json.loads(stripped.decode("utf-8"))
        if line in (b"\r\n", b"\n"):
            break
        name, _, value = line.decode("ascii", errors="replace").partition(":")
        headers[name.lower()] = value.strip()
        break

    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        name, _, value = line.decode("ascii", errors="replace").partition(":")
        headers[name.lower()] = value.strip()

    length = int(headers.get("content-length", "0"))
    if length <= 0:
        return None
    TRANSPORT_MODE = "headers"
    body = sys.stdin.buffer.read(length)
    return json.loads(body.decode("utf-8"))


def write_message(message: dict) -> None:
    body = json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if TRANSPORT_MODE == "headers":
        sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
        sys.stdout.buffer.write(body)
    else:
        sys.stdout.buffer.write(body)
        sys.stdout.buffer.write(b"\n")
    sys.stdout.buffer.flush()


def handle_message(message: dict):
    method = message.get("method")
    message_id = message.get("id")

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": message_id,
            "result": {
                "protocolVersion": message.get("params", {}).get("protocolVersion", "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        }
    if method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": message_id,
            "result": {"tools": [vision_tool_schema()]},
        }
    if method == "tools/call":
        return {
            "jsonrpc": "2.0",
            "id": message_id,
            "result": call_tool(message.get("params", {})),
        }

    if message_id is None:
        return None
    return {
        "jsonrpc": "2.0",
        "id": message_id,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    }


def vision_tool_schema() -> dict:
    return {
        "name": "vision_describe",
        "description": (
            "Describe, OCR, or extract content from a local image path through the local "
            "Claude Gateway vision provider. Use this before answering questions "
            "about gateway-saved image attachments."
        ),
        "inputSchema": {
            "type": "object",
            "additionalProperties": False,
            "properties": {
                "image_path": {
                    "type": "string",
                    "description": "Absolute local image path from the gateway attachment block.",
                },
                "prompt": {
                    "type": "string",
                    "description": "What to extract from the image. Ask to preserve visible text exactly when OCR matters.",
                },
                "provider": {
                    "type": "string",
                    "description": "Optional override: auto, dashscope, gemini, or openai-compatible.",
                },
                "model": {
                    "type": "string",
                    "description": "Optional vision model override.",
                },
                "mime_type": {
                    "type": "string",
                    "description": "Optional MIME type for raw base64 or extensionless files.",
                },
            },
            "required": ["image_path"],
        },
    }


def call_tool(params: dict) -> dict:
    if params.get("name") != "vision_describe":
        return tool_error(f"Unknown tool: {params.get('name')}")

    arguments = params.get("arguments") or {}
    image_path = str(arguments.get("image_path") or arguments.get("image") or "").strip()
    if not image_path:
        return tool_error("image_path is required.")

    body = {
        "image_path": image_path,
        "prompt": str(arguments.get("prompt") or default_prompt()),
    }
    for source, target in [
        ("provider", "provider"),
        ("model", "model"),
        ("mime_type", "mimeType"),
    ]:
        value = str(arguments.get(source) or "").strip()
        if value:
            body[target] = value

    try:
        result = post_gateway_json("/v1/vision/describe", body)
    except Exception as exc:
        return tool_error(str(exc))

    text = str(result.get("text") or "").strip()
    if not text:
        return tool_error(f"Gateway response did not include text: {json.dumps(result, ensure_ascii=False)}")

    provider = result.get("provider", "unknown")
    model = result.get("model", "unknown")
    return {
        "content": [
            {
                "type": "text",
                "text": f"Vision provider result ({provider}/{model}):\n\n{text}",
            }
        ],
        "isError": False,
    }


def post_gateway_json(path: str, payload: dict) -> dict:
    base_url = (
        os.getenv("CLAUDE_GATEWAY_URL")
        or os.getenv("VISION_GATEWAY_URL")
        or "http://127.0.0.1:4000"
    ).rstrip("/")
    key = os.getenv("LOCAL_GATEWAY_KEY") or os.getenv("ANTHROPIC_AUTH_TOKEN") or ""
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url}{path}",
        data=data,
        headers={
            "content-type": "application/json",
            **({"authorization": f"Bearer {key}"} if key else {}),
        },
        method="POST",
    )
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(request, timeout=180) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Gateway HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Gateway request failed: {exc.reason}") from exc


def tool_error(text: str) -> dict:
    return {"content": [{"type": "text", "text": text}], "isError": True}


def default_prompt() -> str:
    return (
        "Describe this image for a downstream agent. Include visible text exactly, "
        "important layout/state, diagrams, tables, charts, code, errors, and uncertainty."
    )


if __name__ == "__main__":
    raise SystemExit(main())
