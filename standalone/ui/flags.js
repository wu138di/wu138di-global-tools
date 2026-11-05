function getNodeFlag(name) {
  const text=String(name||'');const raw=/剩余|流量|到期|重置|套餐|traffic|expire|reset|remaining/i.test(text)?'':text;const flag=raw.match(/[\u{1F1E6}-\u{1F1FF}]{2}/u);
  let code=flag?[...flag[0]].map(c=>String.fromCharCode(c.codePointAt(0)-0x1f1e6+65)).join(''):'';
  if(!code){
    const names=[['HK',/香港|hong[\s_-]*kong/i],['TW',/台湾|台灣|taiwan/i],['JP',/日本|japan|tokyo|osaka|东京|東京|大阪/i],['SG',/新加坡|singapore/i],['KR',/韩国|韓國|korea|seoul/i],['US',/美国|美國|united states|\busa\b|seattle|los angeles|san jose/i],['IN',/印度|india|bombay|mumbai/i],['GB',/英国|英國|united kingdom|britain|london/i],['DE',/德国|德國|germany|frankfurt/i],['FR',/法国|法國|france|paris/i],['CA',/加拿大|canada/i],['AU',/澳大利亚|澳洲|australia|sydney/i],['RU',/俄罗斯|俄羅斯|russia|moscow/i],['CN',/中国|中國|china|北京|上海/i],['BR',/巴西|brazil/i],['NL',/荷兰|荷蘭|netherlands|amsterdam/i]];
    code=names.find(([,r])=>r.test(raw))?.[0]||raw.toUpperCase().match(/(?:^|[^A-Z])(HK|TW|JP|SG|KR|US|IN|GB|UK|DE|FR|CA|AU|RU|CN|BR|NL|TH|VN|MY|ID|PH|TR|CH)(?=$|[^A-Z])/u)?.[1]||'';
  }
  if(code==='UK')code='GB';
  const star=(x,y,r,c='#fff',rotation=0)=>{let pts=[];for(let i=0;i<10;i++){let a=(i*36-90+rotation)*Math.PI/180,k=i%2?r*.382:r;pts.push((x+Math.cos(a)*k).toFixed(2)+','+(y+Math.sin(a)*k).toFixed(2));}return '<polygon points="'+pts.join(' ')+'" fill="'+c+'"/>';};
  const rect=(y,h,c)=>'<rect width="60" height="'+h+'" y="'+y+'" fill="'+c+'"/>';
  const horizontal=(a,b,c)=>rect(0,40/3,a)+rect(40/3,40/3,b)+rect(80/3,40/3,c);
  const vertical=(a,b,c)=>'<path d="M0 0h20v40H0z" fill="'+a+'"/><path d="M20 0h20v40H20z" fill="'+b+'"/><path d="M40 0h20v40H40z" fill="'+c+'"/>';
  const names={HK:'香港',TW:'台湾',JP:'日本',SG:'新加坡',KR:'韩国',US:'美国',IN:'印度',GB:'英国',DE:'德国',FR:'法国',CA:'加拿大',AU:'澳大利亚',RU:'俄罗斯',CN:'中国',BR:'巴西',NL:'荷兰',TH:'泰国',VN:'越南',MY:'马来西亚',ID:'印度尼西亚',PH:'菲律宾',TR:'土耳其',CH:'瑞士',BO:'玻利维亚'};
  let art='';
  if(code==='JP')art=rect(0,40,'#fff')+'<circle cx="30" cy="20" r="12" fill="#bc002d"/>';
  else if(code==='HK'){art=rect(0,40,'#de2910');for(let i=0;i<5;i++)art+='<path d="M30 20C16 16 22 2 30 6C26 9 27 13 30 20" fill="#fff" transform="rotate('+i*72+' 30 20)"/>';}
  else if(code==='TW'){art=rect(0,40,'#fe0000')+'<path d="M0 0h30v20H0z" fill="#000095"/>';for(let i=0;i<12;i++)art+='<path d="M15 2l-1.3 4.5h2.6z" fill="#fff" transform="rotate('+i*30+' 15 10)"/>';art+='<circle cx="15" cy="10" r="4" fill="#fff"/>';}
  else if(code==='US'){for(let i=0;i<13;i++)art+=rect(i*40/13,40/13,i%2?'#fff':'#b22234');art+='<path d="M0 0h25v21.54H0z" fill="#3c3b6e"/>';for(let r=0;r<9;r++)for(let c=0;c<(r%2?5:6);c++)art+=star(2.1+c*4.15+(r%2?2.1:0),2+r*2.18,.95);}
  else if(code==='SG'){art=rect(0,20,'#ef3340')+rect(20,20,'#fff')+'<circle cx="13" cy="10" r="7.2" fill="#fff"/><circle cx="16" cy="8.7" r="6.8" fill="#ef3340"/>';for(let i=0;i<5;i++){let a=(i*72-90)*Math.PI/180;art+=star(23+Math.cos(a)*4,10+Math.sin(a)*4,1.5);}}
  else if(code==='IN')art=horizontal('#ff9933','#fff','#138808')+'<circle cx="30" cy="20" r="5" fill="none" stroke="#000080" stroke-width="1"/>'+Array.from({length:24},(_,i)=>'<path d="M30 20v-5" stroke="#000080" stroke-width=".35" transform="rotate('+i*15+' 30 20)"/>').join('');
  else if(code==='DE')art=horizontal('#000','#dd0000','#ffce00');
  else if(code==='FR')art=vertical('#0055a4','#fff','#ef4135');
  else if(code==='RU')art=horizontal('#fff','#0039a6','#d52b1e');
  else if(code==='NL')art=horizontal('#ae1c28','#fff','#21468b');
  else if(code==='GB'||code==='AU'){art=rect(0,40,'#012169')+'<path d="M0 0l60 40M60 0L0 40" stroke="#fff" stroke-width="8"/><path d="M0 0l60 40M60 0L0 40" stroke="#c8102e" stroke-width="3"/><path d="M30 0v40M0 20h60" stroke="#fff" stroke-width="13"/><path d="M30 0v40M0 20h60" stroke="#c8102e" stroke-width="7"/>';if(code==='AU'){art='<g transform="scale(.5)">'+art+'</g>'+rect(20,20,'#012169')+'<path d="M30 0h30v40H30z" fill="#012169"/>'+star(15,30,4)+star(44,7,3)+star(40,23,3)+star(52,23,3)+star(46,34,3);}}
  else if(code==='CN')art=rect(0,40,'#de2910')+star(10,10,6,'#ffde00')+[[20,4],[24,9],[24,16],[20,21]].map(([x,y])=>star(x,y,2,'#ffde00')).join('');
  else if(code==='KR')art=rect(0,40,'#fff')+'<circle cx="30" cy="20" r="10" fill="#cd2e3a"/><path d="M20 20a10 10 0 0020 0a5 5 0 00-10 0a5 5 0 01-10 0" fill="#0047a0"/>'+[[13,9,-35],[47,31,-35],[47,9,35],[13,31,35]].map(([x,y,a])=>'<g transform="translate('+x+' '+y+') rotate('+a+')" stroke="#111" stroke-width="1.6"><path d="M-5-3H5M-5 0H5M-5 3H5"/></g>').join('');
  else if(code==='CA')art=vertical('#d80621','#fff','#d80621')+'<path d="M30 8l2 7 4-2-1 5 6 1-7 7 1 3-5-1v5h-1v-5l-5 1 1-3-7-7 6-1-1-5 4 2z" fill="#d80621"/>';
  else if(code==='BR')art=rect(0,40,'#009739')+'<path d="M30 4L55 20 30 36 5 20z" fill="#ffdf00"/><circle cx="30" cy="20" r="10" fill="#002776"/><path d="M21 17q10-2 19 8" stroke="#fff" stroke-width="2" fill="none"/>';
  else if(code==='BO')art=horizontal('#d52b1e','#f9e300','#007934');
  else if(code==='TH')art=rect(0,40,'#a51931')+rect(7,26,'#fff')+rect(13,14,'#2d2a4a');
  else if(code==='VN')art=rect(0,40,'#da251d')+star(30,20,12,'#ff0');
  else if(code==='ID')art=rect(0,20,'#ce1126')+rect(20,20,'#fff');
  else if(code==='TR')art=rect(0,40,'#e30a17')+'<circle cx="25" cy="20" r="11" fill="#fff"/><circle cx="28" cy="20" r="9" fill="#e30a17"/>'+star(39,20,5,'#fff',18);
  else if(code==='CH')art=rect(0,40,'#d52b1e')+'<path d="M25 9h10v6h6v10h-6v6H25v-6h-6V15h6z" fill="#fff"/>';
  else if(code==='MY'){for(let i=0;i<14;i++)art+=rect(i*40/14,40/14,i%2?'#fff':'#cc0000');art+='<path d="M0 0h30v23H0z" fill="#010066"/><circle cx="12" cy="11" r="8" fill="#fc0"/><circle cx="15" cy="9" r="7" fill="#010066"/>'+star(23,12,5,'#fc0');}
  else if(code==='PH')art=rect(0,20,'#0038a8')+rect(20,20,'#ce1126')+'<path d="M0 0l30 20L0 40z" fill="#fff"/><circle cx="11" cy="20" r="4" fill="#fcd116"/>'+star(4,6,2,'#fcd116')+star(4,34,2,'#fcd116')+star(24,20,2,'#fcd116');
  else{code='';art='<rect width="60" height="40" rx="6" fill="#e9def1"/><g fill="none" stroke="#9275ab" stroke-width="1.8"><circle cx="30" cy="20" r="14"/><ellipse cx="30" cy="20" rx="6" ry="14"/><path d="M16 20h28M19 11h22M19 29h22"/></g>';}
  return {code,label:names[code]||'网络节点',src:'data:image/svg+xml;charset=utf-8,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 40">'+art+'</svg>')};
}
