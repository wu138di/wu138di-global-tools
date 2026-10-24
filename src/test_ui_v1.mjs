// Offline DOM/runtime regression. No browser, device, network, or real credentials.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { setTimeout as nativeTimeout, clearTimeout as nativeClearTimeout, setInterval as nativeInterval, clearInterval as nativeClearInterval } from 'node:timers';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const require = createRequire(path.join(root, 'package.json'));
const { parseHTML, DOMParser } = require('linkedom');
const uiPath = path.join(here, 'platform-ui.js');
const builtPath = process.argv[2] ? path.resolve(process.argv[2]) : path.join(root, 'dist/wu138di-全球上网-V1.0.js');
const resultPath = path.join(here, 'test_ui_v1_result.json');
const output = [];
const liveFixtures = new Set();
const sha = value => createHash('sha256').update(value).digest('hex');
const wait = milliseconds => new Promise(resolve => nativeTimeout(resolve, milliseconds));
function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};}
const pass = message => { output.push('PASS: ' + message); console.log(output.at(-1)); };
const fixtureURL = 'https://fixture.invalid/subscription/test-only';
let calls = 0;
let networkCalls = 0;
let realRootCommands = 0;

function save(exitCode, error) {
  fs.writeFileSync(resultPath, JSON.stringify({
    test: 'Clash-style platform actual UI runtime in linkedom and Node VM',
    timestamp: new Date().toISOString(), exit_code: exitCode,
    source: uiPath, source_sha256: fs.existsSync(uiPath) ? sha(fs.readFileSync(uiPath)) : null,
    built_source: builtPath, built_sha256: fs.existsSync(builtPath) ? sha(fs.readFileSync(builtPath)) : null,
    built_integration_requested: Boolean(process.argv[2]),
    dom_library: 'linkedom@0.18.12', stdout: output,
    error: error ? String(error.stack || error) : null,
    mock_core_calls: calls, real_root_commands: realRootCommands,
    real_network_requests: networkCalls, real_device_requests: 0, browser_operations: 0,
    credential_fixture: 'synthetic; no user subscription, API secret, or provider data'
  }, null, 2) + '\n');
}

function createCore(configured = false) {
  let locked = true, disposed = false, progress = null,password='2007',configuredPin=false;
  const invocations = [];
  // Intentionally keep a nonempty core payload while unconfigured. The view must
  // gate this data on confirmed subscription state, not blindly render it.
  const status = {core:true, transparent:true, autostart:true, subscription:configured, controller:true, version:'fixture', uptime:3600};
  const proxyData = {
    PROXY:{name:'PROXY',type:'Selector',all:['JP 01','HK 01','TW 01'],now:'HK 01'},
    日本:{name:'日本',type:'Fallback',all:['JP 01'],now:'JP 01'},
    'JP 01':{name:'JP 01',type:'Shadowsocks',udp:true,alive:true,history:[{time:'2026-01-01',delay:45}]},
    'HK 01':{name:'HK 01',type:'Shadowsocks',udp:true,alive:true,history:[{time:'2026-01-01',delay:21}]},
    'TW 01':{name:'TW 01',type:'Shadowsocks',udp:true,alive:true,history:[{time:'2026-01-01',delay:33}]}
  };
  const ruleData = [
    {type:'DomainSuffix',payload:'abema.tv',proxy:'日本',RuleType:'DomainSuffix',Payload:'abema.tv',Proxy:'日本'},
    {type:'GeoIP',payload:'CN',proxy:'DIRECT',RuleType:'GeoIP',Payload:'CN',Proxy:'DIRECT'},
    {type:'Match',payload:'',proxy:'PROXY',RuleType:'Match',Payload:'',Proxy:'PROXY'}
  ];
  const connectionData = {downloadTotal:10485760,uploadTotal:524288,memory:16777216,connections:[
    {id:'fixture-connection-1',metadata:{host:'abema.tv',destinationIP:'192.0.2.23',destinationPort:'443',network:'tcp',sourceIP:'192.0.2.10'},
     upload:1024,download:1048576,chains:['日本','JP 01'],rule:'DomainSuffix',start:'2026-01-01T00:00:00Z'}
  ]};
  let mode = 'rule';
  let importError = false;
  const clone = value => JSON.parse(JSON.stringify(value));
  async function invoke(name, args, fn) {
    assert(!disposed, 'operation after core dispose');
    assert(!locked, 'operation while PIN locked');
    calls++; invocations.push({name,args});
    return clone(fn ? fn() : {ok:true});
  }
  return {
    invocations, statusData:status, proxyData, connectionData,
    get isLocked(){return locked;}, get disposed(){return disposed;},
    set importError(value){importError = value;},
    enter(pin){if(disposed)return false; locked = String(pin) !== password; return !locked;},
    getPinStatus:async()=>({configured:configuredPin}),
    changePin(current,next,confirm){return invoke('changePin',[],()=>{if(current!==password)throw new Error('当前口令错误');if(next!==confirm)throw new Error('两次口令不一致');password=next;configuredPin=true;return{ok:true};});},
    lock(){locked=true;}, leave(){locked=true;}, logout(){locked=true;},
    dispose(){disposed=true; locked=true; progress=null;},
    isBusy(){return false;},
    onProgress(callback){progress=callback; return ()=>{if(progress===callback)progress=null;};},
    snapshot(){return invoke('snapshot',[],()=>({status,mode,proxies:proxyData,rules:ruleData,connections:connectionData}));},
    status(){return invoke('status',[],()=>status);},
    proxies(){return invoke('proxies',[],()=>proxyData);},
    rules(){return invoke('rules',[],()=>ruleData);},
    connections(){return invoke('connections',[],()=>connectionData);},
    setMode(value){return invoke('setMode',[value],()=>{mode=value;return {mode};});},
    select(group,node){return invoke('select',[group,node],()=>{proxyData[group].now=node;return {ok:true};});},
    delay(node){return invoke('delay',[node],()=>({delay:47}));},
    importSubscription(url){return invoke('importSubscription',[url],()=>{if(importError)throw new Error('SUBSCRIPTION_REJECTED');status.subscription=true;return {ok:true};});},
    importYaml(value){return invoke('importYaml',[value],()=>({ok:true}));},
    diagnostics(){return invoke('diagnostics',[],()=>({core:'running',route:'ready',dns:'ready',direct_http:'200',proxy_http:'204'}));},
    refreshSubscription(){return invoke('refreshSubscription',[],()=>({ok:true}));},
    service(action){return invoke('service',[action],()=>{if(action==='stop'){status.transparent=false;status.core=false;}if(action==='disable')status.transparent=false;if(action==='enable'){status.transparent=true;status.core=true;}return {ok:true};});},
    autostart(value){return invoke('autostart',[value],()=>{status.autostart=value;return {ok:true};});},
    install(){return invoke('install',[],()=>({ok:true}));},
    standard(){return invoke('standard',[],()=>({ok:true}));},
    rollbackRules(){return invoke('rollbackRules',[],()=>({ok:true}));},
    closeConnection(id){return invoke('closeConnection',[id],()=>{connectionData.connections=connectionData.connections.filter(x=>x.id!==id);return {ok:true};});}
  };
}

