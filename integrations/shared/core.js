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
  function nativeResponse(response) { if (!response || !['ready','queued','cancelled','error','accepted','complete'].includes(response.status)) throw new Error('Invalid native response'); if (response.status === 'error') throw new Error(response.message || 'Native request failed'); return response; }
  async function capture(item, api, request) {
    if (!/^https?:\/\//i.test(item.url)) return 'ignored';
    await api.pause(item.id);
    try { const response = nativeResponse(await request({url:item.url,filename:item.filename && item.filename.split(/[\\/]/).pop()})); if (response.status === 'queued') { await api.cancel(item.id); return 'queued'; } await api.resume(item.id); return response.status; }
    catch (error) { await api.resume(item.id); throw error; }
  }
  const core = {MAX_LINKS,CHUNK_BYTES,validateLink,links,nativeResponse,capture};
  root.IDMCore = core; if (typeof module !== 'undefined') module.exports = core;
})(globalThis);
