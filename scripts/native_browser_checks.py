#!/usr/bin/env python3
"""Actual packaged native-host/app acceptance checks with isolated data."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import selectors
import struct
import subprocess
import time
import uuid
from browser_fixture import Fixture, PAYLOAD, SHA256


def run(app, directory):
    directory.mkdir(parents=True, exist_ok=True)
    config = directory / 'browser-bridge.json'
    if config.exists():
        raise RuntimeError('Use a fresh test directory')
    process = subprocess.Popen([str(app / 'Contents/MacOS/MacDownloadManager'), '--browser-qa', str(directory)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    host = None
    checks = []
    try:
        for _ in range(100):
            if config.exists():
                break
            time.sleep(.1)
        if not config.exists():
            raise TimeoutError('Bridge did not start')
        assert config.stat().st_mode & 0o777 == 0o600
        host = subprocess.Popen([str(app / 'Contents/MacOS/MacDownloadManagerHost'), '--bridge-config', str(config), 'chrome-extension://amdlggemepjploaameacboladklhlndk/'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        def request(op, **fields):
            ident = str(uuid.uuid4())
            message = json.dumps(dict(id=ident, op=op, **fields)).encode()
            host.stdin.write(struct.pack('<I', len(message)) + message)
            host.stdin.flush()
            selector = selectors.DefaultSelector()
            try:
                selector.register(host.stdout, selectors.EVENT_READ)
                if not selector.select(10):
                    raise TimeoutError('Native host did not respond')
                length = struct.unpack('<I', host.stdout.read(4))[0]
                response = json.loads(host.stdout.read(length))
            finally:
                selector.close()
            assert response['id'] == ident
            return response
        assert request('ping')['status'] == 'ready'
        checks.append('native-ping-and-private-config')
        with Fixture() as fixture:
            links = [dict(url=fixture.url + '/file.bin', filename='same.bin'), dict(url=fixture.url + '/second.bin', filename='same.bin')]
            assert request('batch', links=links)['status'] == 'queued'
            deadline = time.monotonic() + 30
            files = [directory / 'downloads/same.bin', directory / 'downloads/same-1.bin']
            while not all(p.exists() and hashlib.sha256(p.read_bytes()).hexdigest() == SHA256 for p in files):
                if time.monotonic() > deadline:
                    raise TimeoutError('Batch checksum failed')
                time.sleep(.1)
            checks.append('batch-filename-collision-and-checksums')
            stream = str(uuid.uuid4())
            link = dict(url='blob:' + fixture.url + '/' + str(uuid.uuid4()), pageURL=fixture.url, filename='blob.bin')
            assert request('blobBegin', streamID=stream, links=[link], totalBytes=len(PAYLOAD))['status'] == 'accepted'
            assert request('blobBegin', streamID=stream, links=[link])['status'] == 'error'
            for sequence, offset in enumerate(range(0, len(PAYLOAD), 131072)):
                assert request('blobChunk', streamID=stream, sequence=sequence, data=base64.b64encode(PAYLOAD[offset:offset+131072]).decode())['status'] == 'accepted'
            response = request('blobFinish', streamID=stream, totalBytes=len(PAYLOAD))
            assert response['status'] == 'complete' and response['sha256'] == SHA256
            assert hashlib.sha256((directory / 'downloads/blob.bin').read_bytes()).hexdigest() == SHA256
            jobs = json.loads((directory / 'jobs.json').read_text())
            assert all(j['state'] == 'completed' for j in jobs)
            checks.append('duplicate-blob-begin-preserves-stream-and-durable-completion')
            stream = str(uuid.uuid4()); link['filename'] = 'abort.bin'
            assert request('blobBegin', streamID=stream, links=[link])['status'] == 'accepted'
            assert request('blobChunk', streamID=stream, sequence=1, data='YQ==')['status'] == 'error'
            assert not list((directory / 'downloads').glob('.mdm-blob-*'))
            assert not (directory / 'downloads/abort.bin').exists()
            checks.append('blob-sequence-error-cleans-staging')
        denied = subprocess.run([str(app / 'Contents/MacOS/MacDownloadManagerHost'), 'chrome-extension://unauthorized/'], input=b'', stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert denied.returncode == 2
        checks.append('unrecognized-extension-rejected')
        report = dict(checks=checks, passed=True, fixtureSHA256=SHA256)
        (directory / 'report.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report, indent=2))
    finally:
        if host:
            host.stdin.close()
            try:
                host.wait(timeout=3)
            except subprocess.TimeoutExpired:
                host.terminate(); host.wait(timeout=3)
        process.terminate(); process.wait(timeout=10)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--directory', required=True, type=Path)
    args = parser.parse_args()
    run(args.app.resolve(), args.directory.resolve())
