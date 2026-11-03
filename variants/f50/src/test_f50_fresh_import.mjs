import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const here=new URL('.',import.meta.url),read=f=>fs.readFileSync(new URL(f,here),'utf8');
const scripts=Object.fromEntries([['bridge','platform-bridge.sh'],['subscriptionBridge','platform-subscription.cgi'],['update','update.sh'],['standard','restore-standard.sh'],['install','install.sh'],['networkRepair','repair-network.sh']].map(([k,f])=>[k,read(f)]));
const ctx=vm.createContext({URL,TextEncoder,AbortController,crypto:crypto.webcrypto,setTimeout,clearTimeout});
vm.runInContext(['pin-crypto.js','pin-support.js','flags.js','platform-core.js'].map(read).join('\n'),ctx);
const checks=[],calls=[],ops=[],uploads=[];let active=0,maxActive=0,badDelay=false,badProxy=false,importCode=0,toolsInstalled=false,chunks=0,jobFailure=false;
let state='core=running\ntransparent=off\nautostart=no\nsubscription=validated\ncontroller=authenticated-ready';
const node={name:'Fixture HK',type:'Shadowsocks',history:[]};
function decode(cmd){const q=cmd.slice('/system/bin/sh -c '.length,cmd.lastIndexOf('\nr=$?'));return q.slice(1,-1).replaceAll("'\\''","'");}
const jobParts=new Map(),jobScripts=new Map();
async function sdk(cmd){
 if(cmd.includes('__U30_PIN_RC__')){calls.push(cmd);return {success:true,content:'{"default":true}\n__U30_PIN_RC__=0\n'};}
 calls.push(cmd);active++;maxActive=Math.max(active,maxActive);await new Promise(r=>setTimeout(r,3));active--;
 const plain=decode(cmd),tail=plain.slice(plain.lastIndexOf(' -- ')+4),args=[...tail.matchAll(/'([^']*)'/g)].map(x=>x[1]);
 const chunk=plain.match(/printf %s '([A-Za-z0-9+/=]+)' >> '([^']+task\.sh\.b64)'/);
 if(chunk)jobParts.set(chunk[2],(jobParts.get(chunk[2])||'')+chunk[1]);
 const finish=plain.match(/base64 -d '([^']+task\.sh\.b64)'/);if(finish)jobScripts.set(finish[1].replace(/\.b64$/,''),Buffer.from(jobParts.get(finish[1])||'','base64').toString('utf8'));
 const launched=plain.match(/nohup "\$BB" sh '([^']+)\/runner\.sh'/);
 if(launched){const script=jobScripts.get(launched[1]+'/task.sh')||'';if(script.includes('U30_PLUGIN_OK:'))state='core=running\ntransparent=off\nautostart=no\nsubscription=validated\ncontroller=authenticated-ready';const args=[...script.slice(script.lastIndexOf(' -- ')+4).matchAll(/'([^']*)'/g)].map(m=>m[1]);if(args[0])ops.push({op:args[0],args:args.slice(1),callIndex:calls.length-1});}

 let out='ready',rc=0;
 if(plain.startsWith('/system/bin/sh -c ')){
  const op=args[0];ops.push({op,args:args.slice(1),callIndex:calls.length-1});
  if(op==='status')out=state;
  else if(op==='proxies')out=JSON.stringify({proxies:{PROXY:{type:'Selector',all:[node.name],now:node.name},DIRECT:{type:'Direct'}}});
  else if(op==='providers')out=JSON.stringify({providers:{subscription:{proxies:[node]}}});
  else if(op==='mode')out='{"mode":"rule"}';
  else if(op==='rules')out='{"rules":[{"type":"Match","proxy":"PROXY","payload":""}]}';
  else if(op==='connections')out='{"connections":null,"downloadTotal":0,"uploadTotal":0,"memory":0}';
  else if(op==='provider_delay'){out='{"delay":117}';if(badDelay){rc=69;out='controller_request_failed';}}
  else if(op==='delay')throw Error('wrong endpoint for a provider node');
  else if(op==='import_ticket')out=JSON.stringify({ticket:'a'.repeat(64)});
  else if(op==='import_poll')out='__U30_IMPORT_RC__='+importCode;
  else if(op==='import_error')out='download_http_403';
  else if(op==='diagnostics')out=state+'\nroute=ready\ndns=ready\ndirect_http=200\nproxy_http='+(badProxy?'000':'204');
  else out='done';
 } else if(plain.includes('printf ready; else printf missing'))out=toolsInstalled?'ready':'missing';
 else if(plain.includes('tool.b64')&&plain.includes(' >> ')){chunks++;assert(Buffer.byteLength(cmd)<65536);out='';}
 else if(plain.includes('ln ')&&plain.includes('u30proxy-tools/busybox')){toolsInstalled=true;out='ready';}
 else if(plain.includes('nohup /system/bin/sh')){out='started';if(plain.includes('U30_PLUGIN_OK:'))state='core=running\ntransparent=off\nautostart=no\nsubscription=validated\ncontroller=authenticated-ready';}
 else if(plain.includes('__U30_JOB_RC__='))out=jobFailure?'__U30_JOB_RC__=69\n__U30_JOB_REASON__=OFFICIAL_HTTP_DOWNLOAD_FAILED':'__U30_JOB_RC__=0';
 return {success:true,content:out+'\n__U30_RC__='+rc+'\n'};
}
const core=ctx.createPlatformCore({sdk,scripts,request:async(url,opts)=>{uploads.push({url,body:opts.body});return{status:202,json:async()=>({ok:true,result:'started'})};}});
assert(!await core.enter('wrong'));await assert.rejects(core.status());assert.equal(calls.length,1);assert(await core.enter('2007'));checks.push('PIN gate: wrong PIN reads only protected PIN metadata, never proxy commands');
let snap=await core.snapshot();assert(snap.proxies[node.name]);assert.equal(snap.rules.length,1);assert.equal(snap.connections.connections.length,0);checks.push('provider metadata merged without fabricated nodes');
const results=await Promise.all([core.delay(node.name),core.delay(node.name),core.delay(node.name)]);
assert(results.every(r=>r.delay===117&&r.measuredAt>0));assert.equal(maxActive,1);assert(ops.filter(x=>x.op==='provider_delay').every(x=>x.args[0]==='subscription'&&x.args[1]==='Fixture%20HK'));checks.push('correct provider healthcheck route; all SDK and delay requests serialized; reported latency is the core value');
let count=calls.length;await assert.rejects(core.importSubscription('http://fixture.invalid'));assert.equal(calls.length,count);
await assert.rejects(core.importYaml('not yaml'));assert.equal(calls.length,count);checks.push('invalid URL/YAML rejected before device writes');
const yaml='proxies:\n  - {name: FixtureNew, type: ss, server: example.invalid, port: 443, cipher: aes-128-gcm, password: TEST_ONLY_PASSWORD}\n';
assert.equal((await core.importYaml(yaml)).routing,'preserved');assert(uploads.at(-1).url.endsWith('?mode=yaml'));assert.equal(uploads.at(-1).body,yaml);assert(!calls.some(c=>c.includes('TEST_ONLY_PASSWORD')));checks.push('YAML body uses single-use CGI channel, never RootShell or public logs');
await core.importSubscription('https://fixture.invalid/private-subscription');assert(uploads.at(-1).url.endsWith('?mode=subscription'));assert(!calls.some(c=>c.includes('https://fixture.invalid/private-subscription')));assert(!ops.some(x=>x.op==='set_mode'));assert(!calls.some(c=>decode(c).includes('U30_PUBLIC_CONFIG_TEMPLATE_YAML_EOF')));checks.push('subscription and YAML imports preserve gateway rules, DNS and mode; no automatic standard reset');
importCode=69;await assert.rejects(core.importSubscription('https://fixture.invalid/sub-denied'),e=>e.code==='download_http_403'&&e.message.includes('403'));importCode=0;checks.push('HTTP 403 is reported as subscription server rejection, not fake latency or success');
badDelay=true;count=calls.length;await assert.rejects(core.service('enable'),/节点未连通/);assert.equal(calls.length,ops.at(-1).callIndex+1);checks.push('unreachable selected node blocks traffic capture before enable');
badDelay=false;badProxy=true;count=calls.length;await assert.rejects(core.service('enable'),/保持直连/);assert.equal(calls.length,ops.at(-1).callIndex+1);badProxy=false;await core.service('enable');checks.push('mixed-proxy HTTPS preflight also blocks enable on failure; successful preflight permits explicit enable');
const diag=await core.diagnostics();assert.equal(diag.proxy_http,'204');assert.equal(diag.dns,'ready');checks.push('network diagnostics separates route, DNS, direct HTTPS and proxy HTTPS');
const installedState=state;
state='deployment=missing\ncore=stopped\ntransparent=off\nautostart=no\nsubscription=none\ncontroller=not-ready';
scripts.busyboxBase64=Buffer.alloc(60000,7).toString('base64');scripts.busyboxSha256=crypto.createHash('sha256').update(Buffer.alloc(60000,7)).digest('hex');
count=calls.length;const opStart=ops.length;await core.importSubscription('https://fixture.invalid/fresh-private');
assert(toolsInstalled);assert.equal(chunks,4);assert(uploads.at(-1).url.endsWith('?mode=subscription'));
assert(!calls.slice(count).some(c=>c.includes('https://fixture.invalid/fresh-private')));
const freshOps=ops.slice(opStart);assert(freshOps.some(o=>o.op==='stop'));assert(freshOps.some(o=>o.op==='disable'));assert(freshOps.some(o=>o.op==='autostart'&&o.args[0]==='no'));assert(!freshOps.some(o=>o.op==='enable'));
checks.push('fresh F50 subscription import provisions hash-pinned tools in <=24KB chunks, installs backend and disables traffic capture/autostart before uploading private URL');
state='deployment=missing\ncore=stopped\ntransparent=off\nautostart=no\nsubscription=none\ncontroller=not-ready';jobFailure=true;const uploadCount=uploads.length;
await assert.rejects(core.importSubscription('https://fixture.invalid/not-to-be-disclosed'),e=>e.safeCode==='CHANNEL_INSTALL_OFFICIAL_HTTP_DOWNLOAD_FAILED');assert.equal(uploads.length,uploadCount);jobFailure=false;
checks.push('failed backend install retains bounded stage reason, blocks subscription upload and exposes no raw log');
state=installedState;
core.lock();count=calls.length;assert.throws(()=>core.delay(node.name));assert.equal(calls.length,count);core.dispose();checks.push('logout revokes queued/next operations');
const report={result:'passed',checks,scope:'isolated VM, fake authenticated SDK; no device claims'};
fs.writeFileSync(new URL('test_f50_fresh_import_result.json',here),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
