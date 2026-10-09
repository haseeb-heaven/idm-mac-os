import {test} from 'node:test'; import assert from 'node:assert/strict'; import '../../integrations/shared/core.js'; const core = globalThis.IDMCore;
test('HTTP validation, sanitization and deduplication',() => { assert.equal(core.links([{url:'https://a.test/f'},{url:'https://a.test/f'}]).length,1); assert.equal(core.validateLink({url:'https://a.test',filename:'a/b'}).filename,'a_b'); for(const url of ['file:///tmp/a','javascript:alert(1)','https://u:p@a.test']) assert.throws(()=>core.validateLink({url})); assert.throws(()=>core.validateLink({url:'https://a.test',headers:{Cookie:'a\r\nb'}})); assert.equal(core.links(Array.from({length:201},(_,i)=>({url:`https://a.test/${i}`}))).length,200); });
for (const status of ['queued','cancelled','error','disconnect']) test(`capture ${status} preserves correct browser state`,async()=> { const calls=[]; const api=Object.fromEntries(['pause','resume','cancel'].map(name=>[name,async()=>calls.push(name)])); const request=async()=> {if(status==='disconnect')throw new Error('lost'); return {status,message:'declined'};}; if(['error','disconnect'].includes(status)) await assert.rejects(core.capture({id:1,url:'https://a.test/f'},api,request)); else await core.capture({id:1,url:'https://a.test/f'},api,request); assert.deepEqual(calls,status==='queued'?['pause','cancel']:['pause','resume']); });
test('capture ignores browser local files',async()=>assert.equal(await core.capture({url:'blob:https://a.test/id'}, {},()=>{}),'ignored'));
test('native response errors are visible',()=> { assert.throws(()=>core.nativeResponse({status:'error',message:'Host missing'}),/Host missing/); assert.throws(()=>core.nativeResponse({status:'wrong'})); });

test('batch deduplication preserves first filename and source page',()=> { const result = core.links([{url:'https://a.test/f',filename:'first',pageURL:'https://a.test/page'},{url:'https://a.test/f',filename:'second'}]); assert.deepEqual(result,[{url:'https://a.test/f',filename:'first',pageURL:'https://a.test/page'}]); });

test('mixed HTTP and Blob collections retain HTTP batch',()=>assert.deepEqual(core.httpLinks([{url:'blob:https://a.test/id'},{url:'https://a.test/f'}]),[{url:'https://a.test/f'}]));
test('site permission patterns omit TCP port',()=> {assert.equal(core.permissionPattern('http://127.0.0.1:5432/path'),'http://127.0.0.1/*'); assert.equal(core.permissionPattern('https://example.com:8443/f'),'https://example.com/*');});

