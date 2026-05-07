# NAI Launcher - Krita Integration Design

**Date:** 2026-05-07
**Status:** Approved
**Approach:** Thin Plugin + Smart Launcher (Plan B)

## Overview

Enable bidirectional image workflow between NAI Launcher and Krita:

- **Krita → Launcher**: Inpaint (including Focused Inpaint), Img2Img with prompt input and streaming preview
- **Launcher → Krita**: Push generated/gallery images to Krita for editing
- **Architecture**: Launcher runs WebSocket server; Krita Python plugin connects as lightweight client

The plugin handles only canvas I/O and UI. All generation logic (crop/resize/composite for Focused Inpaint, API calls, streaming) stays in the Launcher.

## Section 1: WebSocket Communication Protocol

### Transport

- Launcher listens on `ws://127.0.0.1:{port}/krita` (loopback only)
- Single client model: one Krita connection at a time; new connection replaces old
- JSON text frames for all messages; binary frames reserved for future optimization
- Protocol versioned via `ping`/`pong` handshake

### Auto-Discovery

Launcher writes port file on server start:

```
%APPDATA%/nai-launcher/krita-bridge.json
```

```json
{
  "port": 52381,
  "pid": 12345,
  "version": 1,
  "started_at": "2026-05-07T10:30:00Z"
}
```

Krita plugin reads this file to discover the port. PID field enables stale-file detection (check if process is alive). File is deleted on Launcher clean exit.

### Message Types: Krita → Launcher

#### `inpaint`

```json
{
  "type": "inpaint",
  "id": "req-001",
  "image": "<base64 PNG, full canvas>",
  "mask": "<base64 PNG, white=repaint>",
  "selection_rect": {"x": 200, "y": 150, "w": 400, "h": 300},
  "prompt": "1girl, sitting",
  "negative_prompt": "bad anatomy",
  "strength": 0.7,
  "context_padding": 0.5,
  "focused_inpaint": true
}
```

- `selection_rect`: null when `focused_inpaint` is false
- `context_padding`: maps to `minimumContextMegaPixels` in `FocusedInpaintUtils`

#### `img2img`

```json
{
  "type": "img2img",
  "id": "req-002",
  "image": "<base64 PNG>",
  "prompt": "...",
  "negative_prompt": "...",
  "strength": 0.5
}
```

#### `get_params`

```json
{"type": "get_params", "id": "req-003"}
```

Requests current generation parameter snapshot from Launcher.

#### `cancel`

```json
{"type": "cancel", "id": "req-001"}
```

#### `ping`

```json
{"type": "ping", "version": 1}
```

### Message Types: Launcher → Krita

#### `result`

```json
{
  "type": "result",
  "id": "req-001",
  "image": "<base64 PNG, full composited image>"
}
```

For Focused Inpaint, the image is already composited back to full canvas size.

#### `progress`

```json
{
  "type": "progress",
  "id": "req-001",
  "step": 14,
  "total_steps": 28,
  "preview_image": "<base64 JPEG, current denoising preview>"
}
```

`preview_image` is included when available from NAI's MessagePack streaming API (not guaranteed on every step). For Focused Inpaint, previews are at cropped resolution — the plugin displays them stretched to full canvas as a rough indicator; only the final `result` is properly composited back to full canvas size.

#### `error`

```json
{
  "type": "error",
  "id": "req-001",
  "code": "auth_failed",
  "message": "Human-readable error description"
}
```

#### `params`

```json
{
  "type": "params",
  "id": "req-003",
  "model": "nai-diffusion-4-curated-preview",
  "sampler": "k_euler",
  "steps": 28,
  "cfg_scale": 5.0,
  "seed": 12345,
  "width": 832,
  "height": 1216
}
```

#### `push_image`

```json
{
  "type": "push_image",
  "image": "<base64 PNG>",
  "name": "gen_20260507_103005"
}
```

Launcher pushes an image to Krita (from generation page or gallery).

#### `pong`

```json
{"type": "pong", "version": 1}
```

#### `cancelled`

```json
{"type": "cancelled", "id": "req-001"}
```

## Section 2: Launcher Side Architecture

### New Module

```
lib/core/krita/
  krita_bridge_server.dart    -- dart:io HttpServer + WebSocket upgrade
  krita_bridge_service.dart   -- Orchestrates generation requests from Krita
  krita_bridge_models.dart    -- Message type definitions
```

### WebSocket Server (`krita_bridge_server.dart`)

Uses `dart:io` `HttpServer` + `WebSocketTransformer` (no new pub dependencies):

