import os,json
from pathlib import Path
from mcp_client import MCP
root=Path(__file__).resolve().parent.parent;os.chdir(root)
env=dict(os.environ,JAVA_HOME='/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home',GHIDRA_INSTALL_DIR='/opt/homebrew/opt/ghidra/libexec')
c=MCP([str(root/'.venv/bin/ghidra-headless-mcp')],env=env)
def save(name,result):
 (root/'analysis/raw'/f'{name}.json').write_text(json.dumps(result,indent=2));return result.get('structuredContent',{})
try:
 opened=save('ghidra-reopened',c.call('project.program.open_existing',{'project_location':str(root/'analysis/ghidra'),'project_name':'IDM','program_path':'/IDMan.exe','update_analysis':True,'read_only':False}));session=opened['session_id'];save('ghidra-save',c.call('program.save',{'session_id':session}))
 for address in ['006cf9bc','006cfa00','006cf014','006cf024','006cfaf8']:
  refs=save('ghidra-xrefs-'+address,c.call('reference.to',{'session_id':session,'address':address,'limit':20}))
  print(address,refs,flush=True)
  for ref in refs.get('items',[])[:2]:
   source=ref.get('from_address') or ref.get('from')
   if not source:continue
   f=save('ghidra-function-'+str(source),c.call('function.at',{'session_id':session,'address':source}));print('function',f,flush=True)
   start=f.get('entry') or f.get('entry_point') or f.get('address')
   if not start and isinstance(f.get('function'),dict):start=f['function'].get('entry') or f['function'].get('entry_point')
   if start:save('ghidra-decompile-'+str(start),c.call('decomp.function',{'session_id':session,'function_start':start}))
finally:c.close()
