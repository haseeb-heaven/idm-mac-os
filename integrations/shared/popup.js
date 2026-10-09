const api = globalThis.browser || chrome;
const status = document.getElementById('status'); let media = []; let cachedTab = null;
const parameters = new URLSearchParams(location.search);
const sourceTabID = Number(parameters.get('tabID'));
const ready = (Number.isInteger(sourceTabID) && sourceTabID > 0 ? api.tabs.get(sourceTabID) : api.tabs.query({active:true,currentWindow:true}).then(tabs => tabs[0])).then(tab => { cachedTab = tab; return tab; }).catch(e => { status.textContent = e.message; throw e; });
async function send(message) { try { if (parameters.has('tabID') && !['ping','status'].includes(message.action)) { const tab = await ready; message = {...message,tabID:tab.id}; } const response = await api.runtime.sendMessage(message); if (response.error) throw new Error(response.error); status.textContent = response.message || response.status || 'Ready'; return response; } catch(e) { status.textContent = e.message; throw e; } }
document.getElementById('ping').onclick = () => send({action:'ping'}).catch(() => {});
document.getElementById('copy').onclick = () => navigator.clipboard.writeText(status.textContent).catch(e => {status.textContent = e.message;});
document.getElementById('capture').onchange = e => api.storage.local.set({capture:e.target.checked});
document.getElementById('session').onchange = async e => { try { if (e.target.checked) { if (!cachedTab) throw new Error('Current tab is loading; reopen the popup'); const origin = IDMCore.permissionPattern(cachedTab.url); const granted = await api.permissions.request({permissions:['cookies'],origins:[origin]}); if (!granted) throw new Error('Cookie/site permission declined'); } await api.storage.local.set({session:e.target.checked}); } catch(error) { e.target.checked = false; await api.storage.local.set({session:false}); status.textContent = error.message; } };
document.getElementById('current').onclick = () => send({action:'download'}).catch(() => {});
for (const kind of ['selection','all']) document.getElementById(kind).onclick = async () => { try { const links = await send({action:'collect',kind}); await send({action:'download',links}); } catch (_) {} };
document.getElementById('media').onclick = async () => { try { media = await send({action:'collect',kind:'media'}); document.getElementById('choices').replaceChildren(...media.map((link,i) => { const option = document.createElement('option'); option.value = i; option.textContent = link.url; return option; })); status.textContent = media.length ? 'Choose a direct file. Protected or MediaSource streams may fail.' : 'No direct video/audio files found'; } catch (_) {} };
document.getElementById('chosen').onclick = async () => { const link = media[document.getElementById('choices').value]; if (!link) return; try { await send(link.url.startsWith('blob:') ? {action:'blob',url:link.url} : {action:'download',links:[link]}); } catch (_) {} };
send({action:'status'}).then(s => { document.getElementById('capture').checked = s.capture; document.getElementById('session').checked = s.session; }).catch(() => {});

if (parameters.get('media') === '1') ready.then(() => document.getElementById('media').click()).catch(() => {});
