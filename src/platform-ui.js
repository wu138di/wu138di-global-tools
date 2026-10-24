function mountPlatformUI({ shadow, entry, icon, core }) {
  const doc = shadow.ownerDocument || document;
  const win = doc.defaultView || window;
  const state = {
    unlocked: false, tab: 'overview', snapshot: null, selectedGroup: '',
    ruleQuery: '', connectionQuery: '', delays: new Map(), mutating: false,
    operation: '', open: false, disposed: false, generation: 0,
    previousTraffic: null, uploadRate: 0, downloadRate: 0, readError: false
  };
  let previousFocus = null, pollTimer = null, toastTimer = null, refreshPromise = null, refreshGeneration = -1;
  const tabs = [
    ['overview', '概览', '⌂'], ['proxies', '节点', '◈'], ['subscription', '订阅', '↻'],
    ['rules', '规则', '≡'], ['connections', '连接', '⇄'], ['diagnostics','检测','⌁'], ['settings', '设置', '⚙']
  ];
  const h = (tag, attrs, ...children) => {
    const node = doc.createElement(tag);
    for (const [key, value] of Object.entries(attrs || {})) {
      if (key === 'class') node.className = value;
      else if (key === 'text') node.textContent = value == null ? '' : String(value);
      else if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2).toLowerCase(), value);
      else if (key in node && !key.startsWith('aria-') && key !== 'role') node[key] = value;
      else node.setAttribute(key, String(value));
    }
    for (const child of children.flat()) {
      if (child == null || child === false) continue;
      node.appendChild(typeof child === 'string' || typeof child === 'number' ? doc.createTextNode(String(child)) : child);
    }
    return node;
  };
  const style = h('style', { text: `
    :host{color-scheme:dark;font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif;font-size:14px;color:#f7e9f0}
    *,*::before,*::after{box-sizing:border-box} [hidden]{display:none!important}
    button,input,select{font:inherit}button{cursor:pointer}button:disabled{cursor:default;opacity:.42}
    button,a,input,summary,select{outline:none}button:focus-visible,a:focus-visible,input:focus-visible,summary:focus-visible,select:focus-visible{outline:3px solid #e4a1bf;outline-offset:3px}
    .veil{position:fixed;inset:0;z-index:2147483640;background:#10080fbd;backdrop-filter:blur(14px);display:grid;place-items:center;padding:24px}
    .window{width:min(1110px,100%);height:min(820px,calc(100dvh - 48px));position:relative;border:1px solid #ffffff12;border-radius:25px;overflow:hidden;background:#251a23;box-shadow:0 35px 110px #0008;display:flex}
    .login{width:100%;display:grid;place-items:center;position:relative;background:radial-gradient(ellipse at 18% 12%,#bb749228,transparent 50%),radial-gradient(ellipse at 90% 90%,#c78caa1b,transparent 50%)}
    .login-box{width:min(340px,calc(100% - 48px));text-align:center}.avatar{object-fit:cover;flex:none;border-radius:25%;box-shadow:0 8px 24px #0003}.login-avatar{width:82px;height:82px;margin-bottom:21px}
    h1,h2,h3,p{margin:0}.login h1{font-size:25px;letter-spacing:.02em;font-weight:720}.subtle{color:#bca6b5}.login .subtle{margin:9px 0 30px;font-size:12px;letter-spacing:.16em}
    .field{width:100%;height:48px;border:1px solid #ffffff16;border-radius:13px;background:#35242f;color:#fff0f7;padding:0 15px;transition:border-color .15s}.field::placeholder{color:#a58b9a}.field:focus{border-color:#d892b4}
    .login .field{text-align:center;font-size:18px;letter-spacing:.2em;height:53px}.primary{background:linear-gradient(110deg,#aa587d,#8f466b)!important;color:white!important;border-color:transparent!important;font-weight:650;box-shadow:0 6px 22px #b7678b20}.login .primary{width:100%;margin-top:13px;height:49px}
    .btn{min-height:44px;display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:10px 16px;border:1px solid #ffffff12;border-radius:12px;background:#3c2935;color:#f0dce7;white-space:nowrap;transition:background .15s,transform .15s}.btn:hover:not(:disabled){background:#4a3341}.btn:active:not(:disabled){transform:translateY(1px)}.btn.small{padding:8px 12px;font-size:12px}.btn.danger{color:#ffb1c5;background:#492634;border-color:#fb829219}
    .icon-btn{width:44px;height:44px;display:inline-grid;place-items:center;padding:0;border:1px solid #ffffff0e;border-radius:12px;background:#33232d;color:#cfb6c5;font-size:20px;flex:none}.icon-btn:hover:not(:disabled){background:#47303e;color:#fff}.close{position:absolute;right:17px;top:16px;z-index:3}.login>.close{background:#39263180}
    .brand-footer{display:flex;align-items:center;justify-content:center;gap:7px;font-size:11px;color:#b098a7;letter-spacing:.02em}.login>.brand-footer{position:absolute;bottom:24px}.footer-avatar{width:19px;height:19px;border-radius:6px;object-fit:cover}
    .platform{display:flex;width:100%;min-height:0}.sidebar{width:190px;flex:none;padding:27px 16px 21px;display:flex;flex-direction:column;background:#2d202a;border-right:1px solid #ffffff08}.brand{display:flex;align-items:center;gap:11px;padding:0 5px 29px}.brand .avatar{width:38px;height:38px;border-radius:12px}.brand-title{font-size:13px;font-weight:700;line-height:1.6;letter-spacing:.03em}.brand small{display:block;color:#b297a8;font-size:10px;font-weight:500;letter-spacing:.1em}
    .nav{display:flex;flex-direction:column;gap:7px}.nav-btn{border:0;background:none;color:#c0a7b8;display:flex;align-items:center;text-align:left;min-height:47px;border-radius:12px;gap:13px;padding:0 17px;font-weight:550}.nav-btn:hover{background:#ffffff05;color:#f4e2ee}.nav-btn.active{background:#d889ae1c;color:#f1bdd5}.nav-symbol{font-size:22px;width:23px;text-align:center;line-height:1}.sidebar .brand-footer{margin-top:auto;padding-top:24px;white-space:nowrap}
    .workspace{flex:1;min-width:0;display:flex;flex-direction:column;background:radial-gradient(ellipse at 100% 0,#bd789e10,transparent 45%),#251a23}.topbar{height:91px;flex:none;display:flex;align-items:center;justify-content:space-between;padding:0 32px;border-bottom:1px solid #ffffff07}.page-title{font-size:24px;font-weight:690;letter-spacing:.01em}.top-actions{display:flex;align-items:center;gap:9px}.status-pill{display:flex;align-items:center;gap:7px;border:1px solid #ffffff0d;background:#34252e;padding:8px 11px;border-radius:99px;color:#bfa4b5;font-size:11px;margin-right:3px;white-space:nowrap}.dot{width:6px;height:6px;display:inline-block;border-radius:50%;background:#9f8193}.dot.live{background:#5bd5a3;box-shadow:0 0 11px #5bd5a336}
    .content{padding:27px 32px 28px;overflow:auto;min-height:0;flex:1;scrollbar-width:thin;scrollbar-color:#614351 transparent}.section-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:18px}.section-head h2{font-size:15px;font-weight:650}.section-head .subtle{font-size:11px}.row{display:flex;align-items:center;gap:11px}.wrap{flex-wrap:wrap}.spread{justify-content:space-between}.stack{display:flex;flex-direction:column;gap:14px}.card{border:1px solid #ffffff0b;border-radius:17px;background:#34252f;padding:21px}.card h3{font-size:13px;font-weight:600}.card-label{font-size:12px;color:#c1a7b8}.card-value{font-size:26px;font-weight:700;letter-spacing:-.04em;margin-top:11px}.card-caption{font-size:11px;color:#a98e9f;margin-top:7px}.card-icon{display:grid;place-items:center;width:34px;height:34px;border-radius:11px;background:#d689b315;color:#efb9d3;font-size:19px}
    .stats{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin-bottom:19px}.stat-unit{font-size:11px;color:#bca1b3;letter-spacing:0;font-weight:500;margin-left:5px}.hero{padding:25px;margin-bottom:18px;display:flex;align-items:center;justify-content:space-between;gap:22px;background:linear-gradient(115deg,#70445475,#35232f);border-color:#e5a5c518}.hero h2{font-size:21px;font-weight:650;margin:0 0 8px}.hero p{font-size:12px;color:#c6abbc}.power{width:64px;height:64px;border-radius:21px;flex:none;background:#ad5e85;border:0;color:#fff;font-size:27px;box-shadow:0 8px 35px #b96d942b}.power.on{background:#6bc8ae;color:#122e27;box-shadow:0 8px 35px #6bc8ae15}
    .segmented{display:flex;border-radius:12px;padding:4px;border:1px solid #ffffff08;background:#2a1c25;gap:4px}.segmented button{min-height:44px;flex:1;border:0;background:none;color:#bca0b2;border-radius:9px;font-size:12px;white-space:nowrap;padding:0 14px}.segmented button.active{background:#583447;color:#f6c8df;box-shadow:0 2px 8px #0002}.segmented button:hover:not(:disabled){color:#ffe4f1}
    .regions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}.region{padding:18px}.region-flag{font-size:21px;margin-bottom:12px}.region-title{font-size:13px;font-weight:600}.region-platform{font-size:11px;color:#b799ad;margin-top:5px}.region-node{margin-top:17px;font-size:11px;color:#e3b6cf;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.section-gap{margin-top:27px}.mini-label{font-size:11px;color:#bca0b3}.empty{padding:48px 20px;text-align:center;color:#b99caf}.empty-symbol{display:block;font-size:30px;color:#916d82;margin-bottom:13px}.empty p{font-size:12px;line-height:1.8}.empty .btn{margin-top:20px}.subscription-empty{padding:27px 20px}.subscription-empty .empty-symbol{font-size:25px;margin-bottom:9px}.subscription-empty .btn{margin-top:14px}.count{font-size:11px;border-radius:8px;background:#ffffff07;padding:4px 7px;color:#c0a4b5;font-weight:500}
    .group-tabs{display:flex;gap:8px;overflow:auto;scrollbar-width:none;margin-bottom:19px;padding-bottom:3px}.group-tab{border:1px solid #ffffff0d;border-radius:11px;background:#33232e;color:#c6a7bb;min-height:44px;white-space:nowrap;padding:0 14px;font-size:12px}.group-tab.active{border-color:#dd98b94d;background:#d786aa1c;color:#f4c0d9}.group-detail{color:#b497ab;font-size:11px;margin-top:5px}.node-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.node{display:flex;align-items:center;gap:4px;border:1px solid #ffffff0c;background:#33242e;border-radius:14px;min-width:0;padding:7px 9px 7px 5px}.node.selected{background:#d88baa1c;border-color:#e9a3c15e}.node-select{display:flex;gap:11px;align-items:center;min-height:54px;flex:1;min-width:0;text-align:left;border:0;background:none;color:#f1dce9;border-radius:10px;padding:6px 8px}.node-select:disabled{opacity:1;cursor:default}.node-mark{width:24px;height:24px;border:1px solid #765368;border-radius:8px;display:grid;place-items:center;color:#eac0d4;font-size:12px;flex:none}.selected .node-mark{background:#ad6186;border-color:#d68aaf;color:#fff}.node-name{display:block;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.node-type{display:block;color:#a7879d;font-size:10px;margin-top:5px}.latency{min-height:44px;min-width:49px;padding:0 7px;border:0;background:none;color:#b99aaf;border-radius:9px;font-size:11px}.latency:hover:not(:disabled){background:#ffffff05}.latency.fast{color:#6cc7a5}.latency.slow{color:#e0b36c}.latency.fail{color:#e78b9c}.badge{font-size:10px;padding:4px 8px;border-radius:7px;background:#d98daf1b;color:#e7b5cf}
    .subscribe-card{padding:24px}.subscribe-card .field{margin:19px 0 13px}.subscription-status{display:flex;align-items:center;gap:10px}.subscription-symbol{height:43px;width:43px;background:#d483ad1b;color:#f2bdd9;border-radius:14px;display:grid;place-items:center;font-size:23px}.subscription-state{font-size:16px;font-weight:650}.subscription-sub{font-size:11px;color:#b69aaf;margin-top:5px}.privacy-note{font-size:11px;color:#ab8c9f;margin:17px 2px 0}.search{height:44px;font-size:12px;margin-bottom:15px}.list{border:1px solid #ffffff0a;border-radius:15px;overflow:hidden;background:#32232d}.list-row{min-height:65px;padding:14px 17px;display:flex;align-items:center;gap:15px;border-bottom:1px solid #ffffff07}.list-row:last-child{border-bottom:0}.grow{flex:1;min-width:0}.truncate{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.rule-name,.connection-name{font-size:12px;color:#efd9e6}.rule-kind,.connection-meta{font-size:10px;color:#b092a6;margin-top:5px}.rule-target{color:#ebb5d0;font-size:11px;flex:none;max-width:35%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.connection-count{font-size:12px;color:#bba0b1}.connection-data{font-size:10px;color:#bea2b5;text-align:right;line-height:1.9;white-space:nowrap}.connection-close{border:0;background:none;width:44px;height:44px;color:#a6859a;border-radius:9px;font-size:18px}.connection-close:hover{background:#ffffff05;color:#d58c9e}
    .setting-row{display:flex;align-items:center;justify-content:space-between;min-height:68px;padding:10px 0;gap:14px;border-bottom:1px solid #ffffff07}.setting-row:last-child{border:0}.setting-name{font-size:13px;color:#efdbe8}.setting-desc{font-size:10px;color:#ae91a4;margin-top:5px}.switch-label{width:52px;height:44px;position:relative;display:flex;align-items:center;cursor:pointer;flex:none}.switch-label input{position:absolute;inset:0;opacity:0;width:100%;height:100%;margin:0;cursor:pointer}.switch-track{width:44px;height:25px;border-radius:20px;background:#654355;transition:background .15s;pointer-events:none}.switch-track::before{content:"";display:block;width:19px;height:19px;border-radius:50%;margin:3px;background:#e8d1dd;transition:transform .15s}.switch-label input:checked+.switch-track{background:#b96b91}.switch-label input:checked+.switch-track::before{transform:translateX(19px);background:white}.switch-label input:focus-visible+.switch-track{outline:3px solid #e69cbd;outline-offset:4px}.switch-label input:disabled+.switch-track{opacity:.4}.advanced{border:1px solid #ffffff0b;border-radius:15px;background:#33232e;padding:0 19px;margin-top:18px}.advanced summary{min-height:57px;display:flex;align-items:center;justify-content:space-between;cursor:pointer;color:#c0a3b6;font-size:12px;list-style:none}.advanced summary::-webkit-details-marker{display:none}.advanced summary::after{content:"⌄";font-size:18px;color:#9f7c92}.advanced[open] summary::after{transform:rotate(180deg)}.advanced .row{padding:0 0 19px}.advanced .btn{flex:1}
    .operation{display:flex;align-items:center;gap:10px;padding:12px 32px;background:#4e2f43;color:#ebbed5;font-size:11px;flex:none}.spinner{height:12px;width:12px;border:2px solid #d08cad44;border-top-color:#f5c1dc;border-radius:50%;animation:u30-spin .9s linear infinite}.operation-name{flex:1}.toast{position:absolute;bottom:23px;left:50%;transform:translateX(-50%);max-width:calc(100% - 38px);padding:12px 18px;border:1px solid #ffffff16;border-radius:12px;background:#593a4d;color:#f8deec;font-size:12px;box-shadow:0 10px 28px #0004;z-index:9;text-align:center;pointer-events:none}.toast.error{background:#532d40;color:#eab9c8}.footer-mobile{display:none}.loading{opacity:.55}.mobile-lock{display:none}
    @keyframes u30-spin{to{transform:rotate(360deg)}}
    @media(max-width:760px){.veil{padding:0}.window{width:100%;height:100dvh;border:0;border-radius:0}.sidebar{width:162px;padding:25px 12px 19px}.brand{gap:9px}.brand .avatar{width:33px;height:33px;border-radius:10px}.brand-title{font-size:11px}.brand small{font-size:9px}.nav-btn{padding:0 13px;gap:10px}.sidebar .brand-footer{font-size:10px;gap:4px}.footer-avatar{width:16px;height:16px}.topbar{height:82px;padding:0 23px}.content{padding:23px}.stats{gap:10px}.card{padding:17px}.card-value{font-size:22px}.regions{gap:10px}.region{padding:15px}.hero{padding:22px}.node-grid{grid-template-columns:1fr}.operation{padding:12px 23px}}
    @media(max-width:580px){.platform{padding-bottom:77px}.sidebar{position:absolute;bottom:0;width:100%;height:77px;z-index:3;border-right:0;border-top:1px solid #ffffff0b;padding:4px 8px calc(5px + env(safe-area-inset-bottom));background:#2d202af7;backdrop-filter:blur(15px);display:block}.sidebar .brand,.sidebar>.brand-footer{display:none}.nav{height:100%;display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:2px}.nav-btn{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:5px;font-size:10px;padding:5px 0;min-height:56px;border-radius:11px}.nav-symbol{font-size:21px;width:auto}.topbar{height:78px;padding:0 19px}.page-title{font-size:22px}.top-actions{gap:6px}.top-actions .icon-btn{width:44px;height:44px;background:none;border:0}.status-pill{padding:6px 8px;font-size:10px;margin:0}.content{padding:20px 18px 18px}.stats{gap:8px;margin-bottom:16px}.stats .card{padding:15px 12px;border-radius:14px}.card-label{font-size:10px}.card-value{font-size:20px;margin-top:13px}.stat-unit{font-size:9px;margin-left:3px}.card-caption{font-size:9px}.card-icon{width:26px;height:26px;font-size:15px;border-radius:9px}.stats .row{gap:3px}.hero{padding:22px 19px;margin-bottom:17px}.hero h2{font-size:19px}.hero p{font-size:11px}.power{width:58px;height:58px;border-radius:20px}.regions{gap:8px}.region{padding:15px 12px;border-radius:14px}.region-title{font-size:12px}.region-platform{font-size:10px}.region-node{font-size:10px;margin-top:14px}.section-gap{margin-top:23px}.node-grid{gap:10px}.section-head h2{font-size:14px}.section-head{margin-bottom:15px}.subscribe-card{padding:21px 18px}.subscribe-card .row{gap:8px}.subscribe-card .btn{flex:1;font-size:12px;padding:10px}.segmented button{padding:0 12px}.footer-mobile{display:flex;margin:27px 0 4px}.connection-data{font-size:9px}.list-row{padding:12px 13px;gap:10px}.connection-close{width:44px}.rule-target{max-width:30%;font-size:10px}.operation{padding:11px 19px}.toast{bottom:89px}.login .toast{bottom:75px}.advanced .row{flex-direction:column}.advanced .btn{width:100%}.login-avatar{width:77px;height:77px}}
    @media(prefers-reduced-motion:reduce){*,*::before,*::after{transition:none!important;animation:none!important}}
  ` });
  style.textContent += '\n    :host{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif;color:#342c40}\n    .veil{background:#e7dce988;backdrop-filter:blur(18px);padding:24px}\n    .window{width:min(1260px,100%);height:min(850px,calc(100dvh - 48px));border-radius:30px;border:1px solid #fff9;background:linear-gradient(100deg,#fdf9ffb8,#fff4fa8c),url("__GLOBAL_BG__") center/cover;box-shadow:0 32px 110px #623b6138;color:#342c40}\n    .login{background:linear-gradient(90deg,#ffffff55,#ffedf533)}\n    .login-box{padding:36px 30px;border:1px solid #fff9;border-radius:28px;background:#fff9;backdrop-filter:blur(24px);box-shadow:0 18px 55px #784b7720;width:min(390px,calc(100% - 40px))}\n    .login h1{font-size:24px;letter-spacing:-.04em;color:#3e3047}.login-avatar{width:76px;height:76px;border-radius:24px}.login .subtle{color:#8c7389;margin:10px 0 24px}\n    .sidebar{background:#fcf9ff9c;backdrop-filter:blur(24px);border-right:1px solid #fff8;width:210px;padding:30px 16px 22px}\n    .brand-title{font-size:15px;color:#46334e;line-height:1.6}.brand small{color:#94758d}.nav{gap:7px;margin-top:30px}.nav-btn{min-height:48px;border-radius:14px;color:#836e85;font-weight:550}.nav-btn.active{background:#e9dbf3cf;color:#69499a;box-shadow:0 3px 14px #75578c0b}.nav-btn:hover{background:#eee4f3b0}.nav-symbol{font-size:21px}\n    .workspace{background:#fff1}.topbar{background:#fff5;border-bottom:1px solid #fff8;padding:0 30px;height:85px;backdrop-filter:blur(18px)}.page-title{color:#493652;font-size:25px;letter-spacing:-.04em}.content{padding:26px 30px 30px;scrollbar-width:thin;scrollbar-color:#b8a2c366 transparent}\n    .card,.node,.advanced,.subscribe-card{background:#ffffffab;border:1px solid #ffffffb3;box-shadow:0 6px 24px #704c7610;border-radius:20px;backdrop-filter:blur(14px)}.node{border-radius:16px;box-shadow:none;min-height:78px}.node.selected{background:#eadbf2c9;border-color:#b399cf80}.node-name,.setting-name,.connection-name,.region-title,.section-head h2,.card-value{color:#46354e}.node-type,.card-label,.card-caption,.region-platform,.region-node,.stat-unit,.brand-footer,.mini-label,.subscription-sub{color:#8e7b94}.node-mark{border-color:#cbb9d6;color:#9b70b7}.selected .node-mark{background:#9e7ab9;border-color:#9e7ab9;color:white}\n    .hero{background:linear-gradient(110deg,#f6edfbd9,#fff0f4a1);border-color:#fff9;padding:28px}.hero h2{font-size:24px;color:#49364f}.hero p{display:none}.power{background:linear-gradient(135deg,#a68bc5,#ce9dc3);box-shadow:0 8px 24px #9865a329}.power.on{background:#74c8af;color:#fff}\n    .btn,.icon-btn,.group-tab,.segmented,.field{background:#ffffffa8;border-color:#cdbcd647;color:#765a85}.btn:hover:not(:disabled),.icon-btn:hover:not(:disabled){background:#f4eaf9}.primary{background:linear-gradient(105deg,#9a80ba,#bc91bd)!important;box-shadow:0 6px 18px #a58ab72b}.field{color:#4b3657}.field::placeholder{color:#aa96b0}.field:focus{border-color:#ad8ac5;box-shadow:0 0 0 4px #bba3d41c}.group-tab.active{background:#e4d6efb8;border-color:#bc9cd350;color:#76538c}.segmented button{color:#9b86a5}.segmented button.active{background:#fff9;color:#835899;box-shadow:0 2px 10px #8b6e9b14}.latency{color:#a18cab}.latency.fast{color:#359c7a}.latency.slow{color:#bd8b4d}.latency.fail{color:#cb6c88}.badge,.count{background:#eee2f48f;color:#9472aa}\n    .setting-row{border-bottom-color:#bda2cc1a}.setting-desc,.privacy-note,.subscription-sub{display:none}.subscription-state,.subscription-symbol{color:#80618f}.connection-meta,.rule-target{color:#9e7bb3}.list-row{background:#ffffff9c;border-color:#fff9}.empty,.empty p{color:#a18da9}.advanced summary{color:#8b6c9a}.switch-track{background:#cdbdd5}.switch-label input:checked+.switch-track{background:#ac88c3}.toast{background:#fffef4;color:#5b4267;border-color:#d9c7e4;box-shadow:0 8px 25px #60416321}.toast.error{color:#b75d76}.status-pill{background:#ffffffa6;color:#8c7797;border-color:#fff9}.subtle{color:#a18da9}.rule-row{border-color:#baa5c521}.close{background:#fff7}.yaml-area{height:170px;padding:14px;resize:vertical;line-height:1.6;font:12px ui-monospace,SFMono-Regular,Consolas,monospace;width:100%;border-radius:14px}.yaml-card{margin-top:20px}.yaml-card .row{margin-top:16px;gap:12px}.file-picker{max-width:100%;min-height:44px;color:#927a9c}.diagnostic-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:14px}.diagnostic-card{padding:22px}.diagnostic-card strong{display:block;margin-top:16px;color:#805795}.node-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}\n    @media(prefers-color-scheme:dark){.window{color:#f4e9f7;background:linear-gradient(100deg,#251d32e3,#382439b8),url("__GLOBAL_BG__") center/cover}.sidebar{background:#241c31b8}.topbar{background:#2d203a77}.login-box,.card,.node,.subscribe-card,.advanced{background:#302739c7;border-color:#ffffff15}.brand-title,.page-title,.node-name,.setting-name,.hero h2,.login h1,.region-title,.section-head h2,.card-value,.connection-name{color:#f2e5f8}.field,.btn,.icon-btn,.group-tab,.segmented,.list-row{background:#392e47b0;color:#dac7e7}.hero{background:linear-gradient(110deg,#46344edb,#403144b0)}.node.selected,.nav-btn.active{background:#71508477;color:#f5d7ff}.segmented button.active{background:#67507866;color:#f1d9ff}.toast{background:#3e2d4a;color:#f1d9ff}.status-pill{background:#3d2e4b;color:#cbb5db}.nav-btn{color:#bfa8cf}.nav-btn:hover{background:#62507455}}\n    @media(max-width:760px){.veil{padding:0}.window{height:100dvh;width:100%;border-radius:0}.sidebar{width:170px}.content{padding:20px}.topbar{padding:0 20px}.node-grid{grid-template-columns:1fr}}\n    @media(max-width:580px){.sidebar{width:100%;height:80px;bottom:0;background:#fbf7f2d9;padding:5px 4px}.nav{margin:0;grid-template-columns:repeat(7,1fr);gap:0}.nav-btn{min-height:60px;padding:4px 0;font-size:10px;gap:5px}.nav-symbol{font-size:20px}.platform{padding-bottom:80px}.topbar{height:74px;padding:0 16px}.content{padding:18px 16px}.diagnostic-grid{grid-template-columns:1fr}.stats .card{padding:15px 10px}.hero{padding:23px 18px}.hero h2{font-size:21px}.login-box{padding:30px 24px}.yaml-area{font-size:11px}.brand-footer{color:#a58dac}@media(prefers-color-scheme:dark){.sidebar{background:#302338eb}}}\n';
  style.textContent += '.file-picker::file-selector-button{border:0;border-radius:11px;background:#eee3f4;color:#88659d;padding:12px 16px;margin-right:12px;min-height:44px;font:inherit;cursor:pointer}.brand-title{white-space:nowrap}.brand small{white-space:nowrap;font-size:10px}.brand-title{font-size:16px}';
  style.textContent += '.node-mark{position:relative;width:36px;height:28px;min-width:36px;border:0!important;border-radius:5px;background:none!important;overflow:visible}.node-flag{width:34px;height:23px;display:block;border-radius:4px;object-fit:cover;box-shadow:0 1px 5px #24132e20}.selected-tick{position:absolute;right:-3px;bottom:-3px;display:grid;place-items:center;width:15px;height:15px;border:2px solid white;border-radius:50%;background:#9e7ab9;color:#fff;font-size:9px;line-height:1}.region-flag .node-flag{width:38px;height:26px}.pin-settings{margin-top:22px;display:grid;gap:12px}.pin-settings .section-head{margin-bottom:2px}.pin-settings .btn{justify-self:start;min-width:120px}';
  const avatar = (className) => h('img', { class: className || 'avatar', src: icon || '', alt: '', draggable: false });
  const footer = (extra) => h('div', { class: `brand-footer ${extra || ''}` }, avatar('footer-avatar'), 'Made by wu138di');
  const modal = h('div', { class: 'veil', hidden: true, 'data-testid': 'platform-modal' });
  const frame = h('section', { class: 'window', role: 'dialog', 'aria-modal': 'true', 'aria-label': 'wu138di 全球上网', tabIndex: -1 });
  const login = h('section', { class: 'login' });
  const pin = h('input', { class: 'field', type: 'password', name: 'u30-platform-pin', placeholder: '输入登录口令', autocomplete: 'off', inputMode: 'numeric', maxLength: 64, 'aria-label': '平台口令', 'data-testid': 'platform-pin' });
  const enter = h('button', { class: 'btn primary', type: 'submit', text: '进入', 'data-testid': 'platform-enter' });
  const loginForm = h('form', { class: 'login-box', autocomplete: 'off', 'data-testid': 'platform-login-form', onSubmit: async (event) => {
    event.preventDefault();
    if (enter.disabled) return;
    const value = pin.value;
    const loginToken = state.generation;
    pin.value = '';
    enter.disabled = true;
    enter.textContent = '正在进入';
    try {
      const accepted = await core.enter(value);
      if (state.disposed || !state.open || loginToken !== state.generation) return;
      if (!accepted) { showToast('口令错误', true); focusSoon(pin); return; }
      state.unlocked = true;
      state.generation += 1;
      login.hidden = true;
      platform.hidden = false;
      showTab('overview');
      startPolling();
      refresh().catch(() => {});
    } catch (_) { showToast('进入失败，请重试', true); }
    finally { enter.disabled = false; enter.textContent = '进入'; }
  } }, avatar('avatar login-avatar'), h('h1', { text: 'wu138di 全球上网' }), h('p', { class: 'subtle', text: 'V1.0' }), pin, enter);
  login.append(h('button', { class: 'icon-btn close', type: 'button', text: '×', 'aria-label': '关闭', onClick: close }), loginForm, footer());
  const nav = h('nav', { class: 'nav', 'aria-label': '平台导航' });
  const navButtons = new Map();
  for (const [id, name, symbol] of tabs) {
    const button = h('button', { class: 'nav-btn', type: 'button', onClick: () => showTab(id), 'aria-label': name, 'data-testid': `nav-${id}` }, h('span', { class: 'nav-symbol', 'aria-hidden': 'true', text: symbol }), h('span', { text: name }));
    navButtons.set(id, button);
    nav.appendChild(button);
  }
  const sidebar = h('aside', { class: 'sidebar' }, h('div', { class: 'brand' }, avatar(), h('div', { class: 'brand-title' }, 'wu138di', h('small', { text: '全球上网 · V1.0' }))), nav, footer());
  const pageTitle = h('h1', { class: 'page-title', text: '概览' });
  const statusDot = h('i', { class: 'dot', 'aria-hidden': 'true' });
  const statusText = h('span', { text: '读取中' });
  const statusPill = h('div', { class: 'status-pill' }, statusDot, statusText);
  const refreshButton = h('button', { class: 'icon-btn', type: 'button', text: '↻', title: '刷新', 'aria-label': '刷新', onClick: () => refresh().catch(() => {}) });
  const lockButton = h('button', { class: 'icon-btn', type: 'button', text: '⇥', title: '锁定', 'aria-label': '锁定平台', 'data-testid': 'platform-lock', onClick: lock });
  const topbar = h('header', { class: 'topbar' }, pageTitle, h('div', { class: 'top-actions' }, statusPill, refreshButton, lockButton, h('button', { class: 'icon-btn', type: 'button', text: '×', 'aria-label': '关闭', onClick: close })));
  const operationName = h('span', { class: 'operation-name' });
  const operationPercent = h('span');
  const operation = h('div', { class: 'operation', hidden: true, role: 'status', 'aria-live': 'polite' }, h('i', { class: 'spinner', 'aria-hidden': 'true' }), operationName, operationPercent);
  const page = h('main', { class: 'content', tabIndex: -1 });
  const platform = h('section', { class: 'platform', hidden: true }, sidebar, h('div', { class: 'workspace' }, topbar, operation, page));
  const toast = h('div', { class: 'toast', hidden: true, role: 'status', 'aria-live': 'polite', 'data-testid': 'platform-toast' });
  frame.append(login, platform, toast);
  modal.appendChild(frame);
  shadow.append(style, modal);

  function focusSoon(node) {
    const schedule = typeof win.requestAnimationFrame === 'function' ? win.requestAnimationFrame.bind(win) : (fn) => win.setTimeout(fn, 0);
    schedule(() => { if (!state.disposed && state.open && node && typeof node.focus === 'function') node.focus(); });
  }
  function showToast(message, error) {
    if (state.disposed || !state.open) return;
    win.clearTimeout(toastTimer);
    toast.textContent = message;
    toast.className = `toast${error ? ' error' : ''}`;
    toast.hidden = false;
    toastTimer = win.setTimeout(() => { toast.hidden = true; toast.textContent = ''; }, 3200);
  }
  function valueOn(value) { return value === true || /^(running|on|yes|enabled|validated|configured|valid|authenticated-ready|ready|true)$/i.test(String(value || '')); }
  function status() { return (state.snapshot && state.snapshot.status) || {}; }
  function hasSubscription(value) { return value === true || /^(configured|validated|valid|true)$/i.test(String(value || '')); }
  function subscriptionReady() { return hasSubscription(status().subscription); }
  function proxyMap() { return subscriptionReady() && (state.snapshot && state.snapshot.proxies) || {}; }
  function groups() { return Object.entries(proxyMap()).filter(([, item]) => item && Array.isArray(item.all)); }
  function deployed() {
    const s = status();
    return !!state.snapshot && s.deployment !== 'missing' && s.core !== 'missing' && s.core != null;
  }
  function formatBytes(value, digits) {
    let size = Math.max(0, Number(value) || 0), unit = 0;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    while (size >= 1024 && unit < units.length - 1) { size /= 1024; unit++; }
    return { value: size.toFixed(unit ? (digits == null ? 1 : digits) : 0), unit: units[unit] };
  }
  function byteText(value) { const b = formatBytes(value); return `${b.value} ${b.unit}`; }
  function action(text, fn, options) {
    const opts = options || {};
    const button = h('button', { class: `btn ${opts.primary ? 'primary' : ''} ${opts.danger ? 'danger' : ''} ${opts.small ? 'small' : ''}`, type: 'button', text, disabled: state.mutating || !!opts.disabled,
      onClick: () => execute(opts.label || text, fn, opts) });
    button.dataset.mutate = 'true';
    button.dataset.intrinsicDisabled = opts.disabled ? 'true' : 'false';
    return button;
  }
  function syncBusy() {
    operation.hidden = !state.mutating;
    operationName.textContent = state.operation ? `${state.operation}…` : '';
    if (!state.mutating) operationPercent.textContent = '';
    for (const button of shadow.querySelectorAll('[data-mutate="true"]')) button.disabled = state.mutating || state.readError || button.dataset.intrinsicDisabled === 'true';
  }
  async function execute(label, fn, options) {
    if (!state.unlocked || state.mutating || state.disposed) return;
    const opts = options || {};
    if (opts.confirm && !win.confirm(opts.confirm)) return;
    const token = state.generation;
    state.mutating = true;
    state.operation = label;
    operationPercent.textContent = '';
    syncBusy();
    try {
      await fn();
      if (!state.unlocked || state.disposed || token !== state.generation) return;
      if (opts.refresh !== false) await refresh({ quiet: true, force: true });
      if (!state.unlocked || state.disposed || token !== state.generation) return;
      showToast(opts.success || `${label}完成`);
    } catch (error) {
      if (state.unlocked && !state.disposed && token === state.generation) showToast(error && error.code === 'U30_RULE_ASSIGNMENT_INCOMPLETE' ? '订阅已保存，规则分配待完成' : (['当前口令错误','两次口令不一致','新口令与当前相同','口令需为 4–64 位','服务器拒绝订阅（HTTP 403）','订阅认证失败（HTTP 401）','订阅下载失败','节点配置校验失败','节点未连通，代理未开启','代理链路未就绪，保持直连','请选择可用节点','请先导入节点'].includes(error && error.message)?error.message:`${label}失败，请重试`), true);
    }
    finally {
      if (!state.disposed && token === state.generation) {
        state.mutating = false;
        state.operation = '';
        renderPage();
        syncBusy();
      }
    }
  }
  function updateTraffic(data) {
    if (!hasSubscription(data && data.status && data.status.subscription)) {
      state.previousTraffic = null;
      state.uploadRate = state.downloadRate = 0;
      return;
    }
    const current = data && data.connections;
    if (!current) return;
    const now = Date.now();
    const down = Number(current.downloadTotal) || 0, up = Number(current.uploadTotal) || 0;
    if (state.previousTraffic) {
      const seconds = (now - state.previousTraffic.time) / 1000;
      if (seconds > .25) {
        state.downloadRate = Math.max(0, down - state.previousTraffic.down) / seconds;
        state.uploadRate = Math.max(0, up - state.previousTraffic.up) / seconds;
      }
    }
    state.previousTraffic = { time: now, down, up };
  }
  async function refresh(options) {
    const opts = options || {};
    if (!state.unlocked || state.disposed) return;
    const token = state.generation;
    if (refreshPromise && refreshGeneration === token) {
      if (!opts.force) return refreshPromise;
      await refreshPromise.catch(() => {});
      if (!state.unlocked || state.disposed || token !== state.generation) return;
    }
    refreshButton.disabled = true;
    const read = Promise.resolve().then(() => core.snapshot());
    let currentPromise;
    currentPromise = (async () => {
      try {
        const data = await read;
        if (state.disposed || !state.unlocked || token !== state.generation) return;
        updateTraffic(data);
        state.snapshot = data || {};
        state.readError = false;
        updateHeader();
        renderPage();
      } catch (error) {
        if (state.unlocked && !state.disposed && token === state.generation) {
          state.readError = true;
          updateHeader();
          if (state.tab === 'overview') renderPage(); else syncBusy();
          if (!opts.quiet) showToast('读取失败，请重试', true);
        }
        throw error;
      } finally {
        if (refreshPromise === currentPromise && token === state.generation) {
          refreshButton.disabled = false;
          refreshPromise = null;
          refreshGeneration = -1;
        }
      }
    })();
    refreshPromise = currentPromise;
    refreshGeneration = token;
    return currentPromise;
  }
  function startPolling() {
    stopPolling();
    pollTimer = win.setInterval(() => {
      if (!state.open || !state.unlocked || state.mutating || !['overview', 'connections'].includes(state.tab)) return;
      const focused = shadow.activeElement;
      if (focused && ['INPUT', 'SELECT', 'TEXTAREA'].includes(focused.tagName)) return;
      refresh({ quiet: true }).catch(() => {});
    }, 5000);
  }
  function stopPolling() { win.clearInterval(pollTimer); pollTimer = null; }
  function updateHeader() {
    const s = status(), running = valueOn(s.core) && !state.readError;
    statusDot.className = `dot${running ? ' live' : ''}`;
    const label = state.readError || !state.snapshot ? '未连接' : !deployed() ? '待部署' : running ? '运行中' : '已停止';
    statusText.textContent = `${s.preview === true ? '预览 · ' : ''}${label}`;
  }
  function showTab(id) {
    if (!state.unlocked || !tabs.some(([key]) => key === id)) return;
    state.tab = id;
    for (const [key, button] of navButtons) {
      button.classList.toggle('active', key === id);
      if (key === id) button.setAttribute('aria-current', 'page'); else button.removeAttribute('aria-current');
    }
    pageTitle.textContent = tabs.find(([key]) => key === id)[1];
    renderPage();
  }
  function renderPage() {
    if (!state.unlocked || state.disposed) return;
    page.replaceChildren();
    page.dataset.page = state.tab;
    const renderers = { overview: renderOverview, proxies: renderProxies, subscription: renderSubscription, rules: renderRules, connections: renderConnections, diagnostics:renderDiagnostics, settings: renderSettings };
    renderers[state.tab]();
    page.appendChild(footer('footer-mobile'));
    syncBusy();
  }
  function sectionHead(title, right) { return h('div', { class: 'section-head' }, h('h2', { text: title }), right); }
  function empty(message, symbol, button) { return h('div', { class: 'empty' }, h('span', { class: 'empty-symbol', 'aria-hidden': 'true', text: symbol || '◇' }), h('p', { text: message }), button); }
  function subscriptionPrompt() {
    const prompt = empty('请先导入订阅', '↻', h('button', { class: 'btn primary', type: 'button', text: '添加订阅', 'data-testid': 'subscription-empty-link', onClick: () => showTab('subscription') }));
    prompt.classList.add('card', 'subscription-empty');
    return prompt;
  }
  function metric(label, symbol, value, unit, caption) {
    return h('div', { class: 'card' }, h('div', { class: 'row spread' }, h('span', { class: 'card-label', text: label }), h('span', { class: 'card-icon', 'aria-hidden': 'true', text: symbol })), h('div', { class: 'card-value' }, value, h('span', { class: 'stat-unit', text: unit })), caption ? h('p', { class: 'card-caption', text: caption }) : null);
  }
  function modeSwitch() {
    const active = String((state.snapshot && state.snapshot.mode) || 'rule').toLowerCase();
    const control = h('div', { class: 'segmented', 'aria-label': '代理模式' });
    for (const [mode, name] of [['rule', '规则'], ['global', '全局'], ['direct', '直连']]) {
      const button = h('button', { class: mode === active ? 'active' : '', type: 'button', text: name, disabled: state.mutating || !deployed(), 'aria-pressed': String(mode === active), 'data-testid': `mode-${mode}`, onClick: () => {
        if (mode === active) return;
        execute('切换模式', () => core.setMode(mode), { confirm: `切换到${name}模式？` });
      } });
      button.dataset.mutate = 'true';
      button.dataset.intrinsicDisabled = deployed() ? 'false' : 'true';
      control.appendChild(button);
    }
    return control;
  }
  function renderOverview() {
    const s = status(), running = valueOn(s.core) && !state.readError, transparent = valueOn(s.transparent), installed = deployed();
    const title = state.readError ? '设备未连接' : !state.snapshot ? '连接设备' : !installed ? '准备就绪' : running && transparent ? '代理已开启' : running ? '服务已就绪' : '代理已停止';
    const subtitle = state.readError ? '点击刷新重试' : !state.snapshot ? '读取设备状态' : !installed ? '安装后添加订阅' : running && transparent ? '按当前策略连接网络' : running ? '透明代理未开启' : '点击启动服务';
    const powerAction = !installed ? () => core.install() : () => core.service(transparent ? 'stop' : 'enable');
    const powerLabel = !installed ? '安装' : transparent ? '停止代理' : '开启代理';
    const power = h('button', { class: `power${running && transparent ? ' on' : ''}`, type: 'button', text: '⏻', disabled: state.mutating || !state.snapshot, title: powerLabel, 'aria-label': powerLabel,
      onClick: () => execute(powerLabel, powerAction) });
    power.dataset.mutate = 'true'; power.dataset.intrinsicDisabled = state.snapshot ? 'false' : 'true';
    page.appendChild(h('div', { class: 'card hero' }, h('div', {}, h('h2', { text: title }), h('p', { text: subtitle })), power));
    const traffic = subscriptionReady() && state.snapshot && state.snapshot.connections;
    const down = formatBytes(state.downloadRate), up = formatBytes(state.uploadRate);
    page.appendChild(h('div', { class: 'stats' }, metric('下载', '↓', down.value, `${down.unit}/s`, `累计 ${byteText(traffic && traffic.downloadTotal)}`), metric('上传', '↑', up.value, `${up.unit}/s`, `累计 ${byteText(traffic && traffic.uploadTotal)}`), metric('连接', '⇄', String(traffic && Array.isArray(traffic.connections) ? traffic.connections.length : 0), '个', `内存 ${byteText(traffic && traffic.memory)}`)));
    page.appendChild(sectionHead('运行模式', h('span', { class: 'mini-label', text: valueOn(s.autostart) ? '开机自启已开' : '开机自启已关' })));
    page.appendChild(modeSwitch());
    page.appendChild(h('div', { class: 'section-gap' }, sectionHead('地区分流', h('span', { class: 'mini-label', text: !subscriptionReady() ? '—' : String(state.snapshot && state.snapshot.mode || 'rule').toLowerCase() === 'rule' ? '规则优先' : '未使用规则模式' }))));
    if (!subscriptionReady()) { page.appendChild(subscriptionPrompt()); return; }
    const regions = h('div', { class: 'regions' });
    for (const [flag, name, platformName, pattern] of [['🇭🇰', '香港', 'TVB', /REGION.HK|香港|Hong.?Kong/i], ['🇹🇼', '台湾', 'BAHA', /REGION.TW|台湾|Taiwan/i], ['🇯🇵', '日本', 'ABEMA · NHK', /REGION.JP|日本|Japan/i]]) {
      const found = groups().find(([key]) => pattern.test(key));
      const node = found && found[1].now;
      const available = node && !/^(REJECT|DIRECT)$/i.test(node);
      regions.appendChild(h('div', { class: 'card region' }, h('div', { class: 'region-flag' },h('img',{class:'node-flag',src:getNodeFlag(name).src,alt:name,'data-country':getNodeFlag(name).code})), h('p', { class: 'region-title', text: name }), h('p', { class: 'region-platform', text: platformName }), h('p', { class: 'region-node', title: available ? node : '', text: available ? node : '暂无本区节点' })));
    }
    page.appendChild(regions);
  }
  function renderProxies() {
    if (!subscriptionReady()) { page.appendChild(subscriptionPrompt()); return; }
    const available = groups();
    if (!available.length) { page.appendChild(empty('暂无节点', '◈', action('添加订阅', () => { showTab('subscription'); }, { refresh: false, success: '输入订阅链接' }))); return; }
    if (!available.some(([name]) => name === state.selectedGroup)) state.selectedGroup = (available.find(([name]) => name === 'PROXY') || available[0])[0];
    const strip = h('div', { class: 'group-tabs', role: 'tablist', 'aria-label': '代理组' });
    for (const [name] of available) strip.appendChild(h('button', { class: `group-tab${name === state.selectedGroup ? ' active' : ''}`, type: 'button', text: name, role: 'tab', 'aria-selected': String(name === state.selectedGroup), 'data-testid': 'proxy-group', 'data-group': name, onClick: () => { state.selectedGroup = name; renderPage(); } }));
    page.appendChild(strip);
    const group = proxyMap()[state.selectedGroup];
    const manual = !group.type || /selector|select$/i.test(String(group.type));
    page.appendChild(h('div',{class:'row spread',style:'margin-bottom:16px'},h('span',{class:'mini-label',text:'节点'}),action('全部测速',async()=>{for(const name of group.all){if(!state.unlocked)break; const node=proxyMap()[name];if(!node || Array.isArray(node.all) || /^(DIRECT|REJECT|PASS)$/i.test(name))continue;try{state.delays.set(name,(await core.delay(name)).delay);}catch(_){state.delays.set(name,-1);}}},{refresh:false,disabled:!valueOn(status().core)})));
    page.appendChild(sectionHead(state.selectedGroup, h('div', { class: 'row' }, manual ? null : h('span', { class: 'badge', text: '自动选择' }), h('span', { class: 'count', text: `${group.all.length} 个` }))));
    const grid = h('div', { class: 'node-grid' });
    for (const member of group.all) {
      const name = String(member), item = proxyMap()[name] || {}, selected = group.now === name;
      const history = Array.isArray(item.history) ? item.history : [];
      const last=history[history.length-1]; const recent=last && Date.now()-Date.parse(last.time)<60000; const historicDelay=recent ? Number(last.delay) : null;
      const delay = state.delays.has(name) ? state.delays.get(name) : historicDelay;
      const resultText = delay === 'testing' ? '···' : delay === -1 || delay === 0 ? '超时' : Number.isFinite(delay) && delay > 0 ? `${delay} ms` : '测速';
      const delayButton = h('button', { class: `latency${delay === -1 || delay === 0 ? ' fail' : Number.isFinite(delay) && delay > 0 ? delay < 500 ? ' fast' : ' slow' : ''}`, type: 'button', text: resultText, 'aria-label': `测试 ${name} 延迟`, 'data-testid': 'proxy-delay', 'data-node': name, 'data-delay-node': name, disabled: state.mutating || delay === 'testing' || /^(DIRECT|REJECT|PASS|COMPATIBLE)$/i.test(name), onClick: async () => {
        if (state.mutating) return;
        const token = state.generation;
        state.delays.set(name, 'testing'); renderPage();
        try {
          const result = await core.delay(name);
          if (!state.unlocked || state.disposed || token !== state.generation) return;
          const measured = Number(typeof result === 'number' ? result : result && result.delay);
          state.delays.set(name, measured > 0 && Number.isFinite(measured) ? measured : -1);
        } catch (_) { if (state.unlocked && !state.disposed && token === state.generation) state.delays.set(name, -1); }
        if (state.unlocked && state.tab === 'proxies') renderPage();
      } });
      const selectButton = h('button', { class: 'node-select', type: 'button', disabled: !manual || state.mutating, 'aria-pressed': String(selected), 'aria-label': `选择 ${name}`, 'data-testid': 'proxy-select', 'data-node': name, 'data-select-node': name, 'data-group': state.selectedGroup, onClick: () => {
        if (selected || !manual) return;
        execute('切换节点', () => core.select(state.selectedGroup, name));
      } }, h('span', { class: 'node-mark' },h('img',{class:'node-flag',src:getNodeFlag(name).src,alt:getNodeFlag(name).label,'data-country':getNodeFlag(name).code}),selected?h('span',{class:'selected-tick','aria-hidden':'true',text:'✓'}):null), h('span', { class: 'grow' }, h('span', { class: 'node-name', title: name, text: name }), h('span', { class: 'node-type', text: String(item.type || (Array.isArray(item.all) ? '代理组' : '节点')) })));
      selectButton.dataset.mutate = 'true'; selectButton.dataset.intrinsicDisabled = manual ? 'false' : 'true';
      grid.appendChild(h('div', { class: `node${selected ? ' selected' : ''}` }, selectButton, delayButton));
    }
    page.appendChild(grid);
  }
  function renderSubscription() {
    const present = subscriptionReady(), preview = status().preview === true;
    const input = h('input', { class: 'field', type: 'password', name: 'u30-subscription-import', placeholder: '粘贴 HTTPS 订阅链接', autocomplete: 'off', autocapitalize: 'off', spellcheck: false, maxLength: 8192, disabled: preview, 'aria-label': 'HTTPS 订阅链接', 'data-testid': 'subscription-url' });
    const submit = async () => {
      if (preview) return;
      const url = input.value.trim();
      input.value = '';
      let valid = false;
      try {
        const parsed = new URL(url);
        const length = typeof TextEncoder === 'function' ? new TextEncoder().encode(url).length : encodeURIComponent(url).replace(/%[A-F\d]{2}|./gi, 'x').length;
        valid = parsed.protocol === 'https:' && !!parsed.hostname && !parsed.username && !parsed.password && !parsed.hash && length <= 8192;
      } catch (_) {}
      if (!valid) { showToast('请输入有效的 HTTPS 订阅', true); focusSoon(input); return; }
      await execute('导入订阅', () => core.importSubscription(url), { success: '订阅已更新' });
    };
    const form = h('form', { class: 'card subscribe-card', autocomplete: 'off', 'data-testid': 'subscription-form', onSubmit: (event) => { event.preventDefault(); submit(); } },
      h('div', { class: 'subscription-status' }, h('div', { class: 'subscription-symbol', 'aria-hidden': 'true', text: '↻' }), h('div', {}, h('p', { class: 'subscription-state', text: present ? '订阅已导入' : '添加订阅' }), h('p', { class: 'subscription-sub', text: present ? '自动更新 · 本机保存' : 'Clash / Mihomo 格式' }))), input);
    const importButton = h('button', { class: 'btn primary', type: 'submit', text: '导入订阅', disabled: state.mutating || !deployed() || preview, 'data-testid': 'subscription-submit' });
    importButton.dataset.mutate = 'true'; importButton.dataset.intrinsicDisabled = deployed() && !preview ? 'false' : 'true';
    const refreshSubscription = action('立即更新', () => core.refreshSubscription(), { disabled: !present || !deployed() || preview });
    refreshSubscription.dataset.testid = 'subscription-refresh';
    form.appendChild(h('div', { class: 'row' }, importButton, refreshSubscription));
    page.appendChild(form);
    const yaml=h('textarea',{class:'field yaml-area',placeholder:'proxies:',autocomplete:'off',spellcheck:false,'aria-label':'节点 YAML','data-testid':'yaml-text'});
    const file=h('input',{class:'file-picker',type:'file',accept:'.yaml,.yml,text/yaml,application/yaml','aria-label':'导入 YAML 文件','data-testid':'yaml-file'});
    file.addEventListener('change',async()=>{const f=file.files&&file.files[0];if(!f)return;if(f.size>1048576){showToast('文件超过 1 MB',true);file.value='';return;}yaml.value=await f.text();});
    page.appendChild(h('section',{class:'card yaml-card'},sectionHead('节点 YAML'),yaml,h('div',{class:'row wrap'},file,action('导入 YAML',async()=>{const text=yaml.value;yaml.value='';file.value='';await core.importYaml(text);},{disabled:!deployed()||preview,success:'节点已导入'}))));
    if (!deployed()) page.appendChild(h('div', { class: 'section-gap' }, action('安装 / 校验', () => core.install(), { primary: true })));
    page.appendChild(h('p', { class: 'privacy-note', text: preview ? '请在 UFI-TOOLS 中导入' : '订阅仅保存到当前设备' }));
  }
  function renderDiagnostics(){
    page.appendChild(sectionHead('网络检测',action('开始检测',async()=>{state.diagnostic=await core.diagnostics();},{refresh:false,success:'检测完成'})));
    const data=state.diagnostic||{},grid=h('div',{class:'diagnostic-grid'});
    for(const [key,label] of [['core','代理核心'],['transparent','透明代理'],['route','默认路由'],['dns','DNS'],['direct_http','国内直连'],['proxy_http','代理连接']])grid.appendChild(h('div',{class:'card diagnostic-card'},h('span',{class:'mini-label',text:label}),h('strong',{text:data[key]||'—'})));
    page.appendChild(grid);
  }
  function renderRules() {
    if (!subscriptionReady()) { page.appendChild(subscriptionPrompt()); return; }
    const rules = state.snapshot && Array.isArray(state.snapshot.rules) ? state.snapshot.rules : [];
    const search = h('input', { class: 'field search', type: 'search', placeholder: '搜索规则', value: state.ruleQuery, 'aria-label': '搜索规则', 'data-testid': 'rules-search' });
    const list = h('div', { 'data-testid': 'rules-list' });
    const count = h('span', { class: 'count' });
    const update = () => {
      const query = state.ruleQuery.toLowerCase();
      const filtered = rules.filter((rule) => `${rule.payload || ''} ${rule.type || ''} ${rule.proxy || ''}`.toLowerCase().includes(query));
      count.textContent = `${filtered.length} 条`;
      list.replaceChildren();
      if (!filtered.length) { list.appendChild(empty(rules.length ? '没有匹配规则' : '暂无规则', '≡')); return; }
      const container = h('div', { class: 'list' });
      for (const rule of filtered.slice(0, 500)) container.appendChild(h('div', { class: 'list-row' }, h('div', { class: 'grow' }, h('p', { class: 'rule-name truncate', title: String(rule.payload || ''), text: rule.payload || 'MATCH' }), h('p', { class: 'rule-kind', text: rule.type || 'Rule' })), h('span', { class: 'rule-target', title: String(rule.proxy || ''), text: rule.proxy || '—' })));
      list.appendChild(container);
      if (filtered.length > 500) list.appendChild(h('p', { class: 'privacy-note', text: `显示前 500 条 / 共 ${filtered.length} 条` }));
    };
    search.addEventListener('input', () => { state.ruleQuery = search.value; update(); });
    page.append(sectionHead('分流规则', count), search, list);
    update();
  }
  function renderConnections() {
    if (!subscriptionReady()) { page.appendChild(subscriptionPrompt()); return; }
    const data = state.snapshot && state.snapshot.connections;
    const connections = data && Array.isArray(data.connections) ? data.connections : [];
    const search = h('input', { class: 'field search', type: 'search', placeholder: '搜索连接', value: state.connectionQuery, 'aria-label': '搜索连接' });
    const count = h('span', { class: 'count' });
    const list = h('div', { 'data-testid': 'connections-list' });
    const update = () => {
      const query = state.connectionQuery.toLowerCase();
      const filtered = connections.filter((item) => {
        const m = item.metadata || {};
        return `${m.host || ''} ${m.destinationIP || ''} ${(item.chains || []).join(' ')}`.toLowerCase().includes(query);
      });
      count.textContent = `${filtered.length} 个`;
      list.replaceChildren();
      if (!filtered.length) { list.appendChild(empty(connections.length ? '没有匹配连接' : '暂无连接', '⇄')); return; }
      const container = h('div', { class: 'list' });
      for (const item of filtered.slice(0, 300)) {
        const m = item.metadata || {}, host = String(m.host || m.destinationIP || '未知目标');
        const chain = Array.isArray(item.chains) ? item.chains.join(' › ') : '';
        const metadata = `${String(m.network || 'TCP').toUpperCase()}${m.destinationPort ? ` · ${m.destinationPort}` : ''}${chain ? ` · ${chain}` : ''}`;
        const closeConnection = typeof core.closeConnection === 'function' && item.id ? h('button', { class: 'connection-close', type: 'button', text: '×', title: '关闭连接', 'aria-label': `关闭 ${host} 连接`, 'data-testid': 'connection-close', 'data-connection': String(item.id), 'data-close-connection': String(item.id), disabled: state.mutating, onClick: () => execute('关闭连接', () => core.closeConnection(String(item.id))) }) : null;
        if (closeConnection) { closeConnection.dataset.mutate = 'true'; closeConnection.dataset.intrinsicDisabled = 'false'; }
        container.appendChild(h('div', { class: 'list-row' }, h('div', { class: 'grow' }, h('p', { class: 'connection-name truncate', title: host, text: host }), h('p', { class: 'connection-meta truncate', title: metadata, text: metadata })), h('div', { class: 'connection-data' }, h('div', { text: `↓ ${byteText(item.download)}` }), h('div', { text: `↑ ${byteText(item.upload)}` })), closeConnection));
      }
      list.appendChild(container);
    };
    search.addEventListener('input', () => { state.connectionQuery = search.value; update(); });
    page.append(sectionHead('当前连接', count), search, list);
    update();
  }
  function switchControl(checked, label, handler, disabled) {
    const input = h('input', { type: 'checkbox', checked, disabled: state.mutating || disabled, 'aria-label': label, 'data-testid': label === '开机自启' ? 'autostart-toggle' : 'transparent-toggle', onChange: () => {
      const requested = input.checked;
      input.checked = checked;
      execute(label, () => handler(requested));
    } });
    input.dataset.mutate = 'true'; input.dataset.intrinsicDisabled = disabled ? 'true' : 'false';
    return h('label', { class: 'switch-label' }, input, h('span', { class: 'switch-track', 'aria-hidden': 'true' }));
  }
  function setting(name, desc, control) { return h('div', { class: 'setting-row' }, h('div', {}, h('p', { class: 'setting-name', text: name }), desc ? h('p', { class: 'setting-desc', text: desc }) : null), control); }
  function renderSettings() {
    const s = status(), installed = deployed();
    page.appendChild(sectionHead('代理服务', h('span', { class: 'mini-label', text: 'U30 Pro' })));
    const card = h('div', { class: 'card' },
      setting('透明代理', '接管设备网络', switchControl(valueOn(s.transparent), '透明代理', (on) => core.service(on ? 'enable' : 'disable'), !installed)),
      setting('开机自启', '', switchControl(valueOn(s.autostart), '开机自启', (on) => core.autostart(on), !installed)),
      setting('核心服务', valueOn(s.core) ? '运行中' : installed ? '已停止' : '待部署', action(valueOn(s.core) ? '重启' : '启动', () => core.service(valueOn(s.core) ? 'restart' : 'start'), { small: true, disabled: !installed, confirm: valueOn(s.core) ? '重启代理服务？' : '' })));
    page.appendChild(card);
    page.appendChild(h('div', { class: 'section-gap' }, sectionHead('运行模式'), modeSwitch()));
    page.appendChild(h('div', { class: 'section-gap row spread wrap' }, h('div', {}, h('p', { class: 'setting-name', text: '组件管理' }), h('p', { class: 'setting-desc', text: '保留现有订阅' })), action('安装 / 校验', () => core.install(), { small: true })));
    const oldPin=h('input',{class:'field',type:'password',autocomplete:'current-password',placeholder:'当前口令',maxLength:64,required:true,'aria-label':'当前口令','data-testid':'pin-current'});
    const newPin=h('input',{class:'field',type:'password',autocomplete:'new-password',placeholder:'新口令',minLength:4,maxLength:64,required:true,'aria-label':'新口令','data-testid':'pin-new'});
    const confirmPin=h('input',{class:'field',type:'password',autocomplete:'new-password',placeholder:'确认新口令',minLength:4,maxLength:64,required:true,'aria-label':'确认新口令','data-testid':'pin-confirm'});
    const savePin=h('button',{class:'btn primary',type:'submit',text:'修改口令','data-testid':'pin-save',disabled:state.mutating||status().preview===true});
    savePin.dataset.mutate='true';savePin.dataset.intrinsicDisabled=status().preview===true?'true':'false';
    const pinForm=h('form',{class:'card pin-settings','data-testid':'pin-settings-form',autocomplete:'off',onSubmit:event=>{
      event.preventDefault();const current=oldPin.value,next=newPin.value,confirm=confirmPin.value;oldPin.value=newPin.value=confirmPin.value='';
      execute('修改口令',async()=>{await core.changePin(current,next,confirm);pin.placeholder='输入登录口令';lock();showToast('口令已更新');},{refresh:false});
    }},sectionHead('登录口令'),oldPin,newPin,confirmPin,savePin);
    page.appendChild(pinForm);
    page.appendChild(h('details', { class: 'advanced' }, h('summary', { text: '高级' }), h('div', { class: 'row wrap' }, action('恢复标准分流', () => core.standard(), { disabled: !installed, confirm: '恢复标准分流？当前规则会先备份。' }), action('回滚规则', () => core.rollbackRules(), { disabled: !installed, danger: true, confirm: '恢复上一次规则备份？' }))));
  }
  function clearSession() {
    state.unlocked = false;
    state.generation += 1;
    state.mutating = false;
    state.operation = '';
    refreshPromise = null;
    refreshGeneration = -1;
    refreshButton.disabled = false;
    syncBusy();
    state.snapshot = null;
    state.readError = false;
    state.selectedGroup = '';
    state.ruleQuery = '';
    state.connectionQuery = '';
    state.delays.clear();
    state.diagnostic=null;
    state.previousTraffic = null;
    state.uploadRate = state.downloadRate = 0;
    pin.value = '';
    page.replaceChildren();
    toast.hidden = true;
    toast.textContent = '';
    platform.hidden = true;
    login.hidden = false;
    stopPolling();
  }
  async function syncPinHint(){
    const token=state.generation;pin.placeholder='输入登录口令';pin.inputMode='text';
    try{const status=typeof core.getPinStatus==='function'?await core.getPinStatus():{configured:false};if(!state.disposed&&state.open&&!state.unlocked&&token===state.generation){pin.placeholder=status.configured?'输入登录口令':'登录口令 2007';pin.inputMode=status.configured?'text':'numeric';}}catch(_){}
  }
  function lock() { clearSession();syncPinHint(); if (typeof core.lock === 'function') core.lock(); focusSoon(pin); }
  function open() {
    if (state.disposed) return;
    if (!state.open) previousFocus = doc.activeElement;
    state.open = true;
    modal.hidden = false;
    if (state.unlocked) { startPolling(); focusSoon(page); refresh({ quiet: true }).catch(() => {}); }
    else {syncPinHint();focusSoon(pin);}
  }
  function close() {
    if (!state.open || state.disposed) return;
    state.open = false;
    modal.hidden = true;
    clearSession();
    if (typeof core.lock === 'function') core.lock();
    const target = previousFocus && previousFocus.isConnected ? previousFocus : entry;
    if (target && typeof target.focus === 'function') target.focus();
  }
  function onKeyDown(event) {
    if (!state.open || state.disposed) return;
    if (event.key === 'Escape') { event.preventDefault(); close(); return; }
    if (event.key !== 'Tab') return;
    const focusable = Array.from(frame.querySelectorAll('button,input,select,summary,[tabindex="0"]')).filter((node) => !node.disabled && !node.closest('[hidden]'));
    if (!focusable.length) { event.preventDefault(); frame.focus(); return; }
    const first = focusable[0], last = focusable[focusable.length - 1], active = shadow.activeElement;
    if (event.shiftKey && (active === first || !frame.contains(active))) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && (active === last || !frame.contains(active))) { event.preventDefault(); first.focus(); }
  }
  const onEntryClick = () => open();
  if (entry) entry.addEventListener('click', onEntryClick);
  doc.addEventListener('keydown', onKeyDown, true);
  const unsubscribe = typeof core.onProgress === 'function' ? core.onProgress((progress) => {
    if (!state.unlocked || !state.mutating || state.disposed) return;
    const numeric = typeof progress === 'number' ? progress : progress && progress.percent;
    const percent = Number(numeric);
    if (Number.isFinite(percent) && percent >= 0 && percent <= 100) operationPercent.textContent = `${Math.round(percent)}%`;
  }) : null;
  function dispose() {
    if (state.disposed) return;
    close();
    state.disposed = true;
    stopPolling();
    win.clearTimeout(toastTimer);
    if (typeof unsubscribe === 'function') unsubscribe();
    if (entry) entry.removeEventListener('click', onEntryClick);
    doc.removeEventListener('keydown', onKeyDown, true);
    modal.remove();
    style.remove();
  }
  return { open, close, dispose };
}
