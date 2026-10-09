/* Independently authored WebExtension native handoff. */
if (typeof importScripts === 'function') importScripts('config.js', 'core.js');
const api = globalThis.browser || chrome;
let latestStatus = 'Ready', blobSession = null;
const settings = () => api.storage.local.get({capture:false,session:false});
function report(message) { latestStatus = String(message); }
function nativeRequest(request) {
  return new Promise((resolve,reject) => {
    const port = api.runtime.connectNative(IDM_CONFIG.hostName);
    const timer = setTimeout(() => { port.disconnect(); reject(new Error('Native app did not respond')); }, 120000);
    port.onMessage.addListener(response => { clearTimeout(timer); port.disconnect(); try { if (response.id !== request.id) throw new Error('Native response identity mismatch'); resolve(IDMCore.nativeResponse(response)); } catch(e) { reject(e); } });
    port.onDisconnect.addListener(() => { clearTimeout(timer); reject(new Error(api.runtime.lastError?.message || 'Native host disconnected. Install the native host from Browser Integrations in the app.')); });
    port.postMessage(request);
  });
}
async function sessionLink(link, tab) {
  const result = IDMCore.validateLink({...link,pageURL:tab?.url || link.pageURL});
  if ((await settings()).session) {
    const origin = IDMCore.permissionPattern(result.url);
    if (!await api.permissions.contains({permissions:['cookies'],origins:[origin]})) throw new Error('Allow cookie and site access using the popup first');
    const stores = tab?.cookieStoreId ? [] : await api.cookies.getAllCookieStores();
    const details = {url:result.url,storeId:IDMCore.cookieStore(tab,stores)};
    const cookies = await api.cookies.getAll(details);
    result.headers = {'User-Agent':navigator.userAgent};
    if (cookies.length) result.headers.Cookie = cookies.map(c => `${c.name}=${c.value}`).join('; ');
    if (result.pageURL) result.headers.Referer = new URL(result.pageURL).origin + '/';
  }
  return result;
}
async function download(links,tab) { const clean = IDMCore.httpLinks(links); if (!clean.length) throw new Error('No HTTP or HTTPS links found'); const enriched = await Promise.all(clean.map(l => sessionLink(l,tab))); const response = await nativeRequest({id:crypto.randomUUID(),op:enriched.length === 1 ? 'download':'batch',links:enriched}); report(response.message || response.status); return response; }
function collectDocument(kind) {
  const selection = getSelection();
  const nodes = kind === 'media' ? [...document.querySelectorAll('video,audio,video source,audio source')] : [...document.querySelectorAll('a[href]')].filter(a => kind !== 'selection' || (selection && [...Array(selection.rangeCount)].some((_,i) => selection.getRangeAt(i).intersectsNode(a))));
  return nodes.map(n => ({url:n.currentSrc || n.src || n.href,filename:n.download || undefined,pageURL:location.href})).filter(l => /^(https?:|blob:)/.test(l.url)).slice(0,200);
}
async function inject(tabId,func,args) {
  if (api.scripting) return (await api.scripting.executeScript({target:{tabId},func,args}))[0]?.result;
  return (await api.tabs.executeScript(tabId,{code:`(${func.toString()})(...${JSON.stringify(args)})`}))[0];
}
async function collect(tab,kind) { return inject(tab.id,collectDocument,[kind]); }
async function blobReader(url,streamID) {
  const api = globalThis.browser || chrome;
  const send = message => api.runtime.sendMessage({action:'blobData',streamID,...message});
  let reader;
  try { const response = await fetch(url); if (!response.ok || !response.body) throw new Error('Blob cannot be read (expired, MediaSource or protected media)'); reader = response.body.getReader(); let sequence = 0,totalBytes = 0; for (;;) { const {done,value} = await reader.read(); if (done) break; for (let offset = 0; offset < value.length; offset += 131072) { const chunk = value.subarray(offset,offset+131072); let binary = ''; for (const byte of chunk) binary += String.fromCharCode(byte); const ack = await send({op:'blobChunk',sequence:sequence++,data:btoa(binary)}); if (ack.error) throw new Error(ack.error); totalBytes += chunk.length; } } const ack = await send({op:'blobFinish',totalBytes}); if (ack.error) throw new Error(ack.error); return ack; }
  catch(e) { await send({op:'blobAbort'}).catch(() => {}); return {error:`Browser Blob import failed: ${e.message}`}; }
  finally { await reader?.cancel().catch(() => {}); }
}
async function blob(tab,url,filename) {
  if (blobSession) throw new Error('Another Blob import is active');
  if (!/^https?:/.test(tab.url) || !url.startsWith('blob:') || new URL(url.slice(5)).origin !== new URL(tab.url).origin) throw new Error('Blob must belong to the original HTTP or HTTPS tab');
  const port = api.runtime.connectNative(IDM_CONFIG.hostName); let pending = null;
  port.onMessage.addListener(r => { if (!pending || r.id !== pending.id) return; const p = pending; pending = null; clearTimeout(p.timer); try { p.resolve(IDMCore.nativeResponse(r)); } catch(e) { p.reject(e); } });
  port.onDisconnect.addListener(() => { if (pending) { clearTimeout(pending.timer); pending.reject(new Error('Native host disconnected during Blob import')); pending = null; } });
  const request = message => new Promise((resolve,reject) => { const id = crypto.randomUUID(); pending = {id,resolve,reject,timer:setTimeout(() => { pending = null; reject(new Error('Blob response timed out')); },120000)}; port.postMessage({id,...message}); });
  const streamID = crypto.randomUUID(); blobSession = {tabID:tab.id,streamID,request};
  try { const accepted = await request({op:'blobBegin',streamID,links:[{url,filename:filename || 'browser-import.bin',pageURL:tab.url}]}); if (accepted.status !== 'accepted') return accepted; const result = await inject(tab.id,blobReader,[url,streamID]); if (!result) throw new Error('Source tab closed or Blob unavailable'); if (result.error) throw new Error(result.error); report(result.status || 'complete'); return result; }
  catch(e) { await request({op:'blobAbort',streamID}).catch(() => {}); throw e; }
  finally { blobSession = null; port.disconnect(); }
}
async function handle(message,sender) {
  if (message.action === 'blobData') { if (!blobSession || sender.tab?.id !== blobSession.tabID || message.streamID !== blobSession.streamID || !['blobChunk','blobFinish','blobAbort'].includes(message.op)) throw new Error('Unauthorized Blob message'); return blobSession.request({op:message.op,streamID:message.streamID,sequence:message.sequence,data:message.data,totalBytes:message.totalBytes}); }
  if (sender.id !== api.runtime.id || !sender.url?.startsWith(api.runtime.getURL(''))) throw new Error('Only extension pages may request downloads');
  if (message.action === 'status') return {status:latestStatus,...await settings()};
  if (message.action === 'ping') return nativeRequest({id:crypto.randomUUID(),op:'ping'});
  const tab = message.tabID ? await api.tabs.get(message.tabID) : (await api.tabs.query({active:true,currentWindow:true}))[0];
  if (message.action === 'collect') return collect(tab,message.kind || 'all');
  if (message.action === 'blob') return blob(tab,message.url,message.filename);
  if (message.action === 'download') return download(message.links || [{url:tab.url}],tab);
  throw new Error('Unknown extension action');
}
api.runtime.onMessage.addListener((message,sender,sendResponse) => { const task = handle(message,sender).catch(e => { report(e.message); return {error:e.message}; }); if (globalThis.browser) return task; task.then(sendResponse); return true; });
api.runtime.onInstalled.addListener(() => { for (const [id,title,contexts] of [['link','Download link',['link']],['selection','Download selected links',['selection']],['all','Download all links',['page']],['media','Choose direct video/audio files',['video','audio','page']]]) api.contextMenus.create({id,title,contexts}); });
api.contextMenus.onClicked.addListener(async (info,tab) => { try { if (info.menuItemId === 'link') await download([{url:info.linkUrl}],tab); else { const items = await collect(tab,info.menuItemId); await download(items,tab); } } catch(e) { report(e.message); } });
api.downloads.onCreated.addListener(async item => { if (!(await settings()).capture) return; try { await IDMCore.capture(item,api.downloads,link => download([link],null)); } catch(e) { report(e.message); } });
