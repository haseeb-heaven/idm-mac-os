#!/usr/bin/env python3
"""Deterministic localhost fixture for isolated browser integration checks."""
import hashlib
import base64
import html
import uuid
import re
import http.server
import json
import threading
import time
import socketserver
from urllib.parse import urlsplit

PAYLOAD = bytes(range(256)) * 4096
SHA256 = hashlib.sha256(PAYLOAD).hexdigest()
PAGE = '''<!doctype html><title>IDM browser QA</title>
<a href="__SAFARI_HANDOFF__">Send fixture to IDM Mac</a>
<a href="/file.bin" download="fixture.bin">File</a>
<a href="/second.bin">Second</a><a href="/file.bin">Duplicate</a>
<video src="/video.mp4"></video><audio src="/audio.mp3"></audio>
<script>
window.fixtureBytes = Uint8Array.from({length:1048576},(_,i)=>i%256);
window.fixtureBlob = new Blob([fixtureBytes], {type:'application/octet-stream'});
window.fixtureBlobURL = URL.createObjectURL(fixtureBlob);
const a = document.createElement('a'); a.href=fixtureBlobURL;a.download='blob.bin';a.textContent='Blob';document.body.append(a);
window.expiredBlobURL=URL.createObjectURL(fixtureBlob);URL.revokeObjectURL(expiredBlobURL);
</script>'''

class LoopbackHTTPServer(http.server.ThreadingHTTPServer):
    def server_bind(self):
        # Avoid reverse DNS in isolated loopback tests on hosted runners.
        socketserver.TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]


class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/':
            request={'id':str(uuid.uuid4()),'op':'download','links':[{'url':'http://127.0.0.1:'+str(self.server.server_port)+'/file.bin','filename':'safari.bin'}]}
            payload=base64.urlsafe_b64encode(json.dumps(request).encode()).decode().rstrip('=')
            handoff='idm-mac://download?payload='+payload
            self.server.handoff_url=handoff
            body, kind = PAGE.replace('__SAFARI_HANDOFF__',html.escape(handoff)).encode(), 'text/html; charset=utf-8'
        elif path == '/cookie':
            body, kind = b'Cookie configured', 'text/plain'
        elif path == '/protected.bin' and 'idm_qa=authorized' not in self.headers.get('Cookie', ''):
            self.send_error(403, 'Fixture session cookie required')
            return
        elif path in ('/file.bin', '/second.bin', '/third.bin', '/protected.bin', '/capture.bin', '/fallback.bin', '/video.mp4', '/audio.mp3'):
            body, kind = PAYLOAD, 'application/octet-stream'
        else:
            self.send_error(404)
            return
        full_length=len(body)
        requested=self.headers.get('Range')
        if requested and self.server.support_ranges and path.endswith(('.bin','.mp4','.mp3')):
            match=re.fullmatch(r'bytes=(\d+)-(\d*)',requested)
            if not match:
                self.send_error(400);return
            first=int(match[1]);last=min(int(match[2]) if match[2] else full_length-1,full_length-1)
            if first>last:
                self.send_response(416);self.send_header('Content-Range',f'bytes */{full_length}');self.end_headers();return
            body=body[first:last+1]
            self.send_response(206)
            self.send_header('Content-Range',f'bytes {first}-{last}/{full_length}')
        else:self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Accept-Ranges', 'bytes' if self.server.support_ranges else 'none')
        if path == '/cookie':
            self.send_header('Set-Cookie', 'idm_qa=authorized; Path=/; SameSite=Lax')
        if path.endswith('.bin'):
            self.send_header('Content-Disposition', 'attachment; filename="' + path[1:] + '"')
        self.end_headers()
        if self.command=='HEAD':return
        try:
            if path in ('/capture.bin','/fallback.bin'):
                for offset in range(0,len(body),16384):
                    self.wfile.write(body[offset:offset+16384]); self.wfile.flush(); time.sleep(.02)
            else:
                self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass
    def log_message(self, *_):
        pass

class Fixture:
    def __init__(self,support_ranges=False):
        self.support_ranges=support_ranges

    def __enter__(self):
        self.server = LoopbackHTTPServer(('127.0.0.1', 0), Handler)
        self.server.support_ranges=self.support_ranges
        request={'id':str(uuid.uuid4()),'op':'download','links':[{'url':'http://127.0.0.1:'+str(self.server.server_port)+'/file.bin','filename':'safari.bin'}]}
        self.server.handoff_url='idm-mac://download?payload='+base64.urlsafe_b64encode(json.dumps(request).encode()).decode().rstrip('=')
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:' + str(self.server.server_port)
        return self
    def __exit__(self, *_):
        self.server.shutdown()
        self.server.server_close()

if __name__ == '__main__':
    with Fixture() as fixture:
        print(json.dumps({'url': fixture.url, 'size': len(PAYLOAD), 'sha256': SHA256}), flush=True)
        threading.Event().wait()
