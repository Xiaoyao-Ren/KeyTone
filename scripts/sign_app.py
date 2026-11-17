#!/usr/bin/env python3
"""Sign with a persistent, dedicated local identity. Never silently fall back to ad-hoc."""
import json,os,pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parents[1]
config_path=pathlib.Path(os.environ.get('KEYTONE_SIGNING_CONFIG',pathlib.Path.home()/'Library/Application Support/KeyTone/Signing/identity.json'))
if not config_path.exists():
 raise SystemExit('Missing persistent signing identity. Run python3 scripts/setup_signing.py once; keep the signing directory private and retain it for future updates.')
c=json.loads(config_path.read_text());password=pathlib.Path(c['password_file']).read_text()
def run(args):
 p=subprocess.run(args,capture_output=True,text=True)
 if p.returncode:raise SystemExit(p.stderr.replace(password,'[redacted]'))
 return p.stdout
run(['security','unlock-keychain','-p',password,c['keychain']])
app=sys.argv[1]
requirement=f'=designated => identifier "local.keytone.app" and certificate leaf = H"{c["sha1"]}"'
run(['codesign','--force','--sign',c['sha1'],'--keychain',c['keychain'],'--timestamp=none','--identifier','local.keytone.app','--requirements',requirement,app])
run(['codesign','--verify','--deep','--strict',app])
print('Signed with persistent KeyTone identity:',c['sha1'])
