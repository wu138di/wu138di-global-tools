import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import crypto from 'node:crypto';import os from 'node:os';import path from 'node:path';import {execFileSync} from 'node:child_process';
const here=new URL('.',import.meta.url),read=f=>fs.readFileSync(new URL(f,here),'utf8').replaceAll('\r\n','\n');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ufi-bootstrap-test-')),adb=path.join(fixture,'adb');fs.mkdirSync(adb);
const unix=p=>p.replace(/^([A-Za-z]):/,(_,d)=>'/'+d.toLowerCase()).replaceAll('\\','/');
let writes=0;const binary=Buffer.from('#!/bin/sh\n[ "$1" = true ]\n');
const scripts={busyboxBase64:binary.toString('base64'),busyboxSha256:crypto.createHash('sha256').update(binary).digest('hex')};
const ctx=vm.createContext({URL,TextEncoder,AbortController,crypto:crypto.webcrypto,setTimeout,clearTimeout});
let source=['pin-crypto.js','pin-support.js','platform-core.js'].map(read).join('\n');source=source.replace('  return {\n    async enter','  return {\n    _tools:()=>ensureTools(epoch),\n    async enter');vm.runInContext(source,ctx);
async function sdk(command){
 if(command.includes('__U30_PIN_RC__'))return{success:true,content:'{"default":true}\n__U30_PIN_RC__=0\n'};
 assert(!/iptables|ip rule|curl |subscription\.url|admin\.secret/.test(command));
 const shell=command.replaceAll('/system/bin/sh','bash').replaceAll('/system/bin/toybox base64','base64').replaceAll('/data/adb',unix(adb));
 const result=execFileSync('C:/Program Files/Git/bin/bash.exe',['-c','id(){ printf 0; }; export -f id;\n'+shell],{encoding:'utf8',windowsHide:true});writes++;return{success:true,content:result};
}
try{
 const core=ctx.createPlatformCore({sdk,scripts});assert(await core.enter('2007'));await core._tools();const target=path.join(adb,'u30proxy-tools','busybox');assert.deepEqual(fs.readFileSync(target),binary);assert.deepEqual(fs.readdirSync(path.dirname(target)),['busybox']);
 const first=writes;await core._tools();assert.equal(writes,first+1);assert.deepEqual(fs.readFileSync(target),binary);
 fs.writeFileSync(target,'corrupt fixture');await assert.rejects(core._tools(),/73/);assert.equal(fs.readFileSync(target,'utf8'),'corrupt fixture');
 core.dispose();console.log('PASS: actual shell fixture verifies decode/hash/atomic install/staging cleanup/idempotence/corrupt-file preservation; no device or networking used.');
}catch(e){console.error(e);process.exitCode=1;}
finally{assert(path.basename(fixture).startsWith('ufi-bootstrap-test-'));fs.rmSync(fixture,{recursive:true,force:true});}
