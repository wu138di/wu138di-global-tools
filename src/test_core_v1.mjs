import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const here=new URL('.',import.meta.url),read=f=>fs.readFileSync(new URL(f,here),'utf8');
const scripts=Object.fromEntries([['bridge','platform-bridge.sh'],['subscriptionBridge','platform-subscription.cgi'],['update','update.sh'],['standard','restore-standard.sh'],['install','install.sh']].map(([k,f])=>[k,read(f)]));
const ctx=vm.createContext({URL,TextEncoder,AbortController,crypto:crypto.webcrypto,setTimeout,clearTimeout});
vm.runInContext(['pin-crypto.js','pin-support.js','flags.js','platform-core.js'].map(read).join('\n'),ctx);
const checks=[],calls=[],ops=[],uploads=[];let active=0,maxActive=0,badDelay=false,badProxy=false,importCode=0;
const state='core=running\ntransparent=off\nautostart=no\nsubscription=validated\ncontroller=authenticated-ready';
const node={name:'Fixture HK',type:'Shadowsocks',history:[]};
function decode(cmd){const q=cmd.slice('/system/bin/sh -c '.length,cmd.lastIndexOf('\nr=$?'));return q.slice(1,-1).replaceAll("'\\''","'");}
async function sdk(cmd){
 if(cmd.includes('__U30_PIN_RC__')){calls.push(cmd);return {success:true,content:'{"default":true}\n__U30_PIN_RC__=0\n'};}
 calls.push(cmd);active++;maxActive=Math.max(active,maxActive);await new Promise(r=>setTimeout(r,3));active--;
 const plain=decode(cmd),tail=plain.slice(plain.lastIndexOf(' -- ')+4),args=[...tail.matchAll(/'([^']*)'/g)].map(x=>x[1]);
 let out='ready',rc=0;
 if(plain.startsWith('/system/bin/sh -c ')){
  const op=args[0];ops.push({op,args:args.slice(1)});
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
 } else if(plain.includes('nohup /system/bin/sh'))out='started';
 else if(plain.includes('__U30_JOB_RC__='))out='__U30_JOB_RC__=0';
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
badDelay=true;count=calls.length;await assert.rejects(core.service('enable'),/节点未连通/);assert(!calls.slice(count).some(c=>decode(c).includes('nohup /system/bin/sh')));checks.push('unreachable selected node blocks traffic capture before enable');
badDelay=false;badProxy=true;count=calls.length;await assert.rejects(core.service('enable'),/保持直连/);assert(!calls.slice(count).some(c=>decode(c).includes('nohup /system/bin/sh')));badProxy=false;await core.service('enable');checks.push('mixed-proxy HTTPS preflight also blocks enable on failure; successful preflight permits explicit enable');
const diag=await core.diagnostics();assert.equal(diag.proxy_http,'204');assert.equal(diag.dns,'ready');checks.push('network diagnostics separates route, DNS, direct HTTPS and proxy HTTPS');
core.lock();count=calls.length;assert.throws(()=>core.delay(node.name));assert.equal(calls.length,count);core.dispose();checks.push('logout revokes queued/next operations');
const report={result:'passed',checks,scope:'isolated VM, fake authenticated SDK; no device claims'};
fs.writeFileSync(new URL('test_core_v1_result.json',here),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
