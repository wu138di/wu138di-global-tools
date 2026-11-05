"""Build the independent engine and offline Windows/ADB deployment package."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,urllib.request,zipfile
ROOT=Path(__file__).resolve().parent;REPO=ROOT.parent
VERSION='1.1.0-alpha.2'
OUT=ROOT/'dist';OUT.mkdir(exist_ok=True)
WEB=ROOT/'web';WEB.mkdir(exist_ok=True)
PAY=ROOT/'payload';PAY.mkdir(exist_ok=True)
ASSETS={
 'mihomo.gz':'42b1f2be8702484d3ae6238daab392622f54bd0d264966700f1f28f52596e326',
 'ui.tgz':'7bea3c8878cb15a4bd9ee58275045f41642e17667dbe1ae3ce27bf5e3e7dc99b',
 'geoip-cn.mrs':'d8573e8435f16116a4ba7ef7bfe914d9615e43a812eb2a348694ef21b20e0ed3',
 'geoip-private.mrs':'076ea1da10b442f01c6fb3b86a66411727a15df69d70e8d600a8a458b07a8bb0',
 'geosite-cn.mrs':'2f7ccaf6ac344b22f2d3751ffcdd1e102f6cd698fb526c4c3eb4c0797505d75f',
 'geosite-private.mrs':'0f9ba48d4d0b0d192a4e7c3548486dde05e5a92e6e58e8ea8c9cc302712a1420'
}
def write(p,t):p.write_text(t,encoding='utf-8',newline='\n')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
cache=Path(os.environ.get('GLOBAL_ASSET_CACHE',str(ROOT/'asset-cache')));cache.mkdir(parents=True,exist_ok=True)
legacy=REPO.parents[1]/'aliyun-download-mirror/verified-downloads'
for name,digest in ASSETS.items():
 p=cache/name
 if not p.exists() and (legacy/name).exists() and sha(legacy/name)==digest:shutil.copy2(legacy/name,p)
 if not p.exists():
  with urllib.request.urlopen('https://8.134.248.110/global-tools/releases/v1/'+name,timeout=180) as r:data=r.read()
  if hashlib.sha256(data).hexdigest()!=digest:raise SystemExit('RESOURCE_HASH_MISMATCH: '+name)
  p.write_bytes(data)
 if sha(p)!=digest:raise SystemExit('RESOURCE_HASH_MISMATCH: '+name)
 (PAY/'assets').mkdir(exist_ok=True);shutil.copy2(p,PAY/'assets'/name)
for variant in ['u30','f50']:
 target=PAY/variant;target.mkdir(exist_ok=True)
 for p in target.iterdir():
  if p.is_file() and p.name=='platform-bridge.sh':p.unlink()
 for p in (REPO/'device'/variant).glob('*.sh'):shutil.copy2(p,target/p.name)
 shutil.copy2(REPO/'device/adopt-runtime.sh',target/'adopt-runtime.sh')
(PAY/'tools').mkdir(exist_ok=True)
bb=REPO/'vendor/busybox/busybox-arm64'
assert sha(bb)=='4d60ab3f5a59ebb2ca863f2f514e6924401b581e9b64f602665c008177626651'
shutil.copy2(bb,PAY/'tools/busybox')
env={**os.environ,'CGO_ENABLED':'0','GOOS':'android','GOARCH':'arm64'}
subprocess.run(['go','build','-trimpath','-buildvcs=false','-ldflags=-s -w','-o',str(PAY/'tools/http-tool'),'./cmd/http-tool'],cwd=ROOT,env=env,check=True)
for n in ['ui.js','flags.js']:shutil.copy2(ROOT/'ui'/n,WEB/n)
for n in ['icon.png','sakura.webp']:shutil.copy2(REPO/'assets'/n,WEB/n)
shutil.copy2(ROOT/'app.js',WEB/'app.js')
write(WEB/'index.html','''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>wu138di 全球上网 · 自研管理引擎</title><link rel="icon" href="/icon.png"><link rel="stylesheet" href="/app.css"><script defer src="/flags.js"></script><script defer src="/ui.js"></script><script defer src="/app.js"></script></head><body><button id="entry">打开控制台</button><div id="host"></div></body></html>''')
write(WEB/'app.css','''html,body{margin:0;min-height:100%;background:#f3eaf5;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}#entry{margin:24px;padding:14px 24px;min-height:44px;border:0;border-radius:16px;background:#a481b6;color:#fff}button:active{transform:scale(.98)}@media(prefers-color-scheme:dark){body{background:#281e2f}}@media(prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}''')
subprocess.run(['go','build','-trimpath','-buildvcs=false','-ldflags=-s -w','-o',str(OUT/'global-manager-arm64'),'.'],cwd=ROOT,env=env,check=True)
if '--host' in sys.argv:subprocess.run(['go','build','-trimpath','-buildvcs=false','-o',str(OUT/'global-manager-local.exe'),'.'],cwd=ROOT,check=True)
for name in ['manager.sh','install-device.sh','install.ps1']:shutil.copy2(ROOT/name,OUT/name)
for p in (REPO/'installer').iterdir():
 if p.is_file():shutil.copy2(p,OUT/p.name)
for n in ['README.md','NOTICE.md']:shutil.copy2(REPO/n,OUT/n)
shutil.copy2(REPO/'vendor/busybox/LICENSE',OUT/'BUSYBOX-LICENSE.txt')
shutil.copy2(REPO/'vendor/busybox/MAGISK-LICENSE',OUT/'MAGISK-LICENSE.txt')
for component in ['mihomo','metacubexd']:shutil.copy2(REPO/'vendor'/component/'LICENSE',OUT/(component.upper()+'-LICENSE.txt'))
resources=json.loads((REPO/'installer/resources.json').read_text(encoding='utf-8'));m=resources['magisk']
apk=Path(os.environ.get('GLOBAL_MAGISK_APK',str(cache/'Magisk-v30.7.apk')))
if not apk.exists():
 legacy_apk=REPO.parents[1]/'f50-b08-adaptation/assets/Magisk-v30.7.apk'
 if legacy_apk.exists():apk=legacy_apk
 else:
  with urllib.request.urlopen(m['url'],timeout=180) as r:data=r.read()
  if hashlib.sha256(data).hexdigest()!=m['sha256']:raise SystemExit('MAGISK_APK_HASH_MISMATCH')
  apk.write_bytes(data)
assert sha(apk)==m['sha256']
(OUT/'tools').mkdir(exist_ok=True);shutil.copy2(apk,OUT/m['file'])
manifest={'version':VERSION,'architecture':'android-arm64','engine':'wu138di independent management engine','proxy_core':'Mihomo v1.19.32','requires_root':True,'assets':ASSETS,'manager_sha256':sha(OUT/'global-manager-arm64'),'http_tool_sha256':sha(PAY/'tools/http-tool'),'validation':{'u30_manager':'previous alpha.1 real-device tested; alpha.2 pending','f50':'candidate; not real-device accepted','first_root_flash':'not performed by this installer'}}
proof=REPO/'tests/verification-alpha2.json'
if proof.exists():
 verification=json.loads(proof.read_text(encoding='utf-8'))
 if verification.get('manager_sha256')==manifest['manager_sha256'] and verification.get('http_tool_sha256')==manifest['http_tool_sha256']:
  manifest['validation']['u30_manager']='alpha.2 ADB installer and native helper verified on MU5358 B24; active proxy preserved'
write(OUT/'build-manifest.json',json.dumps(manifest,ensure_ascii=False,indent=2))
device_files=['global-manager-arm64','manager.sh','install-device.sh','root-env.sh']
write(OUT/'DEVICE-SHA256SUMS.txt',''.join(sha(OUT/n)+'  '+n+'\n' for n in device_files))
package_files=device_files+['install.ps1','bootstrap.ps1','installer-lib.ps1','resources.json','setup.cmd','check-env.cmd','prepare-root.cmd','README.md','NOTICE.md','build-manifest.json','BUSYBOX-LICENSE.txt','MAGISK-LICENSE.txt','MIHOMO-LICENSE.txt','METACUBEXD-LICENSE.txt',m['file'],'DEVICE-SHA256SUMS.txt']
write(OUT/'SHA256SUMS.txt',''.join(sha(OUT/n)+'  '+n+'\n' for n in package_files))
with zipfile.ZipFile(OUT/('wu138di-global-tools-v'+VERSION+'-windows.zip'),'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for name in package_files+['SHA256SUMS.txt']:z.write(OUT/name,name)
print(json.dumps({'version':VERSION,'manager_sha256':sha(OUT/'global-manager-arm64'),'http_tool_sha256':sha(PAY/'tools/http-tool'),'offline_magisk_app':True,'offline_resources':len(ASSETS),'adb':'existing SDK or official pinned download; no SDK binaries redistributed'}))
