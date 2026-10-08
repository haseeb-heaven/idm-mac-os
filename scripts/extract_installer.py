"""Extract valid zlib streams from the installer overlay without executing setup."""
import argparse, hashlib, json, re, zlib
from pathlib import Path
import pefile
parser=argparse.ArgumentParser();parser.add_argument('installer',type=Path);args=parser.parse_args()
root=Path(__file__).resolve().parent.parent;out=root/'samples';out.mkdir(exist_ok=True)
blob=args.installer.read_bytes();pe=pefile.PE(data=blob);overlay=pe.get_overlay_data_start_offset()
if overlay is None:raise SystemExit('No overlay found')
manifest=[]
for match in re.finditer(rb'\x78[\x01\x9c\xda]',blob[overlay:]):
 position=overlay+match.start()
 try:
  decoder=zlib.decompressobj();data=decoder.decompress(blob[position:],64*1024*1024)
 except zlib.error:continue
 if len(data)<1024 or not decoder.eof:continue
 name=f'payload-{position:x}'+('.exe' if data.startswith(b'MZ') else '.bin')
 (out/name).write_bytes(data)
 item={'offset':position,'bytes':len(data),'file':name,'sha256':hashlib.sha256(data).hexdigest()}
 if data.startswith(b'MZ'):
  app=pefile.PE(data=data)
  for groups in getattr(app,'FileInfo',[]):
   for group in groups:
    for table in getattr(group,'StringTable',[]):
     values={k.decode(errors='replace'):v.decode(errors='replace') for k,v in table.entries.items()}
     item['version']=values
     if values.get('OriginalFilename','').lower()=='idman.exe':(out/'IDMan.exe').write_bytes(data)
 manifest.append(item)
(root/'analysis/raw/extracted-streams.json').write_text(json.dumps(manifest,indent=2))
print(f'Extracted {len(manifest)} streams; installer SHA256 {hashlib.sha256(blob).hexdigest()}')
