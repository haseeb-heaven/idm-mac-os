import os,json
from pathlib import Path
from mcp_client import MCP
root=Path(__file__).resolve().parent.parent
os.chdir(root)
env=dict(os.environ,JAVA_HOME='/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home',GHIDRA_INSTALL_DIR='/opt/homebrew/opt/ghidra/libexec')
c=MCP([str(root/'.venv/bin/ghidra-headless-mcp')],env=env)
def save(name,result):
 (root/'analysis/raw'/f'{name}.json').write_text(json.dumps(result,indent=2));return result.get('structuredContent',{})
try:
 save('ghidra-info',c.call('ghidra.info',{}))
 opened=save('ghidra-application',c.call('program.open',{'path':str(root/'samples/IDMan.exe'),'project_location':str(root/'analysis/ghidra'),'project_name':'IDM','update_analysis':True,'read_only':False}))
 session=opened['session_id'];save('ghidra-save',c.call('program.save',{'session_id':session}));print('Analyzed',session,flush=True)
 save('ghidra-imports',c.call('external.imports.list',{'session_id':session,'limit':1000}))
 for text in ['Range:','Content-Range','Accept-Ranges','If-Range','ETag','Last-Modified','Scheduler','Speed Limiter']:
  result=save('ghidra-search-'+text.replace(':','').replace(' ','-'),c.call('search.text',{'session_id':session,'text':text,'limit':20}))
  print(text,str(result)[:300],flush=True)
 save('ghidra-functions',c.call('function.list',{'session_id':session,'limit':100}))
 # Inspect references to actual protocol strings, then decompile containing callers.
 for text in ['Range','Content-Range','If-Range']:
  file=root/'analysis/raw'/f'ghidra-search-{text}.json'
  if not file.exists(): continue
  content=json.loads(file.read_text()).get('structuredContent',{})
  for match in content.get('items',[])[:3]:
   addr=match.get('address')
   if not addr:continue
   refs=save('ghidra-xrefs-'+str(addr),c.call('reference.to',{'session_id':session,'address':addr,'limit':20}))
   for ref in refs.get('items',[])[:2]:
    source=ref.get('from_address') or ref.get('from')
    if not source:continue
    function=save('ghidra-function-'+str(source),c.call('function.at',{'session_id':session,'address':source}))
    start=function.get('entry') or function.get('entry_point') or function.get('address')
    if start:save('ghidra-decompile-'+str(start),c.call('decomp.function',{'session_id':session,'function_start':start}))
finally:c.close()
