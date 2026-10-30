import pathlib,subprocess,sys,json,hashlib,re
ROOT=pathlib.Path(__file__).resolve().parent
def run(*args,**kw):return subprocess.run(args,check=True,**kw)
def remote(adb,command):
 wrapped=command+'; unified_result=$?; printf "\\nUNIFIED_REMOTE_EXIT=%s\\n" "$unified_result"'
 result=run(*adb,'shell',wrapped,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
 match=re.search(r'\nUNIFIED_REMOTE_EXIT=(\d+)\s*$',result.stdout)
 print(result.stdout[:match.start()] if match else result.stdout,flush=True)
 if not match or int(match[1])!=0:raise SystemExit('Device operation failed. No reboot was requested; inspect the message above.')
def main():
 action=sys.argv[1] if len(sys.argv)>1 else 'check'
 if action not in ('check','install','restore'):raise SystemExit('Usage: python3 manage.py check|install|restore')
 for rel,digest in json.loads((ROOT/'bundle-hashes.json').read_text()).items():
  if hashlib.sha256((ROOT/rel).read_bytes()).hexdigest()!=digest:raise SystemExit('Bundle hash mismatch: '+rel)
 manifest=json.loads((ROOT/'manifest.json').read_text())
 for item in manifest['files']:
  p=ROOT/'payload'/item['path'].lstrip('/')
  if hashlib.sha256(p.read_bytes()).hexdigest()!=item['sha256']:raise SystemExit('Package hash mismatch: '+item['path'])
 devices=subprocess.check_output(['adb','devices'],text=True).splitlines()[1:]
 active=[line.split()[0] for line in devices if line.endswith('\tdevice')]
 if len(active)!=1:raise SystemExit('Connect exactly one USB ADB device.')
 adb=['adb','-s',active[0]]
 stage='/userdisk/mod-stage-unified-v1'
 if action=='restore':remote(adb,'sh /userdisk/mod-backups/unified-mod-v1/restore.sh')
 else:
  remote(adb,'mkdir -p '+stage)
  for name in ('payload','apps','files.tsv','device-install.sh','device-restore.sh','configure.pl','restore-config.pl','sshd_config','credentials-template.js.bin'):
   run(*adb,'push',str(ROOT/name),stage+'/')
  command='sh '+stage+'/device-install.sh'+(' --check' if action=='check' else '')
  remote(adb,command)
 if action in ('install','restore'):
  print('Files updated. Rebooting to reload system libraries and services.',flush=True)
  run(*adb,'reboot')
if __name__=='__main__':main()
