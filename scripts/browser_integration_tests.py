#!/usr/bin/env python3
"""Execute real Chromium extension/Swift host/app tests using isolated storage."""
import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import time
from browser_fixture import Fixture, SHA256
from browser_test_tools import CDP, WebDriver, wait_target

EXTENSION_ID = 'amdlggemepjploaameacboladklhlndk'

def prepare_extension(source, qa):
    """Stage diagnostic controls privately; never ship test controls to users."""
    extension = qa/'extension'
    shutil.copytree(Path(source).resolve(), extension)
    (extension/'config.js').write_text('globalThis.IDM_CONFIG = {"hostName":"local.haseebheaven.idmmac.test"};\n')
    (extension/'qa.html').write_text('''<!doctype html><html><head><meta charset="utf-8"><title>IDM integration diagnostics</title></head><body><h1>IDM integration diagnostics</h1><label>Diagnostic site origin <input id="origin" value="http://127.0.0.1/*"></label><button id="grant">Allow diagnostic site</button><button id="grant-session">Allow diagnostic cookies</button><button id="ping">Check host</button><pre id="result"></pre><script src="core.js"></script><script src="qa.js"></script></body></html>''')
    (extension/'qa.js').write_text('''const api = globalThis.browser || chrome;
window.IDM_QA = async message => { const result = await api.runtime.sendMessage(message); document.getElementById('result').textContent = JSON.stringify(result); return result; };
window.IDM_QA_SETTINGS = settings => api.storage.local.set(settings);
document.getElementById('ping').onclick = () => window.IDM_QA({action:'ping'});
document.getElementById('grant').onclick = async () => { const granted = await api.permissions.request({origins:[IDMCore.permissionPattern(document.getElementById('origin').value)]}); document.getElementById('result').textContent = JSON.stringify({granted}); };
document.getElementById('grant-session').onclick = async () => { const granted = await api.permissions.request({permissions:['cookies'],origins:[IDMCore.permissionPattern(document.getElementById('origin').value)]}); document.getElementById('result').textContent = JSON.stringify({granted}); };
''')
    return extension

def completed_native_destinations(directory):
    try:jobs=json.loads((directory.parent/'jobs.json').read_text())
    except (FileNotFoundError,json.JSONDecodeError):return set()
    return {Path(job['destination']).resolve() for job in jobs if job.get('state')=='completed'}

def matching_final_files(directory, previous, native=True):
    completed=completed_native_destinations(directory) if native else None
    return [path for path in directory.rglob('*')
            if path.is_file() and path not in previous
            and not any(part.startswith('.idm-blob') for part in path.parts)
            and not path.name.endswith(('.crdownload','.part'))
            and (completed is None or path.resolve() in completed)
            and hashlib.sha256(path.read_bytes()).hexdigest()==SHA256]

def wait_file(directory, previous, timeout=45, native=True):
    return wait_files(directory,previous,1,timeout,native)[0]

def wait_files(directory, previous, count, timeout=45, native=True):
    deadline=time.monotonic()+timeout
    while True:
        matching=matching_final_files(directory,previous,native)
        if len(matching)==count:return matching
        if len(matching)>count:raise AssertionError('Download dedup created extra files')
        if time.monotonic()>=deadline:raise TimeoutError('Expected '+str(count)+' completed final SHA256 files with durable native completed state')
        time.sleep(.2)

def wait_download_state(evaluate, ident, state, browser_api, timeout=10):
    deadline=time.monotonic()+timeout
    while True:
        item=evaluate(browser_api+'.downloads.search({id:'+str(ident)+'}).then(x=>x[0])')
        if item and item.get('state')==state:return item
        if time.monotonic()>deadline:raise AssertionError(item)
        time.sleep(.1)