function domFixture(source, core = createCore()) {
  const {document,window} = parseHTML('<!doctype html><html><head></head><body><div class="functions-container"><div class="actions-buttons"></div></div></body></html>');
  const timers = new Set(), intervals = new Set(), logs = [], storage = new Map();
  const forbidden = () => {networkCalls++;throw new Error('network forbidden in offline DOM test');};
  const storageFacade = {getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,String(value)),removeItem:key=>storage.delete(key),clear:()=>storage.clear()};
  const timeout = (callback,ms=0,...args) => {const id=nativeTimeout(()=>{timers.delete(id);callback(...args);},ms);id.unref();timers.add(id);return id;};
  const interval = (callback,ms,...args) => {const id=nativeInterval(callback,ms,...args);id.unref();intervals.add(id);return id;};
  const clearTimeoutTracked = id => {nativeClearTimeout(id);timers.delete(id);};
  const clearIntervalTracked = id => {nativeClearInterval(id);intervals.delete(id);};
  Object.assign(window,{fetch:forbidden,confirm:()=>true,localStorage:storageFacade,sessionStorage:storageFacade,
    setTimeout:timeout,clearTimeout:clearTimeoutTracked,setInterval:interval,clearInterval:clearIntervalTracked,
    requestAnimationFrame:callback=>timeout(callback,0),cancelAnimationFrame:clearTimeoutTracked});
  const context = vm.createContext({window,document,Event:window.Event,CustomEvent:window.CustomEvent,URL,URLSearchParams,TextEncoder,
    console:{log:(...args)=>logs.push(args.join(' ')),error:(...args)=>logs.push(args.join(' ')),warn:(...args)=>logs.push(args.join(' '))},
    fetch:forbidden,confirm:()=>true,localStorage:storageFacade,sessionStorage:storageFacade,
    setTimeout:timeout,clearTimeout:clearTimeoutTracked,setInterval:interval,clearInterval:clearIntervalTracked,
    requestAnimationFrame:callback=>timeout(callback,0),cancelAnimationFrame:clearTimeoutTracked,
    AbortController,performance,crypto:globalThis.crypto,navigator:{language:'zh-CN'},location:{href:'https://fixture.invalid/'}});
  vm.runInContext(source+'\n;globalThis.__mount = mountPlatformUI;',context,{filename:uiPath});
  const host = document.createElement('div');document.body.appendChild(host);
  const shadow=host.attachShadow({mode:'open'});
  const entry=document.createElement('button');document.body.appendChild(entry);
  const ui=context.__mount({shadow,entry,icon:'data:image/png;base64,fixture',core});
  const fixture={document,window,shadow,entry,ui,core,logs,storage,timers,intervals,context,
    close(){ui.dispose();for(const id of timers)nativeClearTimeout(id);for(const id of intervals)nativeClearInterval(id);timers.clear();intervals.clear();liveFixtures.delete(fixture);}};
  liveFixtures.add(fixture);
  return fixture;
}

