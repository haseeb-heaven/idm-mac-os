"""Run native queue/toolbar checks using a real loopback HTTP server."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parent.parent
fixture=subprocess.Popen([sys.executable,str(root/'scripts/http_fixture.py')],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
try:
 port=int(fixture.stdout.readline())
 binary=sys.argv[1] if len(sys.argv)>1 else str(root/'build/MacDownloadManager.app/Contents/MacOS/MacDownloadManager')
 subprocess.run([binary,'--e2e-test',f'http://127.0.0.1:{port}',str(root/'build/ui-e2e.json')],check=True,timeout=60)
 print((root/'build/ui-e2e.json').read_text())
finally:
 fixture.terminate()
 fixture.wait(timeout=5)
