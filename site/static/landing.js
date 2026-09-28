const moments = [
  {app:'Safari',time:'09:12–09:24',title:'A starting point for Project Atlas',summary:'Read the customer research. People wanted fewer setup steps and a clearer explanation of screen permissions.',source:'Example source text: Atlas research notes. Main friction: too many setup steps. Explain what screen access enables before asking for permission.'},
  {app:'Notes',time:'09:25–09:38',title:'The thought becomes a plan',summary:'Gathered the research into a short brief: show a useful first result before asking people to configure everything.',source:'Example source text: Atlas brief. First-run goal: capture one useful moment. Keep privacy choices visible. Compare two onboarding concepts.'},
  {app:'Figma',time:'09:40–10:18',title:'A prototype worth coming back to',summary:'Compared two onboarding concepts for Atlas. The next step: review the permission screen on Friday.',source:'Example source text: Atlas / onboarding exploration. Concept A: permission-first. Concept B: explain, enable, first moment. Review Friday.'}
];
const entries = document.getElementById('demo-entries');
const search = document.getElementById('demo-search');
function el(tag,text,cls){const node=document.createElement(tag);node.textContent=text;if(cls)node.className=cls;return node;}
function render(){
  entries.replaceChildren();
  const terms=search.value.toLowerCase().trim().split(/\s+/).filter(Boolean);
  const filtered=moments.filter(m=>terms.every(t=>Object.values(m).join(' ').toLowerCase().includes(t)));
  for(const m of filtered){const article=el('article','','demo-entry');const header=el('header','');header.append(el('span',m.app+' · '+m.title),el('time',m.time));const detail=el('details','');detail.append(el('summary','View source text'),el('pre',m.source));article.append(header,el('p',m.summary),detail);entries.append(article);}
  if(!filtered.length) entries.append(el('p','No example moments match. Try “Atlas”, “permissions”, or “prototype”.','demo-empty'));
}
search.addEventListener('input',render);document.getElementById('demo-clear').onclick=()=>{search.value='';render();search.focus();};render();
const useCases={
  recall:{eyebrow:'BACK IN THE FLOW',title:'“Where was that detail?”\nRight where you left it.',copy:'Search for a project, phrase, or decision. Recover the context around it, with the app, time, and original text beside the summary.',label:'A MOMENT WORTH KEEPING',question:'What did I find about\nthe Atlas onboarding?',answer:'10:24 · Safari → Notes\nThe research pointed to a shorter permission flow. The next step was to compare two prototype concepts.',foot:'Illustrative journal entry · Check source text'},
  review:{eyebrow:'THE DAY, WITH A LITTLE DISTANCE',title:'From scattered tabs\nto a connected day.',copy:'Review work in the order it happened. Consecutive captures become sessions, and each app switch stays in the story. Export one Markdown file when you’re ready.',label:'ONE FILE. THE WHOLE THREAD.',question:'Research. Brief. Prototype.\nIt all belongs together.',answer:'09:12 · Customer research in Safari\n09:25 · The working brief in Notes\n09:40 · Onboarding exploration in Figma',foot:'Illustrative day · Actual journals retain source evidence'},
  assistant:{eyebrow:'A BETTER PLACE TO START',title:'Your context, ready\nfor the next conversation.',copy:'Connect your assistant through MCP. Let it find relevant moments and read the daily journal instead of asking you to reconstruct your work from memory.',label:'A LOCAL MCP CONNECTION',question:'“Read today’s flow.\nHelp me pick up Atlas.”',answer:'Available tools: read_day_flow, day_sessions, search_screen_memory, and read_app_day. The connected assistant can read the captured journal.',foot:'Read-only MCP · Connect only assistants you trust'}
};
const tabs=[...document.querySelectorAll('[data-use]')];
function choose(tab){tabs.forEach(t=>{const active=t===tab;t.setAttribute('aria-selected',String(active));t.tabIndex=active?0:-1;});const c=useCases[tab.dataset.use];document.getElementById('use-panel').setAttribute('aria-labelledby',tab.id);for(const [id,key] of [['use-eyebrow','eyebrow'],['use-title','title'],['use-copy','copy'],['example-label','label'],['example-question','question'],['example-answer','answer'],['example-footnote','foot']]){const n=document.getElementById(id);n.textContent=c[key];}}
tabs.forEach((tab,i)=>{tab.onclick=()=>choose(tab);tab.onkeydown=e=>{if(e.key==='ArrowRight'||e.key==='ArrowLeft'){e.preventDefault();const next=tabs[(i+(e.key==='ArrowRight'?1:tabs.length-1))%tabs.length];choose(next);next.focus();}};});
