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