import {execFileSync} from 'node:child_process';
import {readFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import vm from 'node:vm';
test('universal bookmarklet hands off ordinary HTTP without randomUUID',()=> {
 const directory = mkdtempSync(tmpdir() + '/idm-bookmarklet-');
 try {
  execFileSync('python3',[new URL('../../scripts/build_extensions.py',import.meta.url).pathname,'--output',directory]);
  const source = readFileSync(directory + '/bookmarklet.txt','utf8').replace(/^javascript:/,'');
  const location = {href:'http://example.test/file'};
  const context = {location,getSelection:()=>null,document:{querySelectorAll:()=>[]},prompt:()=>location.href,crypto:{getRandomValues:bytes=>{bytes.fill(9);return bytes;}},TextEncoder,Uint8Array,btoa:value=>Buffer.from(value,'binary').toString('base64'),alert:()=>assert.fail('unexpected alert')};
  vm.runInNewContext(source,context);
  const url = new URL(location.href); const payload = JSON.parse(Buffer.from(url.searchParams.get('payload'),'base64url').toString());
  assert.equal(url.protocol,'idm-mac:'); assert.match(payload.id,/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/); assert.equal(payload.links[0].url,'http://example.test/file');
 } finally {rmSync(directory,{recursive:true,force:true});}
});

test('cookies bind to identified tab container and incognito store',()=> { const stores=[{id:'default',tabIds:[1]},{id:'incognito',tabIds:[2]}]; assert.equal(core.cookieStore({id:2,incognito:true},stores),'incognito'); assert.equal(core.cookieStore({id:3,cookieStoreId:'firefox-container-1'},[]),'firefox-container-1'); assert.throws(()=>core.cookieStore(null,stores),/identified browser tab/); assert.throws(()=>core.cookieStore({id:99},stores),/Unable to identify/); });

test('ordinary Blob anchor context menu routes to streaming import',()=> { assert.equal(core.linkAction('blob:https://a.test/id'),'blob'); assert.equal(core.linkAction('https://a.test/f'),'download'); });

test('failed native capture recovers once when Firefox resume fails',async()=> {
 const calls=[]; const item={id:4,url:'https://a.test/f',incognito:true,cookieStoreId:'firefox-private'};
 const api={pause:async()=>calls.push('pause'),resume:async()=>{calls.push('resume');throw new Error('cannot resume');},cancel:async()=>calls.push('cancel')};
 const guard=core.recoveryGuard();
 await assert.rejects(core.capture(item,api,async()=>{throw new Error('Host missing');},async original=>{calls.push('recover');assert.equal(original,item);guard.register(original);assert.equal(guard.consume({...original,id:5}),true);assert.equal(guard.consume({...original,id:6}),false);}),/Host missing/);
 assert.deepEqual(calls,['pause','resume','recover']);
});
test('recovery guard preserves browser context and expires',()=> {
 let now=0;const guard=core.recoveryGuard(()=>now);const item={url:'https://a.test/f',incognito:true,cookieStoreId:'container'};
 guard.register(item);assert.equal(guard.consume({...item,incognito:false}),false);assert.equal(guard.consume({...item,cookieStoreId:'other'}),false);assert.equal(guard.consume(item),true);
 guard.register(item);now=30001;assert.equal(guard.consume(item),false);
});
test('cancelled native request attempts resume once then recovery once',async()=> {
 let resumes=0,recoveries=0;await core.capture({id:1,url:'https://a.test/f'},{pause:async()=>{},resume:async()=>{resumes++;throw new Error('cannot resume');}},async()=>({status:'cancelled'}),async()=>{recoveries++;});assert.equal(resumes,1);assert.equal(recoveries,1);
});

test('recovery marker requires owning extension provenance',()=> { const guard=core.recoveryGuard();const item={url:'https://a.test/f',cookieStoreId:'firefox-default'};guard.register(item);assert.equal(guard.consume({...item,byExtensionId:'other'},'owner'),false);assert.equal(guard.consume(item,'owner'),false);assert.equal(guard.ambiguous(item),true);assert.equal(guard.consume({...item,byExtensionId:'owner'},'owner'),true);assert.equal(guard.ambiguous(item),false); });

test('media context menu opens a selector bound to the original tab',async()=> {
 let clicked;const opened=[];const event={addListener:()=>{}};
 const api={runtime:{id:'owner',getURL:path=>'chrome-extension://owner/'+path,onMessage:event,onInstalled:event},contextMenus:{onClicked:{addListener:fn=>{clicked=fn;}}},downloads:{onCreated:event},tabs:{create:async options=>opened.push(options)}};
 vm.runInNewContext(readFileSync(new URL('../../integrations/shared/background.js',import.meta.url),'utf8'),{browser:api,IDMCore:core});
 await clicked({menuItemId:'media'},{id:17,url:'https://a.test/page'});
 assert.deepEqual(JSON.parse(JSON.stringify(opened)),[{url:'chrome-extension://owner/popup.html?media=1&tabID=17'}]);
});
test('media selector sends only chosen HTTP or Blob using original tab',async()=> {
 const nodes=new Map();const node=id=>{if(!nodes.has(id))nodes.set(id,{textContent:'',value:'0',replaceChildren(...children){this.children=children;},click(){return this.onclick?.();}});return nodes.get(id);};
 const calls=[];const media=[{url:'https://a.test/video.mp4'},{url:'blob:https://a.test/id'}];
 const api={tabs:{get:async id=>({id,url:'https://a.test/page'})},runtime:{sendMessage:async message=>{calls.push(message);if(message.action==='collect')return media;if(message.action==='status')return {capture:false,session:false};return {status:'queued'};}}};
 vm.runInNewContext(readFileSync(new URL('../../integrations/shared/popup.js',import.meta.url),'utf8'),{browser:api,IDMCore:core,URLSearchParams,location:{search:'?tabID=17'},document:{getElementById:node,createElement:()=>({})}});
 await node('media').onclick();
 assert.equal(node('choices').children.length,2);
 await node('chosen').onclick();node('choices').value='1';await node('chosen').onclick();
 const transfers=calls.filter(x=>['download','blob'].includes(x.action));
 assert.deepEqual(JSON.parse(JSON.stringify(transfers)),[{action:'download',links:[media[0]],tabID:17},{action:'blob',url:media[1].url,tabID:17}]);
});
