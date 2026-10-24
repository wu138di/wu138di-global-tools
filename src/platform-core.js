function createPlatformCore(options) {
  'use strict';
  const { sdk, scripts, request } = options || {};
  const pinSupport=createPinSupport(sdk);
  const BASE = '/data/adb/u30proxy';
  const JOBROOT = '/data/local/tmp/u30-ufi-jobs';
  const API_LIMIT = 4 * 1024 * 1024;
  const listeners = new Set();
  const transport = request || (typeof originFetch === 'function' ? originFetch : typeof fetch === 'function' ? fetch.bind(globalThis) : null);
  let unlocked = false;
  let disposed = false;
  let epoch = 0;
  let changing = false;
  let channelReady = false;
  let activeJob = null;
  const nodeProviders=new Map();
  let delayTail=Promise.resolve();
  let importAbort = null;
  const fail = message => new Error(message);
  const quote = value => "'" + String(value).replace(/'/g, "'\\''") + "'";
  function allowed() {
    if (disposed || !unlocked) throw fail('请先输入口令');
  }
  function session(check) { allowed(); if (check !== epoch) throw fail('会话已锁定'); }
  function progress(value) {
    const n = Math.max(0, Math.min(100, Math.round(Number(value) || 0)));
    listeners.forEach(callback => { try { callback(n); } catch (_) {} });
  }
  function textArg(value, limit = 1024) {
    if (typeof value !== 'string' || !value || /[\u0000-\u001f\u007f]/.test(value) || new TextEncoder().encode(value).length > limit) throw fail('参数无效');
    return value;
  }
  function envelope(command) {
    return '/system/bin/sh -c ' + quote(command) + '\nr=$?\nprintf "\\n__U30_RC__=%s\\n" "$r"';
  }
  let sdkTail=Promise.resolve();
  function root(command,check=epoch) {
    const run=()=>rootOnce(command,check);
    const result=sdkTail.then(run,run);sdkTail=result.catch(()=>{});return result;
  }
  async function rootOnce(command, check = epoch) {
    session(check);
    if (typeof sdk !== 'function') throw fail('请在 UFI-TOOLS 中打开');
    let result;
    try { result = await sdk(envelope(command), 20000); }
    catch (_) { throw fail('设备连接中断'); }
    session(check);
    if (!result || result.success !== true) throw fail('请登录 UFI-TOOLS 并开启高级功能');
    const output = String(result.content == null ? '' : result.content);
    if (output.length > API_LIMIT + 1024) throw fail('设备响应过大');
    const marker = output.match(/(?:^|\n)__U30_RC__=(\d+)\s*$/);
    if (!marker) throw fail('设备响应未确认');
    if (Number(marker[1]) !== 0) throw fail('设备操作失败（' + marker[1] + '）');
    return output.slice(0, marker.index).trim();
  }
  function bridgeCommand(op, args = []) {
    if (!scripts || typeof scripts.bridge !== 'string') throw fail('组件缺失，请重新导入插件');
    return '/system/bin/sh -c ' + quote(scripts.bridge) + ' -- ' + [op, ...args].map(quote).join(' ');
  }
  async function bridge(op, args, check = epoch) { return root(bridgeCommand(op, args), check); }
  function parse(value) {
    try { return JSON.parse(value); } catch (_) { throw fail('设备数据格式异常'); }
  }
  function object(value) { if (!value || typeof value !== 'object' || Array.isArray(value)) throw fail('设备数据格式异常'); return value; }
  async function api(op, args = [], check = epoch) { return object(parse(await bridge(op, args, check))); }
  async function status() {
    const check = epoch;
    const output = await bridge('status', [], check);
    const value = Object.create(null);
    const names = new Set(['deployment', 'core', 'enabled', 'transparent', 'autostart', 'subscription', 'controller', 'input_protection', 'admin', 'watchdog', 'regional_rules', 'domestic_rules']);
    output.split(/\r?\n/).forEach(line => {
      const match = line.match(/^([a-z_]+)=([a-z_-]+)$/);
      if (match && names.has(match[1])) value[match[1]] = match[2];
    });
    if (!value.core && value.deployment !== 'missing') throw fail('设备状态未确认');
    return value;
  }
  async function proxies() {
    const nodes=object((await api('proxies')).proxies);
    const providers=object((await api('providers')).providers);
    nodeProviders.clear();
    for (const [providerName,provider] of Object.entries(providers)) {
      if (!provider || !Array.isArray(provider.proxies)) continue;
      for (const node of provider.proxies) {
        if (!node || typeof node.name!=='string' || typeof node.type!=='string') continue;
        nodeProviders.set(node.name,providerName);
        if (!Object.hasOwn(nodes,node.name)) Object.defineProperty(nodes,node.name,{value:node,enumerable:true,writable:true,configurable:true});
      }
    }
    return nodes;
  }
  async function rules() { const value = (await api('rules')).rules; if (!Array.isArray(value)) throw fail('规则数据异常'); return value; }
  async function connections() {
    const value = await api('connections');
    if (value.connections === null) value.connections=[];
    if (!Array.isArray(value.connections)) throw fail('连接数据异常');
    for (const field of ['downloadTotal', 'uploadTotal', 'memory']) {
      if (typeof value[field] !== 'number' || !Number.isFinite(value[field]) || value[field] < 0) value[field] = 0;
    }
    return value;
  }
  async function snapshot() {
    const state = await status();
    const empty = { status: state, mode: 'rule', proxies: {}, rules: [], connections: { connections: [], downloadTotal: 0, uploadTotal: 0, memory: 0 } };
    if (state.deployment === 'missing' || state.subscription !== 'validated' || state.core !== 'running' || state.controller !== 'authenticated-ready') return empty;
    const [config, nodes, ruleList, links] = await Promise.all([api('mode'), proxies(), rules(), connections()]);
    if (!['rule', 'global', 'direct'].includes(config.mode)) throw fail('运行模式异常');
    return { status: state, mode: config.mode, proxies: nodes, rules: ruleList, connections: links };
  }
  async function mutation(operation) {
    allowed();
    if (changing) throw fail('上一步正在处理');
    const check = epoch;
    changing = true;
    progress(0);
    try { const value = await operation(check); session(check); progress(100); return value; }
    finally { changing = false; }
  }
  function id() {
    const data = new Uint32Array(3);
    if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') crypto.getRandomValues(data);
    else for (let n = 0; n < data.length; n++) data[n] = Math.floor(Math.random() * 0xffffffff);
    return 'platform-' + Date.now() + '-' + Array.from(data, n => n.toString(16)).join('');
  }
  async function job(script, check) {
    if (typeof script !== 'string' || !script) throw fail('设备脚本缺失');
    const name = id();
    const path = JOBROOT + '/' + name;
    const runner = '#!/system/bin/sh\numask 077\nD=' + quote(path) + '\n/system/bin/sh "$D/task.sh" >"$D/private.log" 2>&1\nr=$?\nrm -f "$D/task.sh" "$D/runner.sh"\nprintf "%s\\n" "$r" > "$D/result.tmp"\nmv "$D/result.tmp" "$D/result"\nexit "$r"\n';
    const launch = 'set -e\numask 077\ntest ! -L ' + quote(JOBROOT) + '\nmkdir -p ' + quote(JOBROOT) + '\nchmod 700 ' + quote(JOBROOT) +
      '\ntest ! -e ' + quote(path) + '\nmkdir ' + quote(path) + '\nchmod 700 ' + quote(path) + '\nprintf %s ' + quote(script) + ' > ' + quote(path + '/task.sh') +
      '\nprintf %s ' + quote(runner) + ' > ' + quote(path + '/runner.sh') + '\nchmod 700 ' + quote(path + '/task.sh') + ' ' + quote(path + '/runner.sh') +
      '\n/system/bin/sh -n ' + quote(path + '/task.sh') + '\nnohup /system/bin/sh ' + quote(path + '/runner.sh') + ' >/dev/null 2>&1 </dev/null &\nprintf "started\\n"';
    await root(launch, check);
    activeJob = name;
    const deadline = Date.now() + 15 * 60 * 1000;
    let count = 0;
    try {
      while (Date.now() < deadline) {
        session(check);
        const output = await root('if [ -f ' + quote(path + '/result') + ' ]; then r=$(cat ' + quote(path + '/result') + '); case "$r" in ""|*[!0-9]*) exit 65;; esac; printf "__U30_JOB_RC__=%s\\n" "$r"; rm -rf ' + quote(path) + '; else printf "pending\\n"; fi', check);
        const done = output.match(/^__U30_JOB_RC__=(\d+)$/);
        if (done) { if (Number(done[1]) !== 0) throw fail('后台任务失败（' + done[1] + '）'); return { ok: true }; }
        progress(Math.min(90, 8 + ++count * 2));
        await new Promise(resolve => setTimeout(resolve, 1500));
      }
      throw fail('任务仍在后台，请稍后刷新');
    } finally { activeJob = null; }
  }
  async function installChannel(check) {
    const initial=await status();
    if(initial.deployment==='missing')throw fail('请先安装组件');
    if(channelReady){if(initial.core!=='running')await job(bridgeCommand('management_start'),check);return;}
    if(!scripts || typeof scripts.update!=='string') throw fail('更新组件缺失');
    const updater=BASE+'/update.sh',backup=BASE+'/secret/global-v1-update';
    await root('set -e\numask 077\ntest ! -L '+quote(updater)+'\ntest ! -L '+quote(backup)+'\nmkdir -p '+quote(backup)+'\nchmod 700 '+quote(backup)+'\nif [ ! -e '+quote(backup+'/update.original.sh')+' ]; then cp -p '+quote(updater)+' '+quote(backup+'/update.original.sh')+'; fi\nprintf %s '+quote(scripts.update)+' > '+quote(backup+'/candidate.sh')+'\n/system/bin/sh -n '+quote(backup+'/candidate.sh')+'\nchmod 700 '+quote(backup+'/candidate.sh')+'\nmv '+quote(backup+'/candidate.sh')+' '+quote(updater),check);

    if (!scripts || typeof scripts.subscriptionBridge !== 'string') throw fail('订阅组件缺失');
    const dest = BASE + '/admin/cgi-bin/platform-subscription.cgi';
    const save = BASE + '/secret/platform-channel';
    const rollback = '#!/system/bin/sh\nset -eu\nD=' + quote(save) + '\nF=' + quote(dest) + '\ntest ! -L "$F"\nif [ -f "$D/previous.cgi" ]; then cp "$D/previous.cgi" "$F"; chmod 700 "$F"; elif [ -f "$D/previous.absent" ]; then rm -f "$F"; else exit 78; fi\n' + '\nif [ -f /data/adb/u30proxy/secret/global-v1-update/update.original.sh ]; then cp -p /data/adb/u30proxy/secret/global-v1-update/update.original.sh /data/adb/u30proxy/update.sh; fi\n';
    await root('set -e\numask 077\ntest -x ' + quote(BASE + '/control.sh') + '\ntest -d ' + quote(BASE + '/admin/cgi-bin') + '\ntest ! -L ' + quote(BASE + '/admin/cgi-bin') + '\ntest ! -L ' + quote(dest) + '\ntest ! -L ' + quote(save) +
      '\nmkdir -p ' + quote(save) + '\nchmod 700 ' + quote(save) + '\nif [ ! -f ' + quote(save + '/previous.cgi') + ' ] && [ ! -f ' + quote(save + '/previous.absent') + ' ]; then if [ -f ' + quote(dest) + ' ]; then cp ' + quote(dest) + ' ' + quote(save + '/previous.cgi') + '; else touch ' + quote(save + '/previous.absent') + '; fi; fi' +
      '\nprintf %s ' + quote(rollback) + ' > ' + quote(save + '/rollback.sh') + '\nchmod 700 ' + quote(save + '/rollback.sh') +
      '\nprintf %s ' + quote(scripts.subscriptionBridge) + ' > ' + quote(save + '/candidate.cgi') + '\n/system/bin/sh -n ' + quote(save + '/candidate.cgi') + '\nchmod 700 ' + quote(save + '/candidate.cgi') + '\nmv ' + quote(save + '/candidate.cgi') + ' ' + quote(dest) + '\nprintf "ready\\n"', check);
    if((await status()).core!=='running') await job(bridgeCommand('management_start'),check);
    channelReady=true;
  }
  async function assignAfterImport(check) {
    session(check);
    const state=await status(),nodes=await proxies();
    if (state.subscription!=='validated' || !Object.values(nodes).some(n=>n && !Array.isArray(n.all) && !['Direct','Reject','RejectDrop','Pass','Compatible','DNS'].includes(n.type))) throw fail('节点未就绪');
    return {ok:true,routing:'preserved'};
  }
  async function importSubscription(value,kind='subscription') {
    allowed();
    let parsed;
    if(kind==='yaml') {
      if(typeof value!=='string' || !value.trim() || new TextEncoder().encode(value).length>1048576 || !/^(?:proxies|"proxies"|'proxies')\s*:/m.test(value)) throw fail('YAML 格式错误');
    } else {
      if(typeof value!=='string' || !value || value!==value.trim() || /[\u0000-\u0020\u007f]/.test(value) || new TextEncoder().encode(value).length>8192) throw fail('请输入 HTTPS 订阅');
      try{parsed=new URL(value);}catch(_){throw fail('请输入 HTTPS 订阅');}
      if(parsed.protocol!=='https:' || !parsed.hostname || parsed.username || parsed.password || parsed.hash) throw fail('请输入 HTTPS 订阅');
    }
    return mutation(async check => {
      if (!transport) throw fail('订阅通道未就绪');
      await installChannel(check);
      const info = object(parse(await bridge('import_ticket', [], check)));
      if (typeof info.ticket !== 'string' || !/^[a-f0-9]{64}$/.test(info.ticket)) throw fail('订阅通道未确认');
      const ticket = info.ticket;
      let accepted = false;
      importAbort = new AbortController();
      const timer = setTimeout(() => importAbort && importAbort.abort(), 20000);
      try {
        let response;
        try {
          response = await transport('http://192.168.0.1:9091/cgi-bin/platform-subscription.cgi?mode='+kind, {
            method: 'POST', credentials: 'omit', cache: 'no-store', mode: 'cors',
            headers: { 'Content-Type': 'text/plain;charset=UTF-8', Authorization: 'Bearer ' + ticket },
            body: value, signal: importAbort.signal
          });
        } catch (_) { throw fail('订阅提交失败，请重试'); }
        value = ''; parsed = null;
        session(check);
        if (!response || response.status !== 202) throw fail('订阅提交未确认');
        const result = await response.json().catch(() => null);
        if (!result || result.ok !== true || result.result !== 'started') throw fail('订阅提交未确认');
        accepted = true;
        clearTimeout(timer);
        importAbort = null;
        const deadline = Date.now() + 10 * 60 * 1000;
        let count = 0;
        while (Date.now() < deadline) {
          const output = await bridge('import_poll', [ticket], check);
          const done = output.match(/^__U30_IMPORT_RC__=(\d+)$/);
          if (done) { if (Number(done[1]) !== 0) {
              const reason=await bridge('import_error',[],check);
              const messages={download_http_403:'服务器拒绝订阅（HTTP 403）',download_http_401:'订阅认证失败（HTTP 401）',download_failed:'订阅下载失败',test_failed:'节点配置校验失败',format_rejected:'节点配置校验失败'};
              const error=fail(messages[reason]||'导入失败');error.code=reason;throw error;
            } return assignAfterImport(check, '导入'); }
          progress(Math.min(90, 12 + ++count * 2));
          await new Promise(resolve => setTimeout(resolve, 1500));
        }
        throw fail('订阅仍在后台更新，请稍后刷新');
      } finally {
        value = ''; parsed = null; clearTimeout(timer); importAbort = null;
        if (!accepted && unlocked && !disposed && check === epoch) { try { await bridge('import_cancel', [ticket], check); } catch (_) {} }
      }
    });
  }
  function lock() { unlocked = false; epoch++; if (importAbort) importAbort.abort(); importAbort = null; }
  return {
    async enter(pin) { if(disposed)return false;const attempt=++epoch;unlocked=false;const ok=await pinSupport.verify(String(pin));if(disposed||attempt!==epoch)return false;unlocked=ok;return ok; },
    getPinStatus(){return pinSupport.status();},
    changePin(current,next,confirm){return mutation(async()=>pinSupport.change(current,next,confirm));},
    lock,
    snapshot, status, proxies, rules, connections,
    setMode(mode) { if (!['rule', 'global', 'direct'].includes(mode)) return Promise.reject(fail('模式无效')); return mutation(check => api('set_mode', [mode], check)); },
    select(group, node) { return mutation(check => api('select', [encodeURIComponent(textArg(group)), JSON.stringify({ name: textArg(node) })], check)); },
    delay(node) {
      allowed();const check=epoch,original=textArg(node);
      const run=async()=>{
        session(check);
        if(!nodeProviders.has(original)) await proxies();
        const provider=nodeProviders.get(original),name=encodeURIComponent(original);
        const value=await api(provider?'provider_delay':'delay',provider?[encodeURIComponent(provider),name]:[name],check);
        if(typeof value.delay!=='number' || !Number.isFinite(value.delay) || value.delay<=0) throw fail('测速超时');
        return {delay:value.delay,measuredAt:Date.now()};
      };
      const result=delayTail.then(run,run);delayTail=result.catch(()=>{});return result;
    },
    importYaml(value){return importSubscription(value,'yaml');},
    diagnostics(){return bridge('diagnostics').then(output=>Object.fromEntries(output.split(/\r?\n/).filter(l=>/^[a-z_]+=[a-z0-9_-]+$/.test(l)).map(l=>l.split('='))));},
    importSubscription,
    refreshSubscription() { return mutation(async check => { await job(bridgeCommand('refresh'), check); return assignAfterImport(check, '更新'); }); },
    service(action) {
      if(!['start','enable','disable','restart','stop'].includes(action)) return Promise.reject(fail('操作无效'));
      return mutation(async check=>{
        if(action==='enable') {
          const before=await status();
          if(before.subscription!=='validated') throw fail('请先导入节点');
          if(before.core!=='running') await job(bridgeCommand('management_start'),check);
          const nodes=await proxies();let node='PROXY';const visited=new Set();
          while(nodes[node] && Array.isArray(nodes[node].all)) {
            if(visited.has(node)||visited.size>12) throw fail('代理组循环');
            visited.add(node);node=nodes[node].now;
          }
          if(!nodes[node] || ['Direct','Reject','RejectDrop','Pass','Compatible','DNS'].includes(nodes[node].type)) throw fail('请选择可用节点');
          const provider=nodeProviders.get(node),name=encodeURIComponent(node);
          let probe;
          try{probe=await api(provider?'provider_delay':'delay',provider?[encodeURIComponent(provider),name]:[name],check);}catch(_){throw fail('节点未连通，代理未开启');}
          if(!(Number(probe.delay)>0)) throw fail('节点未连通，代理未开启');
          const network=await bridge('diagnostics',[],check);
          if(!/^route=ready$/m.test(network) || !/^proxy_http=20[0-9]$/m.test(network)) throw fail('代理链路未就绪，保持直连');
        }
        return job(bridgeCommand(action),check);
      });
    },
    autostart(value) { if (typeof value !== 'boolean') return Promise.reject(fail('设置无效')); return mutation(check => bridge('autostart', [value ? 'yes' : 'no'], check).then(() => ({ ok: true }))); },
    install() { return mutation(async check=>{
      const before=await status();await job(scripts&&scripts.install,check);
      if(before.deployment==='missing'||before.core==='stopped'){await job(bridgeCommand('stop'),check);await job(bridgeCommand('disable'),check);}
      if(before.autostart!=='yes')await bridge('autostart',['no'],check);
      return {ok:true};
    }); },
    standard() { return mutation(check => job(scripts && scripts.standard, check)); },
    rollbackRules() { return mutation(check => job(bridgeCommand('rollback_rules'), check)); },
    closeConnection(value) { return mutation(check => api('close_connection', [encodeURIComponent(textArg(value, 128))], check)); },
    onProgress(callback) { if (typeof callback !== 'function') throw fail('回调无效'); listeners.add(callback); return () => listeners.delete(callback); },
    isBusy() { return changing; },
    activeJob() { return activeJob; },
    dispose() { lock(); disposed = true; listeners.clear(); }
  };
}
