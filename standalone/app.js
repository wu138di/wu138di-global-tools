function createStandaloneCore(request = window.fetch.bind(window)) {
  let csrf = '', unlocked = false, busy = false, generation = 0, disposed = false;
  const listeners = new Set();
  const messages = {
    PIN_CURRENT_WRONG:'当前口令错误', PIN_CONFIRM:'两次口令不一致', PIN_SAME:'新口令与当前相同', PIN_LENGTH:'口令需为 4–64 位',
    NODE_UNREACHABLE:'节点未连通，代理未开启', PROXY_NOT_READY_DIRECT_PRESERVED:'代理链路未就绪，保持直连',
    SELECT_NODE_FIRST:'请选择可用节点', IMPORT_NODES_FIRST:'请先导入节点'
  };
  function progress(stage) { for (const fn of listeners) fn(typeof stage === 'number' ? stage : {stage}); }
  async function call(path, body, method = 'POST') {
    const response = await request(path, {method, credentials:'same-origin', cache:'no-store', redirect:'error',
      headers:method === 'POST' ? {'Content-Type':'application/json', 'X-CSRF-Token':csrf} : {},
      ...(method === 'POST' ? {body:JSON.stringify(body || {})} : {})});
    const value = await response.json();
    if (!response.ok) {
      const error = new Error(messages[value.code] || '设备操作失败'); error.safeCode = value.code;
      if (response.status === 401 && unlocked) { unlocked = false; csrf = ''; generation++; window.dispatchEvent(new Event('global-session-expired')); }
      throw error;
    }
    return value;
  }
  function allowed() { if (!unlocked || disposed) throw new Error('请先输入口令'); }
  const read = (action, args = []) => { allowed(); return call('/api/read', {action,args}); };
  async function action(name, args = [], value = '') {
    allowed(); if (busy) throw new Error('上一步正在处理'); busy = true;
    const check = generation;
    try {
      progress(0); const started = await call('/api/action',{action:name,args,value}); value = '';
      const deadline = Date.now() + 15 * 60 * 1000;
      while (Date.now() < deadline) {
        if (!unlocked || generation !== check) throw new Error('会话已锁定');
        const state = await call('/api/job',null,'GET');
        if (state.id !== started.id) throw new Error('任务状态已变化');
        if (state.state === 'done') { progress(100); return state.result; }
        if (state.state === 'failed') { const error = new Error(messages[state.code] || '设备操作失败');error.safeCode = state.code;throw error; }
        progress(state.stage || '处理中');await new Promise(resolve => setTimeout(resolve,1000));
      }
      throw new Error('后台任务仍在运行，请稍后刷新');
    } finally { busy = false; }
  }
  return {
    async enter(pin) {
      const check = ++generation;unlocked = false;
      try { const result = await call('/api/login',{pin:String(pin)});if (disposed || check !== generation) return false;csrf=result.csrf;unlocked=true;return true; }
      catch (error) { if(error.safeCode === 'PIN_WRONG') return false;throw error; }
    },
    getPinStatus:()=>call('/api/pin/status',null,'GET'),
    changePin:(current,next,confirm)=>call('/api/pin/change',{current,next,confirm}),
    lock() { const old = csrf; unlocked=false;generation++;csrf='';if(old) request('/api/logout',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','X-CSRF-Token':old},body:'{}'}).catch(()=>{}); },
    snapshot:()=>read('snapshot'), status:()=>read('status'), proxies:()=>read('proxies'), rules:()=>read('rules'), connections:()=>read('connections'),
    delay:node=>read('delay',[node]), diagnostics:()=>read('diagnostics'),
    setMode:mode=>action('set_mode',[mode]), select:(group,node)=>action('select',[group,node]), closeConnection:id=>action('close_connection',[id]),
    install:()=>action('install'), service:name=>action(name), autostart:on=>action('autostart',[on?'yes':'no']),
    importSubscription:url=>action('import_subscription',[],url), importYaml:yaml=>action('import_yaml',[],yaml),
    refreshSubscription:()=>action('refresh'), standard:()=>action('standard'), rollbackRules:()=>action('rollback_rules'),
    onProgress(fn){listeners.add(fn);return()=>listeners.delete(fn);},isBusy:()=>busy,
    dispose(){this.lock();disposed=true;listeners.clear();}
  };
}
if (typeof document !== 'undefined') {
  const entry=document.getElementById('entry'),host=document.getElementById('host');
  const core=createStandaloneCore(),platform=mountPlatformUI({shadow:host.attachShadow({mode:'open'}),entry,icon:'/icon.png',core});
  window.addEventListener('global-session-expired',()=>{platform.close();platform.open();});
  platform.open();
}
