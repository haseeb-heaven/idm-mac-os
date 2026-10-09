"""Minimal CDP client for an isolated Chrome for Testing process."""
import json
import time
import urllib.request

class CDP:
    def __init__(self, url):
        import websocket
        self.ws = websocket.create_connection(url, timeout=30, suppress_origin=True)
        self.sequence = 0
    def call(self, method, params=None):
        self.sequence += 1
        ident = self.sequence
        self.ws.send(json.dumps({'id':ident,'method':method,'params':params or {}}))
        while True:
            message = json.loads(self.ws.recv())
            if message.get('id') == ident:
                if 'error' in message:
                    raise RuntimeError(message['error'])
                return message.get('result', {})
    def evaluate(self, expression):
        reply = self.call('Runtime.evaluate', {'expression':expression,'awaitPromise':True,'returnByValue':True})
        if 'exceptionDetails' in reply:
            raise RuntimeError(reply['exceptionDetails'])
        return reply.get('result',{}).get('value')
    def close(self):
        self.ws.close()

def targets(port):
    with urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list') as response:
        return json.load(response)

def wait_target(port, fragment, timeout=30):
    deadline = time.monotonic()+timeout
    while time.monotonic()<deadline:
        for target in targets(port):
            if fragment in target.get('url','') and 'webSocketDebuggerUrl' in target:
                return target
        time.sleep(.2)
    raise TimeoutError('Browser target absent: '+fragment)

class WebDriver:
    """W3C driver client with Firefox temporary extension support."""
    def __init__(self, port):
        self.base=f'http://127.0.0.1:{port}'
        self.session=None
    def request(self, method, path, body=None):
        data=None if body is None else json.dumps(body).encode()
        req=urllib.request.Request(self.base+path,data=data,method=method,headers={'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(req,timeout=150) as response: value=json.load(response)['value']
        except urllib.error.HTTPError as error:
            raise RuntimeError(error.read().decode()) from error
        return value
    def start(self,binary,profile,extension):
        download_directory=profile.parent/'browser-downloads'
        download_directory.mkdir(exist_ok=True)
        value=self.request('POST','/session',{'capabilities':{'alwaysMatch':{'browserName':'firefox','moz:firefoxOptions':{'binary':binary,'args':['-profile',str(profile)],'prefs':{'extensions.webextensions.uuids':json.dumps({'macdownloadmanager@haseeb-heaven':'f8aa3891-ce0f-4d54-87c7-c5cc73dc27a1'}),'browser.shell.checkDefaultBrowser':False,'browser.download.folderList':2,'browser.download.dir':str(download_directory),'browser.download.useDownloadDir':True,'browser.download.always_ask_before_handling_new_types':False}}}}})
        self.session=value['sessionId']
        self.request('POST',self.path('/moz/addon/install'),{'path':str(extension),'temporary':True})
        return value
    def path(self,suffix):return '/session/'+self.session+suffix
    def navigate(self,url):
        if url.startswith('moz-extension:'):
            self.request('POST',self.path('/moz/context'),{'context':'chrome'})
            try:
                self.request('POST',self.path('/execute/sync'),{'script':'gBrowser.selectedBrowser.loadURI(Services.io.newURI(arguments[0]), {triggeringPrincipal:Services.scriptSecurityManager.getSystemPrincipal()});','args':[url]})
            finally:self.request('POST',self.path('/moz/context'),{'context':'content'})
            time.sleep(1)
            return None
        return self.request('POST',self.path('/url'),{'url':url})
    def evaluate(self,expression):
        return self.request('POST',self.path('/execute/async'),{'script':'const done=arguments[arguments.length-1]; Promise.resolve().then(()=>('+expression+')).then(done,e=>done({error:e.message}));','args':[]})
    def click(self,selector):
        element=self.request('POST',self.path('/element'),{'using':'css selector','value':selector})
        ident=element['element-6066-11e4-a52e-4f735466cecf']
        return self.request('POST',self.path('/element/'+ident+'/click'),{})
    def grant(self,selector='#grant'):
        self.click(selector)
        time.sleep(.5)
        self.request('POST',self.path('/moz/context'),{'context':'chrome'})
        try:self.request('POST',self.path('/execute/sync'),{'script':'document.querySelector("#addon-webext-permissions-notification .popup-notification-primary-button").click();','args':[]})
        finally:self.request('POST',self.path('/moz/context'),{'context':'content'})
        time.sleep(.5)
    def close(self):
        if self.session:self.request('DELETE',self.path(''))
