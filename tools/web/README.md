# WebGPU target

The browser renderer and minimal canvas host build for single-threaded
`wasm32-wasi` with Zig 0.17. They began as a port of the earlier 0.11
WebGPU experiment to the current renderer.

The renderer consumes the current **192-byte** `gpu.Instance`, including
subtree matrices, and respects `Texture.encoding` (`auto`, `display_sdr`,
`surface_linear`). It supports every current kind, pictures and glyphs,
rounded clipping, gradient stops, layers, holes, motion, glass (including
progressive sidebar blur), BGRA/half-float/external textures and LUTs.

## Build and verify

```sh
npm ci --prefix tools/web
PLAYWRIGHT_SKIP_BROWSER_GC=1 tools/web/node_modules/.bin/playwright install --only-shell chromium
zig build web-check -j1
node tools/web/check.mjs
zig build web-parity -j1
node tools/web/parity.mjs
zig build web-demo -j1
node tools/web/browser.mjs
node tools/web/serve.mjs
```

Open the printed loopback URL with `/counter.html` or `/gallery.html`.
The default shell uses Canvas 2D when it cannot acquire a WebGPU device.
The GPU parity checks still require WebGPU and fail on shader diagnostics or
validation errors. Linux CI uses pinned Playwright with SwiftShader.

`NANOUI_GPU=hardware node tools/web/parity.mjs` selects ANGLE Metal on this
Mac and adds H.264/HEVC decode tests. `NANOUI_ENGINE=webkit` selects WebKit.
The tests compare against CPU pixels at scales 1/2 and in BGRA/RGBA. They
cover subtree matrices, explicit color encodings, same-frame compute,
readback across memory growth, stale devices and incremental atlas uploads.

## App integration

`nanoui.web.mount(view, options)` creates one canvas surface;
`nanoui.web.run()` unwinds main to the JavaScript event loop. Register fonts
first. The app's state must outlive the surface. JavaScript drives only
requested frames; an idle surface registers no animation callback.
The canvas keeps a GPU backing texture for ordinary axis-aligned scenes.
It repaints changed tiles and leaves the previous image on screen when an
update produces identical pixels. Backdrop effects, transformed layers,
and application-owned passes use a full redraw.

The build helper `@import("nanoui").web.install(b, exe, dependency.path("."))`
installs a wasm32-wasi command, browser modules, and a default
`web/<executable>.html` entry point. Serve that page over localhost or HTTPS.
The standard shell needs no app-authored HTML or JavaScript. Its module
must be single-threaded and link libc. In JavaScript:

```js
import {start} from './nanoui.js';
const runtime = await start({canvas, url: './my-app.wasm', device});
```

Omit `device` to have nanoui acquire and recover one. Injecting a device
leaves its ownership/recovery to the app; call `await runtime.setDevice(next)`
after replacement. `runtime.destroy()` frees renderer resources and only
an owned device. OffscreenCanvas/Workers use the same API (`worker.js`).

`ui.webgpuDevice()` and `ui.webgpuDeviceGeneration()` identify the shared
GPUDevice. `runtime.gpu.objects.put/get/drop` bridges app objects as handles.
Pass `true` as the second argument to `put` for textures that will keep the
same contents for their entire lifetime. Decoded `VideoFrame` objects are
already treated as immutable.
`Texture.web_texture` borrows a GPUTexture; `web_external` borrows a VideoFrame
or video element. Keep them alive until the frame is submitted. Ordinary
`VideoFrame` sources import directly. Padded frames are cropped, and video
elements use the normalized copy path to bridge decoder backends. Native two-plane formats are not web sources.

`Surface.before_encode` receives the GPUCommandEncoder's handle as a
pointer-sized integer; app JS resolves it through the object table.
`Surface.after_frame` retains its native meaning. `nanoui.web.Renderer` and
`Target` support offscreen rendering and asynchronous premultiplied BGRA
readback; keep output memory and callback context alive until completion.

`Surface.recordFrames` enables CPU/GPU timing; `gpu.stats` exposes recent
samples. The timestamp readback pool is bounded and never blocks a frame.

The host handles pointer and wheel input, pinch gestures, resize/DPR and
device recovery. The canvas delivers pinch scale and midpoint through
`Context.input.zoom` and `mouse`, and two-finger translation through `pan`.
A pinch cancels any active touch pointer drag rather than releasing it.
Workers can forward a pinch through `runtime.host.pinch(x, y, scale, dx, dy)`.
On a focusable DOM canvas, pass a `keyboard(event)` predicate to `start` to
forward selected key events. The Gallery demo uses this for its Zig command
palette. The predicate leaves browser-owned shortcuts and Tab available.
The default shell also enables `semantics: true`. That option projects labels,
headings, text fields, buttons and choices from Zig's accessibility tree into
the DOM. A browser text field hosts IME composition at the Zig caret; commit
inserts one UTF-8 operation into the focused Zig field. Copy, cut and paste
use browser clipboard events in that field, with password selections omitted.
A commit or paste is limited to 64 KiB. Browser preedit is displayed by the DOM
field and is not sent to Zig until commit.

`runtime.host.pickFile({ accept, maxBytes, signal })` must be invoked in a
browser user gesture. It reads one selected file as `{ name, type, bytes }`,
resolves to null on picker cancellation, and defaults to a 16 MiB limit.
`accept` is a picker hint. Validate content in the caller. The host does not
expose unrestricted paths or request filesystem permission at startup.

`start({ ..., cpuFallback: true })` uses the existing Zig CPU rasterizer if
adapter or device acquisition fails. `cpu: true` forces it on startup.
The Canvas 2D path caps the presentation buffer at 4096 × 4096 pixels by
reducing backing scale. GPU textures, custom GPU encoding and GPU timing
require WebGPU. The fallback does not replace a mounted WebGPU context if it
loses its device. Native dialogs, multi-window, a full App/Window platform,
and comprehensive screen-reader acceptance remain separate work.

## Workspace collection picker

Build the same fixture for native and WASI against the sibling workspace's
actual Zig search library:

```sh
zig build picker-check web-demo -Dworkspace-search=../zig-workspace -j1
node tools/web/picker_browser.mjs
NANOUI_PICKER_ENGINE=firefox node tools/web/picker_browser.mjs
node tools/web/compat.mjs
```

Open the native fixture with
`zig build run-collection-picker -Dworkspace-search=../zig-workspace`.
Serve the browser artifacts with `node tools/web/serve.mjs` and open
`/collection-picker.html` at the printed URL.

The native check uses the offscreen Tester. The browser check uses Chromium's
composition protocol and checks the semantic results and keyboard focus on
WebGPU and forced Canvas 2D. The Firefox check runs the same fixture with
injected composition events on Canvas 2D. They use disposable clipboard events
and file fixtures.

See [MEASUREMENTS.md](MEASUREMENTS.md) for verification scope.
