const api = globalThis.browser || chrome;
window.IDM_QA = async message => { const result = await api.runtime.sendMessage(message); document.getElementById('result').textContent = JSON.stringify(result); return result; };
window.IDM_QA_SETTINGS = settings => api.storage.local.set(settings);
document.getElementById('ping').onclick = () => window.IDM_QA({action:'ping'});

document.getElementById('grant').onclick = async () => { const granted = await api.permissions.request({origins:[document.getElementById('origin').value]}); document.getElementById('result').textContent = JSON.stringify({granted}); };

document.getElementById('grant-session').onclick = async () => { const granted = await api.permissions.request({permissions:['cookies'],origins:[document.getElementById('origin').value]}); document.getElementById('result').textContent = JSON.stringify({granted}); };
