const $ = id => document.getElementById(id);
let state, selectedApp = '', selectedName = 'Daily flow', rows = [], searchTimer, loading = false, requestVersion = 0, flowMode = false, welcomeShown = false;
const localDate = new Date();
$('date').value = `${localDate.getFullYear()}-${String(localDate.getMonth()+1).padStart(2,'0')}-${String(localDate.getDate()).padStart(2,'0')}`;
async function api(path, options = {}) {
  const response = await fetch(path, {...options, headers:{'Content-Type':'application/json','X-Constant-Watch':'local',...options.headers}});
  if (!response.ok) throw new Error((await response.json()).detail || `Request failed (${response.status})`);
  return response.json();
}
function error(message) { $('error').textContent = message; $('error').hidden = !message; }
function node(tag, text, className) { const n = document.createElement(tag); if(text !== undefined) n.textContent = text; if(className) n.className = className; return n; }
async function updateStatus() {
  try {
    state = await api('/api/status');
    if(state.platform === 'win32' && !state.settings.onboarding_complete && !welcomeShown) { welcomeShown=true; $('welcome-dialog').showModal(); }
    $('setup-model-status').textContent = state.download?.running ? state.download.status : state.model.available ? 'Qwen is ready on your computer.' : state.download?.status || state.model.error;
    $('download-model').disabled = !!state.download?.running || state.model.available;
    const paused = state.settings.paused;
    const missing = !state.permissions.accessibility || !state.permissions.screen_recording;
    $('live-state').textContent = paused ? 'Paused' : missing ? 'Setup needed' : state.error ? 'Needs attention' : 'Watching locally';
    $('live-state').classList.toggle('paused', paused || missing || !!state.error);
    $('pause').textContent = paused ? 'Resume capture' : 'Pause capture';
    $('attention').hidden = !missing && state.model.available;
    $('grant').hidden = !missing;
    $('attention-title').textContent = missing ? 'Give your journal access to the screen' : 'Your local model needs attention';
    $('attention-text').textContent = missing ? (state.platform === 'win32' ? 'Unlock your Windows desktop. Elevated apps and protected windows cannot be read. Check Capture settings for exclusions.' : 'Enable Accessibility and Screen Recording in macOS System Settings → Privacy & Security for Constant Watch Capture (or the launching app shown by macOS). Then resume your work.') : state.model.error;
    $('capture-detail').textContent = `${state.capture_status} · Every ${state.settings.interval_seconds}s · ${state.settings.retention_days}-day history`;
    $('model-detail').textContent = `${state.settings.model} · ${state.pending_summaries} awaiting summary`;
    $('last-seen').textContent = state.last_capture ? `Last capture ${new Date(state.last_capture).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'})}` : 'Waiting for first capture';
    if (state.error || state.model_error) error(state.error || state.model_error); else error('');
  } catch(e) { error(`Cannot reach Constant Watch. ${e.message}`); $('live-state').textContent = 'Disconnected'; }
}
async function updateApps() {
  const apps = await api('/api/apps');
  $('apps').replaceChildren();
  $('app-count').textContent = apps.length;
  $('total-count').textContent = apps.reduce((n,a)=>n+a.captures,0);
  $('no-apps').hidden = apps.length > 0;
  $('all-apps').classList.toggle('selected', !selectedApp);
  for (const app of apps) {
    const b = node('button', undefined, 'app-button');
    b.classList.toggle('selected', selectedApp === app.app_id);
    b.title = app.app_id;
    b.append(node('span',app.app_name), node('span',String(app.captures)));
    b.onclick = () => selectApp(app.app_id, app.app_name);
    $('apps').append(b);
  }
}
function selectApp(id, name) { selectedApp=id; selectedName=name; $('journal-title').textContent=name; updateApps().catch(e=>error(e.message)); loadEntries().catch(e=>error(e.message)); }
function renderEntries() {
  const openIds = new Set([...document.querySelectorAll('.entry details[open]')].map(n=>n.dataset.id));
  $('entries').replaceChildren();
  for(const row of rows) {
    const article=node('article',undefined,'entry');
    const date=new Date(flowMode ? row.start : row.captured_at);
    const time=node('div',date.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}),'time');
    time.append(node('small',flowMode ? '– '+new Date(row.end).toLocaleTimeString([], {hour:'2-digit',minute:'2-digit'}) : date.toLocaleDateString([], {month:'short',day:'numeric'})));
    const body=node('div');
    const top=node('div',undefined,'entry-top');
    top.append(node('span',row.app_name,'entry-app'));
    if(row.ax_text) top.append(node('span','ACCESSIBILITY','tag'));
    if(row.ocr_text) top.append(node('span','OCR','tag'));
    body.append(top,node('h3',row.window_title || 'Untitled window'),node('p',row.summary || 'Text saved. Waiting for the local model to summarize.','entry-summary'));
    const details=node('details'); details.dataset.id=String(row.id); details.open=openIds.has(String(row.id));
    details.append(node('summary',flowMode ? `${row.observations.length} captured moments · view evidence` : `View captured text · #${row.id}`),node('pre',flowMode ? row.observations.map(o=>`#${o.id} · ${o.captured_at}\nACCESSIBILITY\n${o.ax_text || 'Unavailable'}\n\nOCR\n${o.ocr_text || 'Unavailable'}`).join('\n\n') : `ACCESSIBILITY\n${row.ax_text || 'Unavailable'}\n\nOCR\n${row.ocr_text || 'Unavailable'}`));
    const warnings=JSON.parse(row.warnings || '[]');
    if(warnings.length) details.append(node('p',warnings.join(' · '),'muted'));
    body.append(details); article.append(time,body); $('entries').append(article);
  }
  $('empty').hidden=rows.length>0;
  const filtered=selectedApp || $('search').value;
  $('empty-title').textContent=filtered ? 'No matching moments yet.' : 'Your next thought has a place.';
  $('empty-text').textContent=filtered ? 'Try a different search, application, or date.' : 'Use your apps as usual. New screen text appears here automatically once screen permissions are enabled.';
  $('result-count').textContent=flowMode ? `${rows.length} grouped sessions · Earliest first` : `${rows.length} captured moment${rows.length===1?'':'s'}${selectedApp?' in '+selectedName:''}`;
  $('export').disabled=!$('date').value || !rows.length;
}
async function loadEntries(append=false) {
  const version=++requestVersion;
  const isFlow=!selectedApp && !$('search').value && !!$('date').value;
  if(isFlow){
    const page=await api('/api/day-flow?'+new URLSearchParams({day:$('date').value,offset:append?rows.length:0,limit:50}));
    if(version!==requestVersion)return;
    flowMode=true;rows=append?[...rows,...page.sessions]:page.sessions;
    $('load-more').hidden=page.next_offset===null;$('load-more').textContent='Continue through the day';renderEntries();return;
  }
  const params=new URLSearchParams({app_id:selectedApp,day:$('date').value,q:$('search').value,limit:50});
  if(append && rows.length) params.set('before',rows.at(-1).id);
  const result=await api('/api/observations?'+params);
  if(version!==requestVersion) return;
  flowMode=false;
  rows=append?[...rows,...result]:result;
  $('load-more').hidden=result.length<50;
  renderEntries();
}
async function refresh() {
  if(loading || $('settings-dialog').open) return;
  loading=true;
  try { await Promise.all([updateStatus(),updateApps()]); if(rows.length<=50) await loadEntries(); } catch(e) { error(e.message); } finally {loading=false;}
}
$('all-apps').onclick=()=>selectApp('','Daily flow');
$('pause').onclick=async()=>{if(!state)return; try {await api('/api/settings',{method:'PUT',body:JSON.stringify({...state.settings,paused:!state.settings.paused})}); await updateStatus();}catch(e){error(e.message);}};
$('grant').onclick=async()=>{ $('grant').disabled=true; try{await api('/api/permissions',{method:'POST'});await updateStatus();}catch(e){error(e.message);}finally{$('grant').disabled=false;}};
$('search').oninput=()=>{clearTimeout(searchTimer); searchTimer=setTimeout(()=>loadEntries().catch(e=>error(e.message)),250);};
$('date').onchange=()=>loadEntries().catch(e=>error(e.message));
$('clear-date').onclick=()=>{$('date').value='';loadEntries().catch(e=>error(e.message));};
$('load-more').onclick=()=>loadEntries(true).catch(e=>error(e.message));
$('export').onclick=()=>{location.href='/api/markdown?'+new URLSearchParams({app_id:selectedApp,day:$('date').value});};
$('open-settings').onclick=()=>{if(!state)return; $('interval').value=state.settings.interval_seconds; $('retention').value=state.settings.retention_days; $('exclusions').value=state.settings.excluded_apps.join('\n'); $('data-path').textContent=state.data_directory; $('mcp-config').textContent=JSON.stringify(state.mcp_config,null,2); $('settings-dialog').showModal();};
$('close-settings').onclick=()=>$('settings-dialog').close();
$('settings-form').onsubmit=async e=>{e.preventDefault();try{await api('/api/settings',{method:'PUT',body:JSON.stringify({...state.settings,interval_seconds:Number($('interval').value),retention_days:Number($('retention').value),excluded_apps:$('exclusions').value.split('\n').map(x=>x.trim()).filter(Boolean)})});$('settings-dialog').close();await refresh();}catch(e){error(e.message);}};
refresh(); setInterval(refresh,7000);

$('reopen-welcome').onclick=()=>$('welcome-dialog').showModal();
$('install-ollama').onclick=async()=>{try{await api('/api/open-ollama',{method:'POST'});}catch(e){error(e.message);}};
$('download-model').onclick=async()=>{try{await api('/api/model/setup',{method:'POST'});await updateStatus();}catch(e){error(e.message);}};
async function finishWelcome(start){if(!state)return;try{await api('/api/settings',{method:'PUT',body:JSON.stringify({...state.settings,onboarding_complete:true,paused:!start})});$('welcome-dialog').close();await refresh();}catch(e){error(e.message);}}
$('finish-welcome').onclick=()=>finishWelcome(true);
$('explore-welcome').onclick=()=>finishWelcome(false);
