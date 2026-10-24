function createPinSupport(sdk) {
  const codec=createPinCrypto();
  const file='/data/adb/u30proxy/secret/global-ui-pin.json';
  const quote=v=>"'"+String(v).replace(/'/g,"'\\''")+"'";
  async function command(script) {
    if(typeof sdk!=='function')throw new Error('请先登录 UFI-TOOLS');
    const wrapped='/system/bin/sh -c '+quote(script)+'\nr=$?\nprintf "\\n__U30_PIN_RC__=%s\\n" "$r"';
    const result=await sdk(wrapped,20000);
    if(!result||result.success!==true)throw new Error('请先登录 UFI-TOOLS');
    const out=String(result.content||''),marker=out.match(/(?:^|\n)__U30_PIN_RC__=(\d+)\s*$/);
    if(!marker||marker[1]!=='0')throw new Error('口令设置读取失败');
    return out.slice(0,marker.index).trim();
  }
  async function profile() {
    const raw=await command('set -e\ntest ! -L '+quote(file)+'\nif [ -f '+quote(file)+' ]; then cat '+quote(file)+'; else printf \'{"default":true}\'; fi');
    let p;try{p=JSON.parse(raw);}catch(_){throw new Error('口令设置损坏');}
    if(p.default===true&&Object.keys(p).length===1)return {default:true,raw};
    if(p.v!==1||p.iterations!==100000||!/^[a-f0-9]{32}$/.test(p.salt)||!/^[a-f0-9]{64}$/.test(p.hash))throw new Error('口令设置损坏');
    return {...p,raw};
  }
  function valid(pin){return typeof pin==='string'&&pin.length>=4&&pin.length<=64&&!/[\u0000-\u001f\u007f]/.test(pin);}
  function derive(pin,p){return codec.PBKDF2(pin,codec.enc.Hex.parse(p.salt),{keySize:8,iterations:p.iterations,hasher:codec.algo.SHA256}).toString();}
  function equal(a,b){let n=a.length^b.length;for(let i=0;i<Math.max(a.length,b.length);i++)n|=(a.charCodeAt(i)||0)^(b.charCodeAt(i)||0);return n===0;}
  function matches(pin,p){return valid(pin)&&(p.default?equal(pin,'2007'):equal(derive(pin,p),p.hash));}
  return {
    async status(){return {configured:!(await profile()).default};},
    async verify(pin){if(!valid(pin))return false;return matches(pin,await profile());},
    async change(current,next,confirm){
      if(!valid(next))throw new Error('口令需为 4–64 位');
      if(next!==confirm)throw new Error('两次口令不一致');
      const before=await profile();
      if(!matches(current,before))throw new Error('当前口令错误');
      if(current===next)throw new Error('新口令与当前相同');
      const value={v:1,salt:codec.lib.WordArray.random(16).toString(),iterations:100000};
      value.hash=derive(next,value);
      const body=JSON.stringify(value),expected=before.default?'absent':codec.SHA256(before.raw).toString();
      const check=expected==='absent'?'test ! -e '+quote(file):'test "$(sha256sum '+quote(file)+' | /data/adb/magisk/busybox awk \'{print $1}\')" = '+quote(expected);
      await command('set -e\numask 077\ntest -d /data/adb/u30proxy/secret\ntest ! -L '+quote(file)+'\n'+check+'\nF='+quote(file)+'.new.$$\ntrap \'rm -f "$F"\' EXIT\nprintf %s '+quote(body)+' > "$F"\nchmod 600 "$F"\nmv "$F" '+quote(file)+'\nprintf saved');
      return {ok:true,configured:true};
    }
  };
}
