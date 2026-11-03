//<!-- [KANO_PLUGIN_START] U30Pro-Mihomo -->
//<script>
(function () {
  'use strict';
  const VERSION = '2.0.1';
  const SCRIPTS = __U30_PUBLIC_SCRIPTS__;
  const ICON_URI = __U30_ICON__;
  __U30_CORE__
  __U30_UI__
  const previous = window.__U30MihomoPlugin__;
  if (previous && typeof previous.dispose === 'function') previous.dispose();
  let disposed = false, mounted = null, core = null, host = null, entry = null;
  const owner = {version:VERSION, dispose, isBusy:()=>core && core.isBusy ? core.isBusy() : false};
  window.__U30MihomoPlugin__ = owner;
  function dispose() {
    if (disposed) return;
    disposed = true;
    document.removeEventListener('DOMContentLoaded', start);
    if (mounted) mounted.dispose();
    if (core && core.dispose) core.dispose();
    if (host) host.remove();
    if (entry) entry.remove();
    if (window.__U30MihomoPlugin__ === owner) delete window.__U30MihomoPlugin__;
  }
  function start() {
    if (disposed) return;
    const orphan = document.getElementById('u30-mihomo-plugin-host');
    if (orphan) orphan.remove();
    const orphanEntry = document.getElementById('u30-mihomo-plugin-entry');
    if (orphanEntry) orphanEntry.remove();
    host = document.createElement('div'); host.id = 'u30-mihomo-plugin-host';
    const shadow = host.attachShadow({mode:'open'});
    entry = document.createElement('button'); entry.id = 'u30-mihomo-plugin-entry';
    entry.type = 'button'; entry.className = 'btn';
    const image = document.createElement('img');
    image.src = ICON_URI; image.alt = ''; image.width = 24; image.height = 24;
    image.style.cssText = 'width:24px;height:24px;object-fit:cover;border-radius:8px;flex-shrink:0';
    entry.appendChild(image);
    const title = document.createElement('span'); title.textContent = '科学上网插件'; entry.appendChild(title);
    entry.style.cssText = 'display:inline-flex;align-items:center;gap:9px;min-height:44px';
    const target = document.querySelector('.functions-container .actions-buttons');
    if (target) target.appendChild(entry);
    else {
      entry.style.cssText += ';position:fixed;right:18px;bottom:75px;z-index:2147482999;padding:10px 16px;border-radius:14px;background:#7c8cff;color:#fff;border:0';
      document.body.appendChild(entry);
    }
    document.body.appendChild(host);
    core = createPlatformCore({sdk:(command,timeout)=>{
      if (typeof runShellWithRoot !== 'function') return Promise.reject(new Error('请先登录 UFI-TOOLS'));
      return runShellWithRoot(command,timeout);
    },scripts:SCRIPTS,request:typeof originFetch === 'function' ? originFetch : window.fetch.bind(window)});
    mounted = mountPlatformUI({shadow,entry,icon:ICON_URI,core});
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',start,{once:true});
  else start();
})();
//</script>
//<!-- [KANO_PLUGIN_END] U30Pro-Mihomo -->
