"""Small synchronous stdio MCP client for the locally installed RE servers."""
import json, subprocess, time, select

class MCP:
    def __init__(self, command, env=None):
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open("build/mcp-stderr.log", "a"), env=env, bufsize=0)
        self.sequence = 0
        self.buffer = b""
        self.request("initialize", {"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"idm-re","version":"1"}})
        self.process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
    def request(self, method, params, timeout=1200):
        self.sequence += 1
        number = self.sequence
        self.process.stdin.write((json.dumps({"jsonrpc":"2.0","id":number,"method":method,"params":params})+"\n").encode())
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            if b"\n" not in self.buffer:
                ready,_,_=select.select([self.process.stdout],[],[],1)
                if not ready: continue
                chunk=self.process.stdout.read(1)
                if not chunk: raise RuntimeError("MCP server exited")
                self.buffer+=chunk
                continue
            line,self.buffer=self.buffer.split(b"\n",1)
            try: result=json.loads(line)
            except (ValueError,UnicodeDecodeError): continue
            if result.get("id")==number:
                if "error" in result: raise RuntimeError(str(result["error"]))
                return result["result"]
        raise TimeoutError(method)
    def call(self,name,arguments):
        result=self.request("tools/call",{"name":name,"arguments":arguments})
        if result.get("isError"): raise RuntimeError(str(result))
        return result
    def close(self):
        self.process.terminate()
        self.process.wait(timeout=15)
