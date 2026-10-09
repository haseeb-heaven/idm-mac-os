#!/usr/bin/env python3
"""Build independently authored Chromium/Firefox extensions and Safari handoff."""
import argparse, json, shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, default=ROOT / 'build/extensions')
p.add_argument('--host-name')
a = p.parse_args()
identity = json.loads((ROOT / 'integrations/identity.json').read_text())
host = a.host_name or identity['hostName']
a.output.mkdir(parents=True, exist_ok=True)
for browser in ('chromium', 'firefox'):
    dest = a.output / browser
    dest.mkdir(parents=True, exist_ok=True)
    # Remove legacy locally staged diagnostics before creating production resources.
    for diagnostic in ('qa.js','qa.html'):
        (dest / diagnostic).unlink(missing_ok=True)
    for source in (ROOT / 'integrations/shared').iterdir():
        if source.name in ('background.js','core.js','popup.html','popup.js'):
            shutil.copy2(source, dest / source.name)
    (dest / 'config.js').write_text('globalThis.IDM_CONFIG = ' + json.dumps({'hostName':host}) + ';\n')
    manifest = {'manifest_version':3 if browser == 'chromium' else 2, 'name':'IDM Extension', 'version':'1.0.0', 'description':'Reviewed native download handoff and browser Blob imports.', 'permissions':['nativeMessaging','downloads','storage','contextMenus','activeTab'], 'optional_permissions':['cookies']}
    if browser == 'chromium':
        manifest.update({'key':identity['publicKey'],'background':{'service_worker':'background.js'},'action':{'default_popup':'popup.html'},'optional_host_permissions':['http://*/*','https://*/*']})
        manifest['permissions'].append('scripting')
    else:
        manifest.update({'browser_specific_settings':{'gecko':{'id':identity['firefoxID']}},'background':{'scripts':['config.js','core.js','background.js']},'browser_action':{'default_popup':'popup.html'}})
        manifest['optional_permissions'] += ['http://*/*','https://*/*']
    (dest / 'manifest.json').write_text(json.dumps(manifest,indent=2) + '\n')
bookmarklet = """javascript:(()=>{const s=getSelection();let links=[...document.querySelectorAll('a[href]')].filter(a=>s&&Array.from({length:s.rangeCount},(_,i)=>s.getRangeAt(i)).some(r=>r.intersectsNode(a))).map(a=>({url:a.href}));if(!links.length){const u=prompt('HTTP/HTTPS file, page, or direct media URL',location.href);if(!u)return;links=[{url:u}]}links=[...new Map(links.filter(l=>/^https?:\\/\\//i.test(l.url)).map(l=>[l.url,l])).values()].slice(0,200);if(!links.length)return alert('No HTTP/HTTPS links');const uuid=()=>{if(crypto.randomUUID)return crypto.randomUUID();const b=crypto.getRandomValues(new Uint8Array(16));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;const h=[...b].map(x=>x.toString(16).padStart(2,'0'));return h.slice(0,4).join('')+'-'+h.slice(4,6).join('')+'-'+h.slice(6,8).join('')+'-'+h.slice(8,10).join('')+'-'+h.slice(10).join('')};const request={id:uuid(),op:links.length===1?'download':'batch',links};const bytes=new TextEncoder().encode(JSON.stringify(request));let b='';for(const x of bytes)b+=String.fromCharCode(x);location.href='idm-mac://download?payload='+btoa(b).replace(/\\+/g,'-').replace(/\\//g,'_').replace(/=+$/,'')})()"""
(a.output / 'bookmarklet.txt').write_text(bookmarklet + '\n')
import html
(a.output / 'setup.html').write_text('''<!doctype html><html><head><meta charset="utf-8"><title>Browser Integrations</title></head><body><h1>Browser Integrations</h1><p>First install the native messaging host from the IDM Browser Integrations menu.</p><h2>Chromium (Chrome, Edge, Brave and other Chromium browsers)</h2><p>Download <code>IDM-Extension-&lt;version&gt;-chromium.zip</code> from the app release, extract it, then open chrome://extensions (or edge://extensions, brave://extensions), enable Developer mode, choose Load unpacked, and select the extracted folder. The same build works in every Chromium-based browser.</p><h2>Firefox</h2><p>Download <code>IDM-Extension-&lt;version&gt;-firefox.zip</code> from the app release and extract it. Open about:debugging#/runtime/this-firefox, choose Load Temporary Add-on, and select the extracted <code>manifest.json</code>. Temporary installs disappear on browser restart; permanent distribution requires Mozilla signing.</p><h2>Safari and universal HTTP handoff</h2><p>Drag <a href="''' + html.escape(bookmarklet,quote=True) + '''">Download with IDM</a> to the bookmarks bar. It sends selected links, or prompts for an HTTP/HTTPS URL. The native app reviews every destination. Safari native extension packaging has not been verified.</p><h2>Diagnostics</h2><p>Open the extension popup and choose Check native connection. Copy status provides a shareable error message. Automatic capture and cookie sharing start disabled. Cookie sharing requests permission for the current site. Protected media and expired Blob URLs may not be importable.</p></body></html>''')
print(a.output)