- `start({int preferredPort = 0})` — bind loopback, OS assigns port
- Single client model: `WebSocket? _client`
- `send(Map<String, dynamic>)` for JSON, `sendBinary(Uint8List)` reserved
- Exposes `Stream<Map<String, dynamic>> messages` for incoming messages

### Bridge Service (`krita_bridge_service.dart`)

Translates Krita messages into existing generation pipeline calls:

| Krita Request | Launcher Call Chain |
|---|---|
| `inpaint` (focused) | `FocusedInpaintUtils.prepareRequest()` → `NAIImageGenerationApiService` → `FocusedInpaintRequest.compositeGeneratedImage()` |
| `inpaint` (normal) | `InpaintMaskUtils` → `NAIImageGenerationApiService` |
| `img2img` | `NAIImageGenerationApiService` directly |
| `get_params` | Read `GenerationParamsNotifier.state` snapshot |
| Push image | Launcher UI triggers `server.send()` |

Streaming preview relay: listens to `Stream<ImageStreamChunk>` from API service, forwards each `previewImage` as a `progress` WebSocket message.

### Riverpod Integration

```dart
// lib/presentation/providers/krita/krita_bridge_notifier.dart
@Riverpod(keepAlive: true)
class KritaBridgeNotifier extends _$KritaBridgeNotifier {
  // States: disabled / starting / listening / connected / error
  // Manages KritaBridgeServer + KritaBridgeService lifecycle
}
```

- `keepAlive: true` — server must persist across navigation
- Initialized via `AppBootstrapEffects` pattern (if bridge is enabled in settings)
- Watches `GenerationParamsNotifier` for `get_params` responses

### UI Integration

- **Settings page**: Krita Integration toggle + port display + connection status indicator
- **Generation page toolbar**: "Send to Krita" button on generated images
- **Gallery page**: "Edit in Krita" context menu option

### Dependency Changes

None. `dart:io` provides `HttpServer` + `WebSocketTransformer` natively. Existing `web_socket_channel` package remains for ComfyUI client only.

## Section 3: Krita Plugin Architecture

### File Structure

```
nai_launcher_bridge/
  __init__.py                    -- Plugin entry: register Extension + DockWidgetFactory
  nai_launcher_bridge.desktop    -- Plugin manifest
  bridge_client.py               -- QWebSocket client connecting to Launcher
  bridge_dock.py                 -- DockWidget panel (prompt input, controls, buttons)
  canvas_utils.py                -- Canvas read/write helpers
```

Install location: `%APPDATA%/krita/pykrita/nai_launcher_bridge/`

### Zero-Dependency Strategy

Only uses Krita's bundled PyQt5 and Python stdlib:

| Capability | Implementation |
|---|---|
| WebSocket client | `PyQt5.QtWebSockets.QWebSocket` |
| JSON | `json` (stdlib) |
| Base64 | `base64` (stdlib) |
| Port file | `os` + `json` (stdlib) |
| PID detection | `os` / `ctypes` (Windows) |
| UI widgets | `PyQt5.QtWidgets` |

Copy the folder to pykrita directory and it works. No `pip install` required.

### WebSocket Client (`bridge_client.py`)

```python
class BridgeClient(QObject):
    connected = pyqtSignal()
    disconnected = pyqtSignal()
    message_received = pyqtSignal(dict)
```

- Reads `%APPDATA%/nai-launcher/krita-bridge.json` for port
- Validates PID is alive before connecting
- Auto-reconnect timer: 5-second interval on disconnect

### Dock Panel (`bridge_dock.py`)

```
+-- NAI Launcher Bridge ------------------+
| [Status LED] Connected                  |
|                                         |
| Prompt:                                 |
| [multi-line text input               ]  |
| Negative:                               |
| [multi-line text input               ]  |
|                                         |
| Strength:     [=====o=====] 0.70       |
| Context pad:  [=======o===] 0.50       |
| [x] Focused Inpaint                    |
|                                         |
| [ Inpaint ]  [ Img2Img ]               |
|                                         |
| ||||||||............ Step 14/28         |
+-----------------------------------------+
```

- Status LED: green (connected), yellow (reconnecting), red (not found)
- Prompt / Negative: `QPlainTextEdit`, sent with each request
- Strength: `QSlider` 0.0-1.0
- Context padding: `QSlider`, only enabled when Focused Inpaint is checked
- Focused Inpaint checkbox: when enabled, reads Krita rectangular selection as `focusAreaRect`
- Inpaint / Img2Img buttons: trigger generation
- Progress bar: visible during generation, shows step count

