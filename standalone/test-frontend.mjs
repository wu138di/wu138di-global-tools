import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {setTimeout as sleep} from 'node:timers/promises';
const root=path.dirname(fileURLToPath(import.meta.url));
const require=createRequire(path.join(root,'../package.json'));
const {parseHTML}=require('linkedom');
const resultDir=path.join(root,'test-results');fs.mkdirSync(resultDir,{recursive:true});
const nativeFetch=globalThis.fetch.bind(globalThis);
const stateDir=fs.mkdtempSync(path.join(resultDir,'http-state-'));
const base='http://127.0.0.1:18769';
const server=spawn(path.join(root,'dist/global-manager-local.exe'),['-local-check','-listen','127.0.0.1:18769','-home',stateDir],{windowsHide:true,stdio:['ignore','pipe','pipe']});
let cookie='',networkRequests=0,logs='';const output=[];
server.stdout.on('data',d=>logs+=d);server.stderr.on('data',d=>logs+=d);
async function transport(url,options={}){
 const target=new URL(url,base);assert.equal(target.origin,base,'nonlocal request');networkRequests++;
 const headers=new Headers(options.headers);if(cookie)headers.set('Cookie',cookie);if((options.method||'GET')!=='GET')headers.set('Origin',base);
 const response=await nativeFetch(target,{...options,headers});
 const set=response.headers.get('set-cookie');if(set)cookie=set.split(';')[0];return response;
}
async function until(check,label){for(let n=0;n<150;n++){if(await check())return;await sleep(20);}throw new Error('timeout: '+label);}
const timers=new Set(),intervals=new Set();
let teardown=()=>{};
const timeout=(f,t,...args)=>{const id=setTimeout(()=>{timers.delete(id);f(...args);},t);id.unref();timers.add(id);return id;};
const interval=(f,t,...args)=>{const id=setInterval(f,t,...args);id.unref();intervals.add(id);return id;};
try{
 await until(async()=>{try{return(await nativeFetch(base+'/api/pin/status')).ok;}catch{return false;}},'HTTP server');
 const {document,window}=parseHTML('<html><body><button id="entry">打开控制台</button><div id="host"></div></body></html>');
 Object.assign(window,{fetch:transport,confirm:()=>true,matchMedia:()=>({matches:false,addEventListener(){},removeEventListener(){}}),requestAnimationFrame:f=>timeout(f,0),cancelAnimationFrame:clearTimeout});
 window.HTMLElement.prototype.focus=function(){};
 const context=vm.createContext({document,window,Event:window.Event,CustomEvent:window.CustomEvent,URL,URLSearchParams,TextEncoder,console,Map,Set,Date,Promise,setTimeout:timeout,clearTimeout,setInterval:interval,clearInterval,requestAnimationFrame:window.requestAnimationFrame,cancelAnimationFrame:clearTimeout});
 for(const name of ['flags.js','ui.js','app.js']){let code=fs.readFileSync(path.join(root,'web',name),'utf8');if(name==='app.js')code=code.replace('platform.open();\n}', 'platform.open();window.__testDispose=()=>{platform.dispose();core.dispose();};\n}');vm.runInContext(code,context,{filename:name});}
 teardown=()=>window.__testDispose?.();
 const shadow=document.getElementById('host').shadowRoot;
 const text=()=>Array.from(shadow.childNodes,n=>n.textContent||'').join('');
 const q=id=>shadow.querySelector(`[data-testid="${id}"]`);
 const click=id=>q(id).dispatchEvent(new window.Event('click',{bubbles:true}));
 const submit=id=>q(id).dispatchEvent(new window.Event('submit',{bubbles:true,cancelable:true}));
 await until(()=>q('platform-pin')?.placeholder==='登录口令 2007','default hint');
 output.push('PASS standalone login shows default PIN only before configuration');
 q('platform-pin').value='2007';submit('platform-login-form');
 await until(()=>text().includes('尚未安装'),'actual HTTP snapshot');
 assert(!text().includes('香港 01'));assert(!text().includes('日本 01'));
 output.push('PASS actual Go HTTP/auth/UI stack, no UFI SDK or fabricated nodes');
 click('nav-settings');await until(()=>q('pin-settings-form'),'settings');
 q('pin-current').value='2007';q('pin-new').value='Fixture-PIN-42';q('pin-confirm').value='Fixture-PIN-42';submit('pin-settings-form');
 await until(()=>q('platform-pin')?.placeholder==='输入登录口令'&&!q('platform-login-form')?.closest('[hidden]'),'PIN change');
 const stored=fs.readFileSync(path.join(stateDir,'state/pin.json'),'utf8');assert(!stored.includes('Fixture-PIN-42'));assert.equal(JSON.parse(stored).iterations,100000);
 output.push('PASS settings PIN change persists hashed profile, revokes session and removes 2007 hint');
 q('platform-pin').value='2007';submit('platform-login-form');await sleep(100);assert(text().includes('口令错误'));
 q('platform-pin').value='Fixture-PIN-42';submit('platform-login-form');await until(()=>text().includes('尚未安装'),'custom login');
 output.push('PASS old PIN rejected, new PIN accepted through actual HTTP transport');
 // Core adapter test against the real local server: device actions must fail,
 // never return fake install success just because the UI is running.
 const core=vm.runInContext('createStandaloneCore()',context);await core.enter('Fixture-PIN-42');
 await assert.rejects(()=>core.install(),e=>e.safeCode==='ANDROID_DEVICE_REQUIRED');core.lock();
 output.push('PASS development server rejects Android operations instead of faking success');
 assert(!logs.includes('Fixture-PIN-42'));assert(!fs.readFileSync(path.join(root,'web/app.js'),'utf8').includes('runShellWithRoot'));
 const result={exit_code:0,test:'actual Go HTTP server + linkedom UI',stdout:output,http_requests:networkRequests,real_android_requests:0,device_validation:'NOT_TESTED',state_dir:stateDir};
 fs.writeFileSync(path.join(resultDir,'frontend.json'),JSON.stringify(result,null,2));console.log(output.join('\n'));
}catch(error){fs.writeFileSync(path.join(resultDir,'frontend.json'),JSON.stringify({exit_code:1,error:String(error.stack),stdout:output,logs},null,2));throw error;}
finally{teardown();for(const id of timers)clearTimeout(id);for(const id of intervals)clearInterval(id);server.kill();}
