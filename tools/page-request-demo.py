#!/usr/bin/env python3
"""Exercise the real hidden webview against a temporary loopback server."""
import argparse
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading
import time

HTML = '''<!doctype html><html><meta charset="utf-8"><title>First request</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f4f5f7;color:#17202b;font:16px -apple-system,BlinkMacSystemFont,sans-serif;padding:48px}
small{font-size:12px;letter-spacing:2px;color:#657284}h1{font-size:42px;letter-spacing:-1.6px;margin:14px 0}p{color:#657284;line-height:1.6}main{max-width:800px;margin:auto}.pill{display:inline-block;background:#e0f3e7;color:#17643c;padding:8px 12px;border-radius:30px;font-size:13px}
.card{background:white;border:1px solid #e0e5eb;border-radius:20px;padding:26px;margin-top:24px}.row{display:flex;gap:18px}.metric{flex:1}strong{display:block;font-size:34px;margin:8px 0}.label{font-size:13px;color:#657284}.step{display:flex;align-items:center;gap:16px;padding:14px 0;border-bottom:1px solid #edf0f3}.step:last-child{border:0}.dot{width:28px;height:28px;border-radius:50%;background:#e0f3e7;color:#17643c;text-align:center;line-height:28px}code{font:13px ui-monospace,monospace;color:#37475b}.note{font-size:12px;margin-top:20px}
</style><main><small>NANOUI / PAGE REQUEST MVP</small><h1>The first request is ready.</h1><p>The host prepared its credentials before navigating. This document was served by the loopback server after checking the actual request header.</p><span class="pill">Authenticated document loaded</span><section class="card row"><div class="metric"><div class="label">Document requests</div><strong>1</strong><code>No preliminary load</code></div><div class="metric"><div class="label">Authorization received</div><strong>Yes</strong><code>Test credential only</code></div><div class="metric"><div class="label">First request after</div><strong>ELAPSED ms</strong><code>800 ms preparation timer</code></div></section><section class="card"><div class="step"><span class="dot">1</span><span>Create a deferred webview</span></div><div class="step"><span class="dot">2</span><span>Prepare credentials on the host</span></div><div class="step"><span class="dot">3</span><span>Load a GET request with its headers</span></div></section><p class="note">Real WKWebView capture · Hidden window · No screen or system input used</p></main><script>
addEventListener('load',async()=>{const p=await fetch('/probe');if(await p.text()!=='no-auth')throw Error('headers escaped navigation');setTimeout(()=>nanoui.call('Demo.ready'),150)})
</script></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', default='zig-out/bin/page-request')
    parser.add_argument('--out', default='/tmp/nanoui-page-request.png')
    parser.add_argument('--no-capture', action='store_true', help='Verify requests without a macOS screenshot')
    args = parser.parse_args()
    events = []
    started = time.monotonic()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            elapsed = time.monotonic() - started
            auth = self.headers.get('Authorization')
            events.append({'path': self.path, 'authorized': auth == 'Bearer nanoui-demo', 'elapsed_ms': round(elapsed * 1000)})
            if self.path == '/':
                body = HTML.replace('ELAPSED', str(round(elapsed * 1000))).encode()
                self.send_response(200 if auth == 'Bearer nanoui-demo' else 401)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
            else:
                body = b'no-auth' if auth is None else b'unexpected-auth'
                self.send_response(200)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    worker = threading.Thread(target=server.serve_forever, daemon=True)
    worker.start()
    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.unlink(missing_ok=True)
    env = os.environ.copy()
    env.update(NANOUI_DEMO_URL=f'http://127.0.0.1:{server.server_port}/', NANOUI_DEMO_CHECK='1')
    if not args.no_capture:
        env['NANOUI_DEMO_CAPTURE'] = str(out)
    try:
        result = subprocess.run([args.binary, '--nanoui-hidden', '--nanoui-wait=12'], env=env, capture_output=True, text=True, timeout=25)
        assert result.returncode == 0, result.stderr
        documents = [e for e in events if e['path'] == '/']
        assert len(documents) == 1 and documents[0]['authorized'], events
        assert documents[0]['elapsed_ms'] >= 700, events
        assert any(e['path'] == '/probe' and not e['authorized'] for e in events), events
        assert 'authenticated document ready' in result.stderr, result.stderr
        if not args.no_capture:
            assert out.exists() and out.stat().st_size > 1000, result.stderr
        report = {'passed': True, 'events': events, 'capture': None if args.no_capture else str(out)}
        out.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()