### Canvas Interaction (`canvas_utils.py`)

**Read canvas image:**

```python
def export_visible_as_png(doc) -> bytes:
    pixel_data = doc.pixelData(0, 0, doc.width(), doc.height())
    qimage = QImage(pixel_data, doc.width(), doc.height(), QImage.Format_RGBA8888)
    buffer = QBuffer()
    buffer.open(QBuffer.WriteOnly)
    qimage.save(buffer, "PNG")
    return bytes(buffer.data())
```

**Read selection (Focused Inpaint focus rect):**

```python
def get_selection_rect(doc) -> dict | None:
    sel = doc.selection()
    if sel is None:
        return None
    return {"x": sel.x(), "y": sel.y(), "w": sel.width(), "h": sel.height()}
```

**Read mask — dual mode:**

- **Selection mode**: Krita selection = mask (intuitive, uses native tools)
- **Mask layer mode**: layer named "Inpaint Mask" is read as mask (more precise, saveable)

User selects mask source via dropdown in Dock panel.

**Write generation result:**

```python
def insert_result_layer(doc, image_bytes: bytes, name: str):
    layer = doc.createNode(name, "paintLayer")
    # decode image_bytes → QImage → write pixel data to layer
    doc.rootNode().addChildNode(layer, None)
    doc.refreshProjection()
```

Each generation creates a new layer (e.g., `NAI Inpaint 10:30:05`) for easy comparison and undo.

### Streaming Preview Display

1. Generation starts → create temporary layer `"NAI Preview"`
2. Each `progress` message → decode Base64 → update `"NAI Preview"` layer → `doc.refreshProjection()`
3. `result` received → delete `"NAI Preview"` → create final result layer

Users see the real-time denoising process (blurry → sharp) on the Krita canvas. For Focused Inpaint, preview images are at cropped resolution and displayed stretched to canvas — only a rough visual indicator until the final composited result replaces it. Throttling (skip every N frames) can be added if `refreshProjection()` becomes a bottleneck.

## Section 4: End-to-End Workflows

### Workflow 1: Connection Establishment

1. Launcher starts with bridge enabled → `KritaBridgeServer.start(port: 0)` → writes port file
2. Krita plugin activated → reads port file → checks PID → `QWebSocket.open()`
3. Handshake: `ping` (version 1) → `pong` (version 1) → status LED green

Startup order does not matter. Krita retries every 5 seconds if Launcher is not yet running.

### Workflow 2: Focused Inpaint

```
Krita                                    Launcher
-----                                   --------
1. User paints mask (repaint area)
2. User draws rect selection (focus)
3. Checks Focused Inpaint, enters
   prompt, clicks [Inpaint]
4. Plugin reads canvas + mask +
   selection rect
5. Sends `inpaint` message ----------->  6. Decodes image + mask
                                          7. FocusedInpaintUtils.prepareRequest()
                                             → crop, resize to target dimensions
                                          8. NAIImageGenerationApiService
                                             .generateImageStream()
                                          9. Stream<ImageStreamChunk> starts
                                             |
10. Receives `progress` <-----------     10. For each step: send progress
    Updates "NAI Preview" layer              with preview_image
    Shows progress bar 14/28
    (repeats for each step)
                                         11. Stream ends, got finalImage
                                         12. compositeGeneratedImage()
                                             → paste result back to full canvas
13. Receives `result` <-------------     13. Sends composited full image
    Deletes "NAI Preview" layer
    Creates "NAI Inpaint 10:30:05"
    layer with final result
```

The plugin sends the full canvas and receives the full canvas. All crop/resize/composite logic is hidden inside the Launcher.

### Workflow 3: Normal Inpaint

Same as Workflow 2 but `focused_inpaint: false`, `selection_rect: null`. Launcher skips `FocusedInpaintUtils`, sends full image + mask directly to API.

### Workflow 4: Img2Img

1. User completes sketch on canvas
2. Enters prompt, adjusts strength, clicks [Img2Img]
3. Plugin reads canvas → sends `img2img` message
4. Launcher calls API directly (no mask/crop involved)
5. Streaming preview → progress messages → final result as new layer

### Workflow 5: Launcher Pushes Image to Krita

1. User clicks "Send to Krita" in Launcher (generation page or gallery)
2. Launcher sends `push_image` via WebSocket
3. Plugin creates new layer with the image
4. User can immediately paint mask on it and run Inpaint

