/* Read-only offline preview: no seed nodes, rules, subscriptions or device calls. */
function createPreviewCore() {
  let unlocked=false,disposed=false;
  const status={deployment:'missing',core:'stopped',transparent:'off',autostart:'no',subscription:'none',controller:'not-ready',preview:true};
  const connections={connections:[],downloadTotal:0,uploadTotal:0,memory:0};
  const clone=x=>JSON.parse(JSON.stringify(x));
  function gate(){if(!unlocked||disposed)throw new Error('请先输入口令');}
  async function unavailable(){gate();throw new Error('请在 UFI-TOOLS 中操作');}
  return {
    enter(pin){unlocked=!disposed&&String(pin)==='2007';return unlocked;},
    getPinStatus:async()=>({configured:false}),changePin:unavailable,
    lock(){unlocked=false;},dispose(){unlocked=false;disposed=true;},
    snapshot:async()=>{gate();return clone({status,mode:'rule',proxies:{},rules:[],connections});},
    status:async()=>{gate();return clone(status);},proxies:async()=>{gate();return {};},
    rules:async()=>{gate();return [];},connections:async()=>{gate();return clone(connections);},
    setMode:unavailable,select:unavailable,delay:unavailable,importSubscription:unavailable,
    refreshSubscription:unavailable,service:unavailable,autostart:unavailable,install:unavailable,
    standard:unavailable,rollbackRules:unavailable,closeConnection:unavailable,
    onProgress:()=>()=>{}
  };
}
