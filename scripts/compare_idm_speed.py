"""Paired real-file benchmarks of original Windows IDM and the native engine.

Uses IDM's documented command line in an isolated CrossOver bottle. Both paths
include dispatch, full-file completion, and SHA-256 verification in elapsed time.
No browser integration or artificial network throttle. Defaults remain unchanged.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parent.parent
CASES={
 'VS Code':('https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64-dmg',295206425),
 'Cursor':('https://api2.cursor.sh/updates/download/golden/darwin-arm64/cursor/3.23',294097415),
 'Antigravity':('https://storage.googleapis.com/antigravity-public/antigravity-hub/2.21.1-5614635819335680/darwin-arm/Antigravity.dmg',206573240),
}
def run_idm(name,url,size,trial,directory,deadline):
 wine=ROOT/'build/tools/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine'
 env=dict(os.environ,LC_ALL='C',LANG='C',CX_BOTTLE_PATH=str(ROOT/'build/bottles'))
 destination=directory/f'{name.replace(" ","-")}-{trial}.dmg'
 if destination.exists():raise RuntimeError('Benchmark destination already exists')
 log_path=directory/f'{name.replace(" ","-")}-{trial}-wine.log'
 with log_path.open('w') as log:
  start=time.perf_counter()
  launcher=subprocess.Popen([str(wine),'--bottle','IDM-Reference','--no-wait',r'C:\Program Files\Internet Download Manager\IDMan.exe','/d',url,'/p','Z:'+str(directory).replace('/','\\'),'/f',destination.name,'/n'],env=env,stdout=log,stderr=log)
  while not destination.exists() or destination.stat().st_size!=size:
   if time.perf_counter()-start>deadline:raise TimeoutError(f'Original IDM did not finish {name} within {deadline}s; inspect its dialog and log')
   time.sleep(.1)
  with destination.open('rb') as file:digest=hashlib.file_digest(file,'sha256').hexdigest()
  elapsed=time.perf_counter()-start
  # Existing IDM handles the request; the temporary launcher can be reaped when it exits.
  if launcher.poll() is not None:launcher.wait()
 destination.unlink()
 return {'engine':'original-idm-crossover','name':name,'trial':trial,'bytes':size,'seconds':round(elapsed,6),'MBps':round(size/elapsed/1e6,6),'sha256':digest}
def run_native(name,url,size,trial,deadline):
 start=time.perf_counter()
 result=subprocess.run([str(ROOT/'.build/release/IDMCoreChecks'),'--url',url],capture_output=True,text=True,timeout=deadline)
 elapsed=time.perf_counter()-start
 match=re.search(r'DOWNLOAD SUCCEEDED: (\d+) bytes, SHA256 ([a-f0-9]{64})',result.stdout)
 if result.returncode or not match:raise RuntimeError(f'Native check failed: {result.stdout} {result.stderr}')
 if int(match[1])!=size:raise RuntimeError('Native asset size changed; exclude the run')
 return {'engine':'native-release','name':name,'trial':trial,'bytes':size,'seconds':round(elapsed,6),'MBps':round(size/elapsed/1e6,6),'sha256':match[2]}
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--trials',type=int,default=3);parser.add_argument('--timeout',type=int,default=600);parser.add_argument('--case',choices=CASES);args=parser.parse_args()
 if args.trials<1 or args.timeout<=0:parser.error("trials and timeout must be positive")
 directory=ROOT/'build/speed-comparison'/time.strftime('run-%Y%m%d-%H%M%S');directory.mkdir(parents=True)
 report={'startedUTC':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'nativeConnections':8,'nativeBinarySHA256':hashlib.file_digest((ROOT/'.build/release/IDMCoreChecks').open('rb'),'sha256').hexdigest(),'originalSettings':'unmodified isolated reference installation defaults','timing':'command dispatch through full-file completion and checksum, including launcher overhead','runs':[]}
 def save(): (directory/'results.json').write_text(json.dumps(report,indent=2)+'\n')
 try:
  for name,(url,size) in CASES.items():
   if args.case and name!=args.case:continue
   for trial in range(1,args.trials+1):
    pair=[]
    order=[run_idm,run_native] if trial%2 else [run_native,run_idm]
    for run in order:
     print(f'RUN {name} trial {trial} {run.__name__}',flush=True)
     record=run(name,url,size,trial,directory,args.timeout) if run==run_idm else run(name,url,size,trial,args.timeout)
     report['runs'].append(record);pair.append(record);save();print(json.dumps(record),flush=True)
    if pair[0]['sha256']!=pair[1]['sha256']:raise RuntimeError('Pair checksum mismatch; speed comparison is invalid')
    for item in pair:item['pairChecksumMatched']=True
    save()
 except Exception as error:
  report['error']=str(error);save();raise
 print('RESULTS '+str(directory/'results.json'),flush=True)
if __name__=='__main__':main()
