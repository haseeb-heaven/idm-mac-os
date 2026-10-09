#!/usr/bin/env python3
"""Build and verify separately packaged Apple Silicon, Intel, and universal apps."""
import hashlib, json, plistlib, re, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT/'version.json').read_text())
OUT = ROOT/'build/releases'
def command(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.STDOUT).strip()
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        while block:=f.read(1024*1024): h.update(block)
    return h.hexdigest()
# Universal packaging builds both thin bundles and then joins their executable slices.
subprocess.run(['scripts/package.sh','--arch','universal'],cwd=ROOT,check=True)
artifacts=[]
for architecture in ('arm64','x86_64','universal'):
    source_app=OUT/architecture/'IDM Mac.app'
    # FileProvider may reattach FinderInfo in Documents after packaging. Perform
    # archive verification on a metadata-free staging copy, outside Documents.
    staging=tempfile.TemporaryDirectory(prefix='idm-release-stage-',dir='/private/tmp')
    app=Path(staging.name)/'IDM Mac.app'
    command('ditto','--norsrc','--noextattr',str(source_app),str(app))
    command('xattr','-cr',str(app))
    expected={'arm64','x86_64'} if architecture=='universal' else {architecture}
    plist=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    assert plist['CFBundleShortVersionString']==VERSION['version']
    assert plist['LSMinimumSystemVersion']==VERSION['minimumMacOS']
    command('codesign','--verify','--strict',str(app))
    binaries=[]
    for product in ('IDMMac','IDMBrowserHost'):
        binary=app/'Contents/MacOS'/product
        architectures=set(command('lipo','-archs',str(binary)).split())
        assert architectures==expected,(product,architectures,expected)
        command('codesign','--verify','--strict',str(binary))
        load_commands=command('otool','-l',str(binary))
        minimums=re.findall(r'\bminos\s+([\d.]+)',load_commands)
        assert minimums and all(x.startswith('13.') for x in minimums),(product,minimums)
        binaries.append({'name':product,'architectures':sorted(architectures),'sha256':digest(binary),'minimumMacOS':minimums,'signature':'ad hoc; strict verification passed'})
    archive=OUT/f'IDM-Mac-{VERSION["version"]}-{architecture}.zip'
    # No resource forks or quarantine metadata are distributed in release archives.
    command('ditto','-c','-k','--norsrc','--noextattr','--keepParent',str(app),str(archive))
    with tempfile.TemporaryDirectory(prefix='idm-release-verify-',dir='/private/tmp') as extraction:
        command('ditto','-x','-k','--norsrc','--noextattr',str(archive),extraction)
        extracted=Path(extraction)/app.name
        command('codesign','--verify','--strict',str(extracted))
        for product in ('IDMMac','IDMBrowserHost'):
            assert digest(extracted/'Contents/MacOS'/product)==digest(app/'Contents/MacOS'/product)
    artifacts.append({'filename':archive.name,'bytes':archive.stat().st_size,'sha256':digest(archive),'binaries':binaries})
    staging.cleanup()
manifest={'version':VERSION['version'],'minimumMacOS':VERSION['minimumMacOS'],'artifacts':artifacts,'runtimeValidation':'See docs/macos-compatibility.md; cross-compilation is not hardware validation.'}
(OUT/'release-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(OUT/'SHA256SUMS').write_text(''.join(f'{a["sha256"]}  {a["filename"]}\n' for a in artifacts))
print(json.dumps(manifest,indent=2))