const find = (fixture,testId) => {
  const aliases={'pin-input':'platform-pin','login-form':'platform-login-form','login-error':'platform-toast','toast':'platform-toast','logout':'platform-lock'};
  const node=fixture.shadow.querySelector(`[data-testid="${aliases[testId]||testId}"]`);
  assert(node,'missing UI control: '+testId);return node;
};
async function click(fixture,testId){find(fixture,testId).click();await wait(15);}
function setValue(fixture,testId,value){const element=find(fixture,testId);element.value=value;element.dispatchEvent(new fixture.window.Event('input',{bubbles:true}));return element;}
async function submit(fixture,testId){find(fixture,testId).dispatchEvent(new fixture.window.Event('submit',{bubbles:true,cancelable:true}));await wait(15);}
const visibleText=fixture=>fixture.shadow.querySelector('.window')?.textContent||'';
function noPrivateUI(fixture){assert(!visibleText(fixture).includes(fixtureURL),'subscription URL echoed in visible UI');assert(!fixture.logs.join('\n').includes(fixtureURL),'subscription URL logged');assert.equal(fixture.storage.size,0,'PIN or subscription persisted in browser storage');}


try {
 const source=fs.readFileSync(path.join(here,'flags.js'),'utf8')+'\n'+fs.readFileSync(uiPath,'utf8'),core=createCore(true),f=domFixture(source,core);
 f.ui.open();await wait(20);assert.equal(core.invocations.length,0);
 setValue(f,'pin-input','0000');await submit(f,'login-form');assert.equal(core.invocations.length,0);
 setValue(f,'pin-input','2007');await submit(f,'login-form');assert.equal(f.shadow.querySelectorAll('.nav-btn').length,7);
 pass('locked UI only asks PIN status; wrong PIN does not query proxy state; correct PIN opens seven tabs');
 await click(f,'nav-subscription');assert(find(f,'yaml-file'));assert(find(f,'yaml-text'));assert(visibleText(f).includes('节点 YAML'));
 setValue(f,'yaml-text','proxies:\n  - {name: fixture}');
 [...f.shadow.querySelectorAll('button')].find(n=>n.textContent==='导入 YAML').click();await wait(30);
 assert(core.invocations.some(x=>x.name==='importYaml'));assert.equal(find(f,'yaml-text').value,'');
 pass('YAML text/file controls render; explicit YAML submit calls core and clears private text');
 setValue(f,'subscription-url',fixtureURL);await submit(f,'subscription-form');assert(core.invocations.some(x=>x.name==='importSubscription'));noPrivateUI(f);
 pass('subscription submit clears URL and never persists browser credentials');
 await click(f,'nav-diagnostics');[...f.shadow.querySelectorAll('button')].find(n=>n.textContent==='开始检测').click();await wait(30);assert(visibleText(f).includes('204'));assert(visibleText(f).includes('ready'));
 pass('diagnostic results re-render immediately after completion');
 await click(f,'nav-proxies');assert([...f.shadow.querySelectorAll('[data-testid="proxy-delay"]')].every(n=>n.textContent==='测速'));
 [...f.shadow.querySelectorAll('button')].find(n=>n.textContent==='全部测速').click();await wait(40);assert([...f.shadow.querySelectorAll('[data-testid="proxy-delay"]')].every(n=>n.textContent==='47 ms'&&!n.disabled));
 pass('expired historical values are not shown as current; batch results refresh and controls re-enable');
 await click(f,'nav-overview');f.shadow.querySelector('.power').click();await wait(30);assert(core.invocations.some(x=>x.name==='service'&&x.args[0]==='stop'));assert(!core.statusData.transparent);
 f.shadow.querySelector('.power').click();await wait(30);assert(core.invocations.some(x=>x.name==='service'&&x.args[0]==='enable'));assert(core.statusData.transparent);
 pass('power uses stop and explicit enable, not a second-click service-only start');
 await click(f,'nav-proxies');assert.equal(f.shadow.querySelectorAll('.node-flag[data-country=JP]').length,1);assert.equal(f.shadow.querySelectorAll('.node-flag[data-country=HK]').length,1);assert(f.shadow.querySelector('.selected-tick'));pass('embedded country flags fill node marks and selection keeps its check badge');
 await click(f,'nav-settings');setValue(f,'pin-current','2007');setValue(f,'pin-new','Fixture-PIN-42');setValue(f,'pin-confirm','Fixture-PIN-42');await submit(f,'pin-settings-form');assert(core.isLocked);assert.equal(find(f,'pin-input').placeholder,'输入登录口令');
 setValue(f,'pin-input','2007');await submit(f,'login-form');assert(core.isLocked);setValue(f,'pin-input','Fixture-PIN-42');await submit(f,'login-form');assert(!core.isLocked);pass('settings change locks session; custom-PIN login hides the default hint and rejects 2007');
 await click(f,'logout');assert(core.isLocked);assert(find(f,'pin-input'));f.close();save(0);console.log('UI V1 PASS');
} catch(error){save(1,error);for(const f of liveFixtures)f.close();throw error;}
