#!/usr/bin/env python3
"""Capture the real host callback using private in-process AppKit drag input."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', default='zig-out/bin/page-drop')
parser.add_argument('--out', default='/tmp/nanoui-page-drop.png')
args = parser.parse_args()
out = Path(args.out).resolve()
out.parent.mkdir(parents=True, exist_ok=True)
out.unlink(missing_ok=True)
with tempfile.TemporaryDirectory(prefix='nanoui-drop-fixture-') as fixture:
    for name in ('Track 01.wav', 'Cover Art.png'):
        (Path(fixture) / name).write_bytes(b'nanoui drop test fixture')
    env = os.environ.copy()
    env.update(NANOUI_DEMO_CAPTURE=str(out), NANOUI_DROP_FIXTURE=fixture)
    result = subprocess.run([args.binary, '--nanoui-hidden', '--nanoui-wait=12'], env=env, capture_output=True, text=True, timeout=25)
    assert result.returncode == 0, result.stderr
    assert result.stderr.count('demo: drop 1, 2 files at ') == 1, result.stderr
    assert 'demo: drop 2' not in result.stderr, result.stderr
    assert out.exists() and out.stat().st_size > 1000, result.stderr
    report = {'passed': True, 'input': 'private in-process AppKit drag fixture, not an OS drag session', 'callbacks': 1, 'files': 2, 'capture': str(out)}
    out.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
