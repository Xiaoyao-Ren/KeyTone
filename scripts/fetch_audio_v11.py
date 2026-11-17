#!/usr/bin/env python3
"""Fetch the pinned upstream audio; original per-key maps are retained in AudioSources."""
import concurrent.futures,hashlib,json,os,pathlib,shutil,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
WORK=pathlib.Path(os.environ.get('KEYTONE_AUDIO_WORK',ROOT/'.build/audio-sources'))
items=json.loads((ROOT/'AudioSources/downloads.json').read_text())
def fetch(item):
 folder=WORK/item['id'];folder.mkdir(parents=True,exist_ok=True)
 target=folder/item['audio']
 if not target.exists():target.write_bytes(urllib.request.urlopen(item['url'],timeout=90).read())
 assert hashlib.sha256(target.read_bytes()).hexdigest()==item['audio_sha256'],f"Audio checksum mismatch: {item['id']}"
 config=ROOT/'AudioSources'/item['id']/'config.json'
 assert hashlib.sha256(config.read_bytes()).hexdigest()==item['config_sha256']
 shutil.copy2(config,folder/'config.json')
 return item['id']
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 for name in pool.map(fetch,items):print('Verified',name)
