// Example OffscreenCanvas entry point. DOM input can be forwarded as messages.
import { start } from "./nanoui.js";
let runtime;
let receiveReplacement;

function requestReplacement() {
  return new Promise(resolve => {
    receiveReplacement = resolve;
    self.postMessage({ replaceCanvas: true });
  });
}

self.onmessage = async ({ data }) => {
  try {
    if (Object.hasOwn(data, "fallbackCanvas")) {
      const receive = receiveReplacement;
      receiveReplacement = undefined;
      receive?.(data.fallbackCanvas);
    } else if (data.canvas) {
      runtime = await start({
        canvas: data.canvas, url: data.url ?? "./counter.wasm",
        width: data.width, height: data.height, scale: data.scale ?? 1,
        cpuFallback: !!data.cpuFallback, replaceOffscreenCanvas: requestReplacement,
        onError: error => self.postMessage({ error: error.message }),
      });
      self.postMessage({ ready: true });
    } else if (data.info) {
      const value = runtime.exports.counter_value?.();
      self.postMessage({
        id: data.info, frames: runtime.exports.nanoui_web_frames(),
        callbacks: runtime.host.stats.callbacks, generation: runtime.gpu?.generation ?? 0,
        value: value === undefined ? undefined : Number(value),
      });
    }
    else if (data.resize) runtime.host.resize(...data.resize);
    else if (data.pointer) runtime.host.pointer(...data.pointer);
    else if (data.pinch) runtime.host.pinch(...data.pinch);
    else if (data.wheel) runtime.host.wheel(...data.wheel);
    else if (data.destroy) { runtime?.destroy(); receiveReplacement?.(null); self.close(); }
  } catch (error) { self.postMessage({ error: error.message }); }
};
