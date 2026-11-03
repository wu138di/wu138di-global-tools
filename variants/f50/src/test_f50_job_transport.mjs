import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import crypto from 'node:crypto';import os from 'node:os';import path from 'node:path';import {spawn} from 'node:child_process';
const here=new URL('.',import.meta.url),read=f=>fs.readFileSync(new URL(f,here),'utf8').replaceAll('\r\n','\n');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'ufi-job-test-')),jobs=path.join(fixture,'jobs'),tool=path.join(fixture,'busybox');
const unix=p=>p.replace(/^([A-Za-z]):/,(_,d)=>'/'+d.toLowerCase()).replaceAll('\\','/');
fs.writeFileSync(tool,'#!/bin/sh\na=$1;shift\ncase "$a" in sh) exec bash "$@";; nohup) exec /usr/bin/nohup "$@";; *) exec "$a" "$@";; esac\n');
let source=['pin-crypto.js','pin-support.js','platform-core.js'].map(read).join('\n');source=source.replace("const JOBROOT = '/data/local/tmp/u30-ufi-jobs'","const JOBROOT = "+JSON.stringify(unix(jobs))).replaceAll('/data/adb/u30proxy-tools/busybox',unix(tool));source=source.replace('  return {\n    async enter','  return {\n    _job:(s)=>job(s,epoch),\n    async enter');
const ctx=vm.createContext({URL,TextEncoder,AbortController,crypto:crypto.webcrypto,setTimeout,clearTimeout});vm.runInContext(source,ctx);
let chunks=0,largest=0;async function sdk(command){
 if(command.includes('__U30_PIN_RC__'))return {success:true,content:'{"default":true}\n__U30_PIN_RC__=0\n'};
 largest=Math.max(largest,Buffer.byteLength(command));assert(Buffer.byteLength(command)<20000,'overlarge SDK command');if(command.includes(' >> '))chunks++;
 const wrapped=command.slice('/system/bin/sh -c '.length,command.lastIndexOf('\nr=$?'));
 const plain=wrapped.slice(1,-1).replaceAll("'\\''","'").replaceAll('/system/bin/sh','bash');
 const shell="shopt -s expand_aliases; alias nohup='false ';\n(\n"+plain+"\n)\nr=$?\nprintf '\\n__U30_RC__=%s\\n' \"$r\"\n";
 const output=await new Promise((resolve,reject)=>{const p=spawn('C:/Program Files/Git/bin/bash.exe',['-s'],{windowsHide:true});let stdout='',stderr='';p.stdout.on('data',d=>stdout+=d);p.stderr.on('data',d=>stderr+=d);p.on('error',reject);p.on('close',code=>code===0?resolve({stdout}):reject(new Error('fixture bash exit '+code+': '+stderr)));p.stdin.end(shell);});
 return {success:true,content:output.stdout};
}
try{
 const core=ctx.createPlatformCore({sdk,scripts:{}});assert(await core.enter('2007'));
 assert.equal((await core._job('#'+('x'.repeat(90000))+'\nprintf test_ok\\n\nexit 0\n')).ok,true);assert.deepEqual(fs.readdirSync(jobs),[]);assert(chunks>=8);
 await assert.rejects(core._job("printf 'PRIVATE_FIXTURE_TOKEN\\nU30_PLUGIN_ERROR: MOCK_CAPABILITY_FAILED\\n' >&2\nexit 37\n"),e=>e.safeCode==='MOCK_CAPABILITY_FAILED'&&!e.message.includes('PRIVATE_FIXTURE'));
 const failed=path.join(jobs,fs.readdirSync(jobs)[0]);assert.equal(fs.readFileSync(path.join(failed,'result'),'utf8'),'37\n');assert.equal(fs.readFileSync(path.join(failed,'runner.started'),'utf8'),'started');assert(fs.readFileSync(path.join(failed,'private.log'),'utf8').includes('PRIVATE_FIXTURE_TOKEN'));
 core.dispose();const report={test:'actual_shell_chunked_background_job',result:'PASS',largest_sdk_command_bytes:largest,chunks,success_exit:0,failure_exit:37,failed_root_log_preserved:true,outer_nohup_alias_ignored:true,device_tested:false};fs.writeFileSync(new URL('test_f50_job_transport_result.json',here),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}catch(e){console.error(e);process.exitCode=1;}
finally{assert(path.basename(fixture).startsWith('ufi-job-test-'));fs.rmSync(fixture,{recursive:true,force:true});}
