"""Deterministic loopback fixture for download-engine integration tests."""
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
import re,threading,time,socket
from urllib.parse import urlsplit
DATA=bytes(range(256))*4096
lock=threading.Lock(); attempts={}
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_HEAD(self):self.serve(False)
 def do_GET(self):self.serve(True)
 def serve(self,body):
  path=urlsplit(self.path).path
  if path=='/redirect':
   self.send_response(302);self.send_header('Location','/file');self.end_headers();return
  if path=='/auth' and self.headers.get('Authorization')!='Basic dXNlcjpwYXNz':
   self.send_response(401);self.send_header('WWW-Authenticate','Basic realm="fixture"');self.end_headers();return
  if path=='/missing':self.send_error(404);return
  if path=='/headforbidden' and not body:self.send_error(403);return
  if path=='/protected':
   self.send_response(403);self.send_header('cf-mitigated','challenge');self.end_headers();return
  if path in ['/nohead','/emptyhead'] and not body:self.send_error(405);return
  if (path=='/flaky' and body) or (path=='/headflaky' and not body):
   with lock:attempts[path]=attempts.get(path,0)+1;number=attempts[path]
   if number==1:self.send_error(503);return
  if path=='/large':
   length=5*1024*1024*1024;start=0;end=length-1
   ranged=self.headers.get('Range')
   if ranged:
    match=re.fullmatch(r'bytes=(\d+)-(\d+)',ranged)
    if not match:self.send_error(416);return
    start,end=map(int,match.groups())
    if start>end or end>=length:self.send_error(416);return
   self.send_response(206 if ranged else 200)
   self.send_header('Content-Length',str(end-start+1))
   self.send_header('Accept-Ranges','bytes');self.send_header('ETag','"large-v1"')
   if ranged:self.send_header('Content-Range',f'bytes {start}-{end}/{length}')
   self.end_headers()
   if body:
    try:
     for position in range(start,end+1,65536):
      size=min(65536,end-position+1);offset=position%256
      self.wfile.write(DATA[offset:offset+size])
    except (BrokenPipeError,ConnectionResetError,OSError):pass
   return
  if path in ['/page','/basepage','/commentbase','/bigpage','/manylinks']:
   payload=b'<html><a href="/asset.zip">zip</a><a href="/page">page</a><a href="/asset.zip">duplicate</a><script src="javascript:x"></script></html>'
   if path=='/basepage':payload=b'<html><base href="/assets/"><a href="file.zip">zip</a></html>'
   if path=='/commentbase':payload=b'<html><!-- <base href="/old/"> --><script>var x=\'<base href="/wrong/">\';</script><base href="/assets/"><a href="file.zip">zip</a></html>'
   if path=='/bigpage':payload=b'x'*(2*1024*1024+1)
   if path=='/manylinks':payload=(''.join(f'<a href="/asset{i}.zip">file</a>' for i in range(510))).encode()
   self.send_response(200);self.send_header('Content-Type','text/html');self.send_header('Content-Length',str(len(payload)));self.end_headers()
   if body:self.wfile.write(payload)
   return
  payload=b'' if path in ['/empty','/emptyhead'] else DATA
  if path in ['/gethtml','/htmlattachment'] and body:payload=b'<html>login or attachment</html>'
  validator='"fixture-v2"' if path=='/changed' and body else '"fixture-v1"'
  ranged=self.headers.get('Range') if path not in ['/norange','/ignore','/weakignore','/omitignore','/changed','/nohead','/retryfull','/gethtml','/htmlattachment'] else None
  if ranged:
   match=re.fullmatch(r'bytes=(\d+)-(\d+)',ranged)
   if not match:self.send_error(416);return
   start,end=map(int,match.groups())
   if start> end or end>=len(payload):self.send_error(416);return
   payload=payload[start:end+1];self.send_response(206)
   self.send_header('Content-Range',f'bytes {start+1 if path=="/bad" else start}-{end}/{len(DATA)}')
  else:self.send_response(200)
  if path not in ['/unknown','/gethtml','/htmlattachment']:self.send_header('Content-Length',str(len(payload)))
  if path in ['/gethtml','/htmlattachment'] and body:self.send_header('Content-Type','text/html')
  if path=='/htmlattachment':self.send_header('Content-Disposition','attachment; filename=sample.html')
  if path not in ['/norange','/nohead','/unknown','/retryfull']:self.send_header('Accept-Ranges','bytes')
  if path=='/weakignore':
   self.send_header('ETag','W/"fixture-v1"');self.send_header('Last-Modified','Wed, 07 Oct 2026 12:00:00 GMT')
  elif path!='/novalidator' and not (path=='/omitignore' and body):self.send_header('ETag',validator)
  self.end_headers()
  if not body:return
  try:
   if path=='/retryfull':
    with lock:attempts[path]=attempts.get(path,0)+1;number=attempts[path]
    if number==1:
     self.wfile.write(payload[:150000]);self.wfile.flush();self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
   if path=='/truncate':
    self.wfile.write(payload[:70000]);self.wfile.flush();self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
   for index in range(0,len(payload),16384):
    self.wfile.write(payload[index:index+16384]);self.wfile.flush()
    if path=='/slow':time.sleep(.025)
  except (BrokenPipeError,ConnectionResetError,OSError):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
print(server.server_address[1],flush=True)
server.serve_forever()
