(function(root) {
  const MAX_LINKS = 200, CHUNK_BYTES = 128 * 1024;
  function validateLink(link) {
    const u = new URL(link.url);
    if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password) throw new Error('Only HTTP and HTTPS links without embedded credentials are supported');
    const result = {url:u.href};
    if (link.filename) result.filename = String(link.filename).replace(/[\\/\x00-\x1f]/g, '_').slice(0, 255);
    if (link.pageURL) { const p = new URL(link.pageURL); if (['http:','https:'].includes(p.protocol)) result.pageURL = p.href; }
    if (link.headers) { result.headers = {}; for (const [key,value] of Object.entries(link.headers)) { if (!['Cookie','Referer','User-Agent'].includes(key) || typeof value !== 'string' || /[\r\n\0]/.test(value)) throw new Error('Invalid session header'); result.headers[key] = value; } }
    return result;
  }
  function links(items) { const seen = new Set(); return items.map(validateLink).filter(l => !seen.has(l.url) && seen.add(l.url)).slice(0, MAX_LINKS); }
  function httpLinks(items) { return links(items.filter(link => !String(link.url).startsWith('blob:'))); }
  function permissionPattern(url) { const u = new URL(url); if (!['http:','https:'].includes(u.protocol)) throw new Error('Site access requires HTTP or HTTPS'); return u.protocol + '//' + u.hostname + '/*'; }
  function linkAction(url) { return String(url).startsWith('blob:') ? 'blob' : 'download'; }
  function cookieStore(tab, stores) {
    if (!tab || !Number.isInteger(tab.id)) throw new Error('Cookie sharing requires an identified browser tab; automatic capture resumed');
    if (tab.cookieStoreId) return tab.cookieStoreId;
    const store = stores.find(item => Array.isArray(item.tabIds) && item.tabIds.includes(tab.id));
    if (!store || typeof store.id !== 'string') throw new Error('Unable to identify this tab cookie store; cookie sharing stopped');
    return store.id;
  }
  function nativeResponse(response) { if (!response || !['ready','queued','cancelled','error','accepted','complete'].includes(response.status)) throw new Error('Invalid native response'); if (response.status === 'error') throw new Error(response.message || 'Native request failed'); return response; }
  function recoveryGuard(now = () => Date.now()) {
    const pending = new Map(); let serial = 0;
    const key = item => JSON.stringify([item.url,Boolean(item.incognito),item.cookieStoreId || 'firefox-default']);
    function prune() { for (const [k, entry] of pending) if (entry.expiry <= now()) pending.delete(k); }
    return {register(item) { prune(); if (pending.size >= 32) throw new Error('Too many pending browser recoveries'); const token = ++serial; pending.set(token,{key:key(item),expiry:now()+30000}); return () => pending.delete(token); }, consume(item,extensionID) { prune(); if (item.byExtensionId !== extensionID) return false; const k=key(item); for (const [token,entry] of pending) if (entry.key === k) { pending.delete(token); return true; } return false; }, ambiguous(item) { prune(); return !item.byExtensionId && [...pending.values()].some(entry => entry.key === key(item)); }};
  }
  async function capture(item, api, request, recover) {
    if (!/^https?:\/\//i.test(item.url)) return 'ignored';
    await api.pause(item.id);
    async function resume() { try { await api.resume(item.id); } catch(error) { if (!recover) throw error; await recover(item,error); } }
    let response;
    try { response = nativeResponse(await request({url:item.url,filename:item.filename && item.filename.split(/[\\/]/).pop()})); }
    catch(error) { try { await resume(); } catch(recoveryError) { throw new Error(`${error.message}; browser recovery failed: ${recoveryError.message}`); } throw error; }
    if (response.status === 'queued') { await api.cancel(item.id); return 'queued'; }
    await resume(); return response.status;
  }
  const core = {MAX_LINKS,CHUNK_BYTES,validateLink,links,httpLinks,permissionPattern,linkAction,cookieStore,nativeResponse,recoveryGuard,capture};
  root.IDMCore = core; if (typeof module !== 'undefined') module.exports = core;
})(globalThis);
