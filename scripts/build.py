from pathlib import Path
import base64,json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[1];HERE=ROOT/'src';OUT=ROOT/'dist';OUT.mkdir(exist_ok=True)
bg='data:image/webp;base64,'+base64.b64encode((ROOT/'assets/sakura.webp').read_bytes()).decode()
icon='data:image/png;base64,'+base64.b64encode((ROOT/'assets/icon.png').read_bytes()).decode()
scripts={k:(HERE/f).read_text(encoding='utf-8') for k,f in [('install','install.sh'),('standard','restore-standard.sh'),('bridge','platform-bridge.sh'),('subscriptionBridge','platform-subscription.cgi'),('update','update.sh')]}
ui=(HERE/'platform-ui.js').read_text(encoding='utf-8').replace('__GLOBAL_BG__',bg)
helpers='\n'.join((HERE/f).read_text(encoding='utf-8') for f in ['pin-crypto.js','pin-support.js','flags.js'])
assert '</script' not in helpers.lower()
core=helpers+'\n'+(HERE/'platform-core.js').read_text(encoding='utf-8')
source=(HERE/'plugin.template.js').read_text(encoding='utf-8').replace("const VERSION = '2.0.1'","const VERSION = '1.0.0'").replace('U30Pro-Mihomo','wu138di-GlobalNet').replace('科学上网插件','wu138di 全球上网 V1.0')
for k,v in {'__U30_PUBLIC_SCRIPTS__':json.dumps(scripts,ensure_ascii=False).replace('<',r'\u003c'),'__U30_ICON__':json.dumps(icon),'__U30_CORE__':core,'__U30_UI__':ui}.items():
 assert source.count(k)==1;source=source.replace(k,v)
assert len(source.encode())<4*1024*1024
for ext in ['txt','js']:(OUT/('wu138di-全球上网-V1.0.'+ext)).write_text(source,encoding='utf-8',newline='\n')
preview=(HERE/'preview-core.js').read_text(encoding='utf-8').replace('setMode:unavailable','importYaml:unavailable,diagnostics:unavailable,setMode:unavailable')
preview=helpers+'\n'+preview
html='''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>wu138di 全球上网 V1.0</title><style>body{margin:0;background:#f3eaf5;font-family:system-ui}.open{padding:15px 24px;border:0;border-radius:18px;background:#a58ac0;color:white;margin:30px;min-height:44px}</style></head><body><button id="entry" class="open">wu138di 全球上网 V1.0</button><div id="host"></div><script>'''+preview+'\n'+ui+'\nconst host=document.getElementById("host"),entry=document.getElementById("entry");const platform=mountPlatformUI({shadow:host.attachShadow({mode:"open"}),entry,icon:'+json.dumps(icon)+',core:createPreviewCore()});platform.open();</script></body></html>'
(OUT/'界面预览.html').write_text(html,encoding='utf-8',newline='\n')
shutil.copy2(ROOT/'assets/sakura.webp',OUT/'sakura.webp')
metadata={'name':'wu138di 全球上网 V1.0','pin':'2007','version':'1.0.0','sha256':hashlib.sha256(source.encode()).hexdigest(),'bytes':len(source.encode()),'device_operations':0}
(OUT/'manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(metadata,ensure_ascii=True))