def bridge_rejections(qa):
    import socket
    import struct
    config=json.loads((qa/'browser-bridge.json').read_text())
    before=(qa/'jobs.json').read_bytes() if (qa/'jobs.json').exists() else None
    cases={
        'forged-token': json.dumps({'token':'0'*64,'request':{'id':'qa-forged','op':'ping'}}).encode(),
        'oversized-frame': None,
    }
    results=[]
    for name,payload in cases.items():
        with socket.create_connection(('127.0.0.1',config['port']),timeout=3) as connection:
            frame=struct.pack('<I',len(payload))+payload if payload else struct.pack('<I',1048577)
            connection.sendall(frame);connection.shutdown(socket.SHUT_WR)
            try:received=connection.recv(4096)
            except ConnectionResetError:received=b''
            if received:
                response=json.loads(received[4:].decode())
                if response.get('status') not in ('error','cancelled'):raise AssertionError('Forged bridge request accepted')
            results.append({'name':name,'rejected':True})
    after=(qa/'jobs.json').read_bytes() if (qa/'jobs.json').exists() else None
    if before!=after:raise AssertionError('Rejected bridge frames changed jobs')
    return results

def run(args):
    qa = Path(args.directory).resolve()
    qa.mkdir(parents=True, exist_ok=True)
    if (qa/'browser-bridge.json').exists():raise RuntimeError('Use a fresh QA directory')
    downloads = qa/'downloads'
    downloads.mkdir(exist_ok=True)
    app = Path(args.app).resolve()
    extension = prepare_extension(args.extension, qa)
    profile = qa/'chromium-profile'
    hosts = profile/'NativeMessagingHosts'
    hosts.mkdir(parents=True,exist_ok=True)
    launcher = qa/'native-host'
    launcher.write_text('#!'+sys.executable+'\nimport os,sys,json\nopen('+repr(str(qa/'host-arguments.json'))+',"w").write(json.dumps(sys.argv))\nos.execv('+repr(str(app/'Contents/MacOS/IDMBrowserHost'))+', ['+repr(str(app/'Contents/MacOS/IDMBrowserHost'))+', "--bridge-config", '+repr(str(qa/'browser-bridge.json'))+', "--app", '+repr(str(app))+']+sys.argv[1:])\n')
    launcher.chmod(0o700)
    host_name='local.haseebheaven.idmmac.test'
    (hosts/(host_name+'.json')).write_text(json.dumps({'name':host_name,'description':'Isolated IDM browser QA','path':str(launcher),'type':'stdio','allowed_origins':['chrome-extension://'+EXTENSION_ID+'/']}))
    report={'browser':'Chrome for Testing','checks':[]}
    processes=[]
    try:
        processes.append(subprocess.Popen([str(app/'Contents/MacOS/IDMMac'),'--browser-qa',str(qa)],stdout=(qa/'app.stdout').open('w'),stderr=(qa/'app.stderr').open('w')))
        deadline=time.monotonic()+30
        while not (qa/'browser-bridge.json').exists():
            if time.monotonic()>deadline: raise TimeoutError('App bridge config missing')
            time.sleep(.2)
        report['checks'].extend(bridge_rejections(qa))
        with Fixture(support_ranges=args.resumable_fixture) as fixture:
            chrome=subprocess.Popen([args.chrome,'--user-data-dir='+str(profile),'--remote-debugging-port=0','--enable-unsafe-extension-debugging','--no-first-run','--no-default-browser-check','--load-extension='+str(extension),'--disable-extensions-except='+str(extension),'chrome-extension://'+EXTENSION_ID+'/qa.html',fixture.url],stdout=(qa/'chrome.stdout').open('w'),stderr=(qa/'chrome.stderr').open('w'))
            processes.append(chrome)
            deadline=time.monotonic()+30
            while not (profile/'DevToolsActivePort').exists():
                if time.monotonic()>deadline: raise TimeoutError('Chrome debugging port missing')
                time.sleep(.2)
            port=int((profile/'DevToolsActivePort').read_text().splitlines()[0])
            browser_control=CDP('ws://127.0.0.1:'+str(port)+(profile/'DevToolsActivePort').read_text().splitlines()[1])
            report['extensionLoad']=browser_control.call('Extensions.loadUnpacked',{'path':str(extension)})
            tab=wait_target(port,fixture.url)
            tab_targets=browser_control.call('Target.getTargets',{'filter':[{'type':'tab'},{'exclude':True}]})['targetInfos']
            report['tabTargets']=tab_targets
            (qa/'target-diagnostic.json').write_text(json.dumps(report,indent=2))
            toolbar_target=next(t['targetId'] for t in tab_targets if t['url'].startswith(fixture.url))
            browser_control.call('Extensions.triggerAction',{'id':EXTENSION_ID,'targetId':toolbar_target})
            browser_control.call('Target.createTarget',{'url':'chrome-extension://'+EXTENSION_ID+'/qa.html'})
            browser_control.close()
            tab=wait_target(port,fixture.url)
            control=CDP(wait_target(port,'/qa.html')['webSocketDebuggerUrl'])
            control.call('Page.navigate',{'url':'chrome-extension://'+EXTENSION_ID+'/qa.html'})
            deadline=time.monotonic()+20
            while not control.evaluate('typeof IDM_QA === "function"'):
                if time.monotonic()>deadline:raise TimeoutError(control.evaluate('document.body.innerText.slice(0,500)'))
                time.sleep(.2)
            control.call('Page.bringToFront')
            tab_id=control.evaluate('chrome.tabs.query({}).then(t=>t.find(x=>x.url?.startsWith('+json.dumps(fixture.url)+')).id)')
            def check(name,action,download=False):
                previous=set(downloads.rglob('*'))
                result=control.evaluate('IDM_QA('+json.dumps(action)+')')
                if isinstance(result,dict) and result.get('error'): raise AssertionError(result)
                item={'name':name,'response':result}
                if download:item['files']=[str(p) for p in wait_files(downloads,previous,int(download))];item['sha256']=SHA256
                report['checks'].append(item)
            check('native-ping',{'action':'ping'})
            check('http-download',{'action':'download','tabID':tab_id,'links':[{'url':fixture.url+'/file.bin'}]},True)
            check('batch-dedup',{'action':'download','tabID':tab_id,'links':[{'url':fixture.url+'/second.bin'},{'url':fixture.url+'/third.bin'},{'url':fixture.url+'/second.bin'}]},2)
            page=CDP(tab['webSocketDebuggerUrl'])
            page.evaluate('fetch("/cookie").then(r=>r.text())')
            blob=page.evaluate('fixtureBlobURL')
            collected=control.evaluate('IDM_QA('+json.dumps({'action':'collect','tabID':tab_id,'kind':'all'})+')')
            if not any(x['url'].startswith('blob:') for x in collected):raise AssertionError('Fixture Blob link missing')
            check('mixed-http-blob-links',{'action':'download','tabID':tab_id,'links':collected},2)
            check('live-blob',{'action':'blob','tabID':tab_id,'url':blob,'filename':'blob.bin'},True)
            expired=page.evaluate('expiredBlobURL')
            result=control.evaluate('IDM_QA('+json.dumps({'action':'blob','tabID':tab_id,'url':expired,'filename':'expired.bin'})+')')
            if not result.get('error'): raise AssertionError('Expired blob did not return a visible error')
            report['checks'].append({'name':'expired-blob','response':result})
            media=control.evaluate('IDM_QA('+json.dumps({'action':'collect','tabID':tab_id,'kind':'media'})+')')
            if not isinstance(media,list) or {x['url'] for x in media} != {fixture.url+'/video.mp4',fixture.url+'/audio.mp3'}:raise AssertionError(media)
            report['checks'].append({'name':'media-selection','response':media})
            # Invoke the registered context-menu callback inside the real worker,
            # then interact with its actual selection page (not collection alone).
            page.evaluate('const mediaBlob=document.createElement("audio");mediaBlob.src=fixtureBlobURL;document.body.append(mediaBlob)')
            previous=set(downloads.rglob('*'))
            worker=CDP(wait_target(port,'chrome-extension://'+EXTENSION_ID+'/background.js')['webSocketDebuggerUrl'])
            worker.evaluate('chrome.tabs.get('+str(tab_id)+').then(tab=>contextMenuClicked({menuItemId:"media"},tab))')
            worker.close()
            chooser=CDP(wait_target(port,'popup.html?media=1')['webSocketDebuggerUrl'])
            deadline=time.monotonic()+15
            while chooser.evaluate('document.querySelector("#choices")?.options.length')!=3:
                if time.monotonic()>deadline:raise TimeoutError('Media context selector did not show HTTP and Blob choices')
                time.sleep(.1)
            if set(downloads.rglob('*'))!=previous:raise AssertionError('Media selector queued downloads before selection')
            chooser.evaluate('document.querySelector("#choices").value="0";document.querySelector("#chosen").click()')
            http_file=wait_files(downloads,previous,1)[0]
            previous=set(downloads.rglob('*'))
            chooser.evaluate('const choices=document.querySelector("#choices");choices.value=[...choices.options].find(x=>x.textContent.startsWith("blob:")).value;document.querySelector("#chosen").click()')
            blob_file=wait_files(downloads,previous,1)[0]
            report['checks'].append({'name':'media-context-menu-choice-http-and-blob','files':[str(http_file),str(blob_file)],'sha256':SHA256})
            chooser.call('Page.close');chooser.close()
            browser_downloads=qa/'browser-downloads';browser_downloads.mkdir(exist_ok=True)
            control.call('Browser.setDownloadBehavior',{'behavior':'allow','downloadPath':str(browser_downloads)})
            control.evaluate('IDM_QA_SETTINGS({capture:true})')
            previous=set(downloads.rglob('*'))
            captured_id=control.evaluate('chrome.downloads.download({url:'+json.dumps(fixture.url+'/capture.bin')+'})')
            captured_file=wait_file(downloads,previous)
            captured=wait_download_state(control.evaluate,captured_id,'interrupted','chrome')
            if captured.get('state')!='interrupted' or captured.get('error')!='USER_CANCELED':raise AssertionError(captured)
            report['checks'].append({'name':'download-interception','browserState':captured,'file':str(captured_file),'sha256':SHA256})
            registration=hosts/(host_name+'.json')
            hidden=registration.with_suffix('.disabled');registration.rename(hidden)
            try:
                previous=set(browser_downloads.rglob('*'))
                fallback_id=control.evaluate('chrome.downloads.download({url:'+json.dumps(fixture.url+'/fallback.bin')+'})')
                fallback_file=wait_file(browser_downloads,previous,native=False)
                fallback=wait_download_state(control.evaluate,fallback_id,'complete','chrome')
                if fallback.get('state')!='complete':raise AssertionError(fallback)
                report['checks'].append({'name':'host-failure-resumes-browser','browserState':fallback,'file':str(fallback_file),'sha256':SHA256})
            finally:hidden.rename(registration)
            control.call('Page.bringToFront')
            control.call('Runtime.evaluate',{'expression':'document.querySelector("#grant-session").click()','userGesture':True})
            time.sleep(1)
            granted=control.evaluate('chrome.permissions.contains({permissions:["cookies"],origins:["http://127.0.0.1/*"]})')
            if granted:
                control.evaluate('IDM_QA_SETTINGS({capture:false,session:true})')
                check('cookie-protected-download',{'action':'download','tabID':tab_id,'links':[{'url':fixture.url+'/protected.bin'}]},True)
                control.evaluate('IDM_QA_SETTINGS({session:false})')
            else:report['limitations']=['Chromium optional cookie permission UI did not complete during automation']
            page.close(); control.close()
    except Exception as error:
        report['failure']=str(error)
        raise
    finally:
        for process in reversed(processes):
            process.terminate()
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
        report['nativeCompletedJobs']=[{'filename':path.name,'state':'completed','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size} for path in sorted(completed_native_destinations(downloads)) if path.is_file()]
        (qa/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

def run_firefox(args):
    """Firefox uses a unique temporary native registration and isolated profile."""
    import socket
    import zipfile
    qa=Path(args.directory).resolve();qa.mkdir(parents=True,exist_ok=True)
    if (qa/'browser-bridge.json').exists():raise RuntimeError('Use a fresh QA directory')
    downloads=qa/'downloads';downloads.mkdir(exist_ok=True)
    app=Path(args.app).resolve()
    launcher=qa/'firefox-native-host'
    host=str(app/'Contents/MacOS/IDMBrowserHost')
    launcher.write_text('#!'+sys.executable+'\nimport os,sys,json\nopen('+repr(str(qa/'host-arguments.json'))+',"w").write(json.dumps(sys.argv))\nos.execv('+repr(host)+', ['+repr(host)+', "--bridge-config", '+repr(str(qa/'browser-bridge.json'))+', "--app", '+repr(str(app))+']+sys.argv[1:])\n');launcher.chmod(0o700)
    host_name='local.haseebheaven.idmmac.test'
    manifest=Path.home()/'Library/Application Support/Mozilla/NativeMessagingHosts'/(host_name+'.json')
    if manifest.exists():raise RuntimeError('Refusing to overwrite existing QA native registration')
    manifest.parent.mkdir(parents=True,exist_ok=True)
    manifest.write_text(json.dumps({'name':host_name,'description':'Isolated IDM browser QA','path':str(launcher),'type':'stdio','allowed_extensions':['idm-mac@haseeb-heaven']}))
    extension=prepare_extension(args.extension, qa)
    archive=qa/'firefox-extension.xpi'
    with zipfile.ZipFile(archive,'w') as bundle:
        for path in extension.rglob('*'):
            if path.is_file():bundle.write(path,path.relative_to(extension))
    with socket.socket() as probe:probe.bind(('127.0.0.1',0));port=probe.getsockname()[1]
    processes=[];driver=WebDriver(port);report={'browser':'Firefox','checks':[]}
    try:
        processes.append(subprocess.Popen([str(app/'Contents/MacOS/IDMMac'),'--browser-qa',str(qa)],stdout=(qa/'app.stdout').open('w'),stderr=(qa/'app.stderr').open('w')))
        processes.append(subprocess.Popen([args.geckodriver,'--allow-system-access','--port',str(port)],stdout=(qa/'geckodriver.stdout').open('w'),stderr=(qa/'geckodriver.stderr').open('w')))
        time.sleep(2)
        profile=qa/'firefox-profile';profile.mkdir(exist_ok=True)
        report['capabilities']=driver.start(args.firefox,profile,archive)
        with Fixture(support_ranges=args.resumable_fixture) as fixture:
            driver.navigate(fixture.url)
            driver.evaluate('fetch("/cookie").then(r=>r.text())')
            blob=driver.evaluate('fixtureBlobURL');expired=driver.evaluate('expiredBlobURL')
            new_tab=driver.request('POST',driver.path('/window/new'),{'type':'tab'})
            driver.request('POST',driver.path('/window'),{'handle':new_tab['handle']})
            driver.navigate('moz-extension://f8aa3891-ce0f-4d54-87c7-c5cc73dc27a1/qa.html')
            driver.grant('#grant')
            time.sleep(1)
            tab_id=driver.evaluate('browser.tabs.query({}).then(t=>t.find(x=>x.url?.startsWith('+json.dumps(fixture.url)+')).id)')
            def check(name,action,download=False):
                previous=set(downloads.rglob('*'))
                result=driver.evaluate('IDM_QA('+json.dumps(action)+')')
                if isinstance(result,dict) and result.get('error'):raise AssertionError(result)
                item={'name':name,'response':result}
                if download:item.update(files=[str(p) for p in wait_files(downloads,previous,int(download))],sha256=SHA256)
                report['checks'].append(item)
            check('native-ping',{'action':'ping'})
            check('http-download',{'action':'download','tabID':tab_id,'links':[{'url':fixture.url+'/file.bin'}]},True)
            driver.grant('#grant-session')
            driver.evaluate('IDM_QA_SETTINGS({session:true})')
            check('cookie-protected-download',{'action':'download','tabID':tab_id,'links':[{'url':fixture.url+'/protected.bin'}]},True)
            driver.evaluate('IDM_QA_SETTINGS({session:false})')
            check('batch-dedup',{'action':'download','tabID':tab_id,'links':[{'url':fixture.url+'/second.bin'},{'url':fixture.url+'/third.bin'},{'url':fixture.url+'/second.bin'}]},2)
            collected=driver.evaluate('IDM_QA('+json.dumps({'action':'collect','tabID':tab_id,'kind':'all'})+')')
            if not any(x['url'].startswith('blob:') for x in collected):raise AssertionError('Fixture Blob link missing')
            check('mixed-http-blob-links',{'action':'download','tabID':tab_id,'links':collected},2)
            check('live-blob',{'action':'blob','tabID':tab_id,'url':blob,'filename':'blob.bin'},True)
            result=driver.evaluate('IDM_QA('+json.dumps({'action':'blob','tabID':tab_id,'url':expired,'filename':'expired.bin'})+')')
            if not result.get('error'):raise AssertionError('Expired blob did not return an error')
            report['checks'].append({'name':'expired-blob','response':result})
            check('media-selection',{'action':'collect','tabID':tab_id,'kind':'media'})
            # The registered Firefox context-menu callback opens the real UI.
            qa_handle=driver.request('GET',driver.path('/window'))
            driver.request('POST',driver.path('/window'),{'handle':next(h for h in driver.request('GET',driver.path('/window/handles')) if h!=qa_handle)})
            driver.evaluate('(()=>{const mediaBlob=document.createElement("audio");mediaBlob.src=fixtureBlobURL;document.body.append(mediaBlob)})()')
            driver.request('POST',driver.path('/window'),{'handle':qa_handle})
            previous=set(downloads.rglob('*'));handles=set(driver.request('GET',driver.path('/window/handles')))
            driver.evaluate('browser.runtime.getBackgroundPage().then(bg=>browser.tabs.get('+str(tab_id)+').then(tab=>bg.contextMenuClicked({menuItemId:"media"},tab)))')
            deadline=time.monotonic()+15
            while not (new_handles:=set(driver.request('GET',driver.path('/window/handles')))-handles):
                if time.monotonic()>deadline:raise TimeoutError('Media context selector tab not opened')
                time.sleep(.1)
            driver.request('POST',driver.path('/window'),{'handle':new_handles.pop()})
            driver.request('POST',driver.path('/window/rect'),{'width':1024,'height':800})
            report['mediaInitialViewport']=driver.evaluate('({url:location.href,width:innerWidth,height:innerHeight,visibility:document.visibilityState})')
            activated=driver.evaluate('browser.tabs.getCurrent().then(tab=>tab?browser.tabs.update(tab.id,{active:true}).then(()=>browser.windows.update(tab.windowId,{focused:true,state:"normal"})):Promise.reject(new Error("Selector is not a browser tab")))')
            if isinstance(activated,dict) and activated.get('error'):raise AssertionError(activated)
            viewport_deadline=time.monotonic()+10
            while not driver.evaluate('innerWidth>0 && innerHeight>0'):
                if time.monotonic()>viewport_deadline:raise TimeoutError('Firefox selector browsing context has zero viewport')
                time.sleep(.1)
            while driver.evaluate('document.querySelector("#choices")?.options.length')!=3:
                if time.monotonic()>deadline:raise TimeoutError('Media selector did not retain HTTP and Blob choices')
                time.sleep(.1)
            if set(downloads.rglob('*'))!=previous:raise AssertionError('Media selector queued downloads before selection')
            driver.evaluate('document.querySelector("#choices").value="0"')
            try:driver.click('#chosen')
            except RuntimeError:
                report['mediaViewportDiagnostic']=driver.evaluate('({width:innerWidth,height:innerHeight,scrollY,button:document.querySelector("#chosen").getBoundingClientRect().toJSON(),body:document.body.getBoundingClientRect().toJSON(),visibility:getComputedStyle(document.querySelector("#chosen")).visibility})')
                raise
            http_file=wait_files(downloads,previous,1)[0];previous=set(downloads.rglob('*'))
            driver.evaluate('(()=>{const choices=document.querySelector("#choices");choices.value=[...choices.options].find(x=>x.textContent.startsWith("blob:")).value})()');driver.click('#chosen')
            try:blob_file=wait_files(downloads,previous,1)[0]
            except TimeoutError:
                report['mediaDiagnostic']=driver.evaluate('document.querySelector("#status").textContent')
                raise
            report['checks'].append({'name':'media-context-menu-choice-http-and-blob','files':[str(http_file),str(blob_file)],'sha256':SHA256})
            driver.request('DELETE',driver.path('/window'));driver.request('POST',driver.path('/window'),{'handle':qa_handle})
            driver.evaluate('IDM_QA_SETTINGS({capture:true,session:false})')
            previous=set(downloads.rglob('*'))
            captured_id=driver.evaluate('browser.downloads.download({url:'+json.dumps(fixture.url+'/capture.bin')+',saveAs:false})')
            captured_file=wait_file(downloads,previous)
            captured=wait_download_state(driver.evaluate,captured_id,'interrupted','browser')
            if captured.get('state')!='interrupted' or captured.get('error')!='USER_CANCELED':raise AssertionError(captured)
            report['checks'].append({'name':'download-interception','browserState':captured,'file':str(captured_file),'sha256':SHA256})
            hidden=manifest.with_suffix('.disabled');manifest.rename(hidden)
            try:
                browser_downloads=qa/'browser-downloads'
                previous=set(browser_downloads.rglob('*'))
                fallback_id=driver.evaluate('browser.downloads.download({url:'+json.dumps(fixture.url+'/fallback.bin')+',saveAs:false})')
                try:fallback_file=wait_file(browser_downloads,previous,native=False)
                except TimeoutError:
                    report['fallbackDiagnostic']=driver.evaluate('browser.downloads.search({id:'+str(fallback_id)+'}).then(x=>x[0])')
                    report['extensionStatus']=driver.evaluate('IDM_QA({action:"status"})')
                    raise
                deadline=time.monotonic()+10
                while True:
                    fallback_items=driver.evaluate('browser.downloads.search({}).then(items=>items.filter(x=>x.url==='+json.dumps(fixture.url+'/fallback.bin')+'))')
                    complete=[item for item in fallback_items if item.get('state')=='complete']
                    if len(complete)==1 and len(fallback_items)<=2:break
                    if time.monotonic()>deadline:raise AssertionError(fallback_items)
                    time.sleep(.1)
                original=next(item for item in fallback_items if item['id']==fallback_id)
                report['checks'].append({'name':'host-failure-preserves-browser-download','browserState':complete[0],'originalState':original,'file':str(fallback_file),'sha256':SHA256})
            finally:hidden.rename(manifest)

    except Exception as error:
        report['failure']=str(error);raise
    finally:
        try:driver.close()
        except Exception:pass
        for process in reversed(processes):
            process.terminate()
            try:process.wait(timeout=10)
            except subprocess.TimeoutExpired:process.kill();process.wait()
        manifest.unlink(missing_ok=True)
        report['nativeCompletedJobs']=[{'filename':path.name,'state':'completed','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size} for path in sorted(completed_native_destinations(downloads)) if path.is_file()]
        (qa/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

def run_safari(args):
    """Execute bookmarklet in one owned Safari window; keep user settings intact."""
    qa=Path(args.directory).resolve();qa.mkdir(parents=True,exist_ok=True)
    if (qa/'browser-bridge.json').exists():raise RuntimeError('Use a fresh QA directory')
    downloads=qa/'downloads';downloads.mkdir(exist_ok=True)
    app=Path(args.app).resolve()
    process=subprocess.Popen([str(app/'Contents/MacOS/IDMMac'),'--browser-qa',str(qa)],stdout=(qa/'app.stdout').open('w'),stderr=(qa/'app.stderr').open('w'))
    window=None;report={'browser':'Safari','checks':[]}
    try:
        time.sleep(2)
        with Fixture(support_ranges=args.resumable_fixture) as fixture:
            result=subprocess.run(['osascript','-e','on run argv\ntell application "Safari"\nmake new document with properties {URL:item 1 of argv}\nreturn id of front window\nend tell\nend run',fixture.url],check=True,capture_output=True,text=True)
            window=result.stdout.strip();time.sleep(1)
            bookmarklet=Path(args.bookmarklet).read_text().removeprefix('javascript:').strip()
            script="""const range=document.createRange(); range.selectNode(document.querySelector('a[href="/file.bin"]')); const selection=getSelection();selection.removeAllRanges();selection.addRange(range);"""+bookmarklet
            result=subprocess.run(['osascript','-e','on run argv\ntell application "Safari" to do JavaScript (item 2 of argv) in current tab of window id (item 1 of argv as integer)\nend run',window,script],capture_output=True,text=True)
            if result.returncode:
                report['limitations']=[result.stderr.strip()]
                handoff=fixture.server.handoff_url
                navigation=subprocess.run(['osascript','-e','on run argv\ntell application "Safari" to set URL of current tab of window id (item 1 of argv as integer) to (item 2 of argv)\nend run',window,handoff],capture_output=True,text=True)
                if navigation.returncode:report['limitations'].append(navigation.stderr.strip());return report
                report['checks'].append({'name':'actual-safari-url-scheme-navigation'})
            else:report['checks'].append({'name':'actual-bookmarklet-executed'})
            time.sleep(1)
            probe=subprocess.run(['osascript','-e','on run argv\ntell application "System Events"\nset p to first process whose unix id is (item 1 of argv as integer)\ntell p\nrepeat with w in windows\nrepeat with e in entire contents of w\ntry\nif role of e is "AXButton" and name of e is "Save" then return true\nend try\nend repeat\nend repeat\nend tell\nend tell\nreturn false\nend run',str(process.pid)],capture_output=True,text=True)
            if probe.returncode or probe.stdout.strip()!='true':
                report.setdefault('limitations',[]).append('Owned native Save dialog was not available through accessibility; destination approval untested')
                return report
            review='on run argv\ntell application "System Events"\nset p to first process whose unix id is (item 1 of argv as integer)\ntell p\nset frontmost to true\nkeystroke "g" using {command down, shift down}\ndelay 0.5\nkeystroke (item 2 of argv)\nkey code 36\ndelay 0.5\nkey code 36\nend tell\nend tell\nend run'
            subprocess.run(['osascript','-e',review,str(process.pid),str(downloads)],check=True,capture_output=True)
            downloaded=wait_file(downloads,set())
            report['checks'].append({'name':'reviewed-url-scheme-handoff','file':str(downloaded),'sha256':SHA256})
    except Exception as error:
        report['failure']=str(error);raise
    finally:
        if window:
            subprocess.run(['osascript','-e','on run argv\ntell application "Safari" to close window id (item 1 of argv as integer)\nend run',window],capture_output=True)
        process.terminate()
        try:process.wait(timeout=10)
        except subprocess.TimeoutExpired:process.kill();process.wait()
        report['nativeCompletedJobs']=[{'filename':path.name,'state':'completed','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size} for path in sorted(completed_native_destinations(downloads)) if path.is_file()]
        (qa/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--app',required=True)
    parser.add_argument('--extension')
    parser.add_argument('--chrome')
    parser.add_argument('--firefox')
    parser.add_argument('--geckodriver')
    parser.add_argument('--safari',action='store_true')
    parser.add_argument('--bookmarklet')
    parser.add_argument('--resumable-fixture',action='store_true')
    parser.add_argument('--directory',required=True)
    args=parser.parse_args()
    print(json.dumps(run_safari(args) if args.safari else run_firefox(args) if args.firefox else run(args),indent=2))