This closes the loop: generate → send to Krita → edit → inpaint → edit → inpaint...

### Workflow 6: Cancel Generation

1. Krita sends `cancel` message
2. Launcher cancels API stream, sends `cancelled`
3. Krita deletes "NAI Preview" layer, resets progress bar

## Section 5: Error Handling and Edge Cases

### Connection Errors

| Scenario | Krita Behavior | Launcher Behavior |
|---|---|---|
| Launcher not running | Red LED, "NAI Launcher not detected", retry every 5s | — |
| Port file exists but PID dead | Ignore stale file, treat as not running | — |
| Connection drops mid-generation | Yellow LED, auto-reconnect; clean up preview layer, show "Connection interrupted" | Detect client disconnect, cancel in-flight API request, release stream resources |
| Launcher clean exit | Receives WebSocket close → enter reconnect | Close WebSocket → delete port file |
| Protocol version mismatch | `pong` version differs → show "Please update plugin", refuse requests | `ping` version unknown → return `pong` with `supported_versions` |

### Generation Error Codes

| NAI API Error | Code | User-Facing Message |
|---|---|---|
| 401 Unauthorized | `auth_failed` | Authentication failed, please re-login in Launcher |
| 402 / Insufficient Anlas | `insufficient_anlas` | Insufficient Anlas (remaining: N) |
| 429 Rate limit | `rate_limited` | Too many requests, please wait |
| 500 Server error | `server_error` | NovelAI server error |
| Network timeout | `timeout` | Network timeout |
| Stream interrupted | `stream_interrupted` | Generation interrupted |
| Another request in progress | `busy` | Previous request still processing |

Krita displays errors as red text in Dock panel bottom (auto-dismiss after 3 seconds).

### Canvas Validation (Krita-side, before sending)

| Check | Failure Behavior |
|---|---|
| No document open | Buttons greyed out, tooltip "Please open a document first" |
| Canvas < 64x64 | Reject, show "Canvas too small" |
| Inpaint but no mask | Show "Please mark the repaint area first" |
| Focused Inpaint but no rect selection | Show "Please use Rectangle Select tool to mark focus area" |
| Not connected | Buttons greyed out |

All validation is local — no WebSocket round-trip for invalid requests.

### Concurrency

Single-request model: one generation at a time.

- Krita: button becomes [Cancel] during generation, restored on result/error/cancelled
- Launcher: returns `error` code `busy` if a request arrives while another is in progress

No request queuing — not worth the complexity for an interactive editing workflow.

### Large Canvas

| Canvas Size | Handling |
|---|---|
| <= 4096x4096 | Send as-is |
| > 4096x4096 | Plugin downscales to fit 4096 before sending; result is upscaled back to original size when writing layer |

Base64 PNG of 4096x4096 is ~20-40 MB, acceptable for localhost WebSocket.

### Safety During Generation

User can continue editing in Krita while generation is in progress:

- Preview layer is separate from user's working layers
- Final result writes to a new layer, never overwrites existing content
- `doc.refreshProjection()` is thread-safe (Krita Python plugin + QWebSocket signals both run on main thread)

### State Recovery

| Scenario | Recovery |
|---|---|
| Krita restart | Plugin re-reads port file → auto-reconnect; Dock input fields not persisted (V1) |
| Launcher restart | New port written to file; Krita's next reconnect attempt picks up new port |
| Launcher crashes mid-generation | Krita detects disconnect → clean up preview layer → yellow LED → auto-reconnect |
| Krita crashes mid-generation | Launcher detects client disconnect → cancel API request → release resources |

## License and Compliance

### Krita GPL v3

The Krita plugin must be GPL v3 if distributed. The Launcher is a separate program communicating over WebSocket — not subject to GPL copyleft. This is the same pattern as krita-ai-diffusion (GPL) + ComfyUI (separate process).

### NovelAI ToS

Section 5.3.2-5.3.4 prohibit third-party remote access and circumventing technical measures. The Krita integration:

- Runs on the same local machine (loopback only)
- Uses the user's own persistent API token (already stored in Launcher)
- Does not expose the API to third parties or over the network
- Same compliance posture as the Launcher itself

## Out of Scope (V1)

- ControlNet / Vibe Transfer from Krita (requires additional protocol messages)
- Multiple concurrent Krita connections
- Dock panel input persistence across Krita sessions
- Binary WebSocket frames for image transfer (optimization if Base64 proves too slow)
- Non-Windows platforms (Krita plugin is Python so it's portable, but testing is Windows-only for V1)
