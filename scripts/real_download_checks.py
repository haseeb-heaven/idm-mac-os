"""Opt-in real HTTP downloads with independent curl checksum comparison."""
from pathlib import Path
import hashlib,subprocess,json
root=Path(__file__).resolve().parent.parent
links={
 'VS Code':'https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64-dmg',
 'Cursor':'https://api2.cursor.sh/updates/download/golden/darwin-arm64/cursor/3.23',
 'Antigravity':'https://storage.googleapis.com/antigravity-public/antigravity-hub/2.21.1-5614635819335680/darwin-arm/Antigravity.dmg',
}
results=[]
for name,url in links.items():
 print('RUN '+name,flush=True)
 reference=root/'build'/f'{name.replace(" ","-")}-reference.dmg'
 curl=subprocess.run(['curl','-fsSL','--max-time','300',url,'-o',str(reference)],capture_output=True,text=True)
 args=[str(root/'.build/debug/DownloadCoreChecks'),'--url',url]
 if curl.returncode==0:
  with reference.open('rb') as file:hash=hashlib.file_digest(file,'sha256').hexdigest()
  args+=['--sha256',hash]
 result=subprocess.run(args,capture_output=True,text=True,timeout=600)
 record={'name':name,'url':url,'referenceSucceeded':curl.returncode==0,'nativeSucceeded':result.returncode==0,'nativeOutput':result.stdout.strip()}
 results.append(record);print(json.dumps(record),flush=True)
 if reference.exists():reference.unlink()
(root/'build/real-download-results.json').write_text(json.dumps(results,indent=2)+'\n')

raise SystemExit(0 if all(r["referenceSucceeded"] and r["nativeSucceeded"] for r in results) else 1)
