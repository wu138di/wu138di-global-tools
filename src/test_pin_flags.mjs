import fs from 'node:fs';import vm from 'node:vm';import crypto from 'node:crypto';import assert from 'node:assert/strict';
const here=new URL('.',import.meta.url),read=f=>fs.readFileSync(new URL(f,here),'utf8');
const ctx=vm.createContext({crypto:{getRandomValues:crypto.webcrypto.getRandomValues.bind(crypto.webcrypto)}});
vm.runInContext(['pin-crypto.js','pin-support.js','flags.js'].map(read).join('\n'),ctx);
const commands=[];let stored=null;
const sdk=async command=>{
 commands.push(command);const part=command.slice('/system/bin/sh -c '.length,command.lastIndexOf('\nr=$?')),plain=part.slice(1,-1).replaceAll("'\\''","'");
 const body=plain.match(/printf %s '(\{[^']+\})'/);
 let out;
 if(body){stored=body[1];out='saved';}else out=stored||'{"default":true}';
 return {success:true,content:out+'\n__U30_PIN_RC__=0\n'};
};
const pin=ctx.createPinSupport(sdk),fixture='Test-PIN-fixture-42';
assert.equal((await pin.status()).configured,false);assert(await pin.verify('2007'));assert(!await pin.verify('bad'));
await assert.rejects(pin.change('wrong',fixture,fixture),/当前口令错误/);assert.equal(stored,null);
await assert.rejects(pin.change('2007',fixture,'other'),/不一致/);assert.equal(stored,null);
await pin.change('2007',fixture,fixture);assert(stored&&!stored.includes(fixture));
const data=JSON.parse(stored);assert.equal(data.hash,crypto.pbkdf2Sync(fixture,Buffer.from(data.salt,'hex'),100000,32,'sha256').toString('hex'));
const reloaded=ctx.createPinSupport(sdk);assert.equal((await reloaded.status()).configured,true);assert(!await reloaded.verify('2007'));assert(await reloaded.verify(fixture));
assert(!commands.some(c=>c.includes(fixture)));assert(!commands.some(c=>c.includes("'2007'")));
const saved=stored;stored='{broken';await assert.rejects(reloaded.verify('2007'),/损坏/);stored=saved;
for(const [name,code] of [['HK Hong Kong 04','HK'],['JP Japan 03','JP'],['TW Taiwan 01','TW'],['SG Singapore 02','SG'],['US USA Seattle 01','US'],['BO Bombay 02','IN'],['🇯🇵 JP WU138DI AU','JP'],['UK London','GB'],['德国 01','DE'],['法国','FR'],['KR Seoul','KR'],['Unknown',''],['剩余流量 1316 GB',''],['🇧🇴 Bombay 02','BO']]){
 const f=ctx.getNodeFlag(name);assert.equal(f.code,code,name);assert(f.src.startsWith('data:image/svg+xml;'));assert(decodeURIComponent(f.src).includes('<svg'));
}
const report={result:'passed',checks:['device-scoped default and custom PIN status','current PIN verification and confirmation mismatch rejection','salted PBKDF2-SHA256 matches Node native implementation','fresh session accepts changed PIN and rejects 2007','plain PIN never enters device commands or stored profile','corrupt profile fails closed instead of default fallback','HTTP-LAN browser compatibility without crypto.subtle','14 country/region recognition cases; embedded SVG flags need no CDN']};
fs.writeFileSync(new URL('test_pin_flags_result.json',here),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
