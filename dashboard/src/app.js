import {restoreBroadcast} from './broadcast.js';
import {signupForm, registrationPayload, legalLinks} from './account.js';
const isSignup=/^\/merchant\/signup\/?$/.test(location.pathname);
import {activityCard, activityView} from './activity.js';
import {DemoApi} from './demo.js';
const isDemo = /^\/demo\/?$/.test(location.pathname);
import {Api} from './api.js';
import {routes, escapeHtml as e, resolveApiBase, routeFromHash, statusOf, offerPayload, localDate, dateToApi} from './domain.js';
import {icon, pill, button, empty, offersTable, overview, campaignCards, beaconPage, accountPage, preview} from './views.js';
const root=document.querySelector('#app');
const state={workspace:null, config:null, api:null, error:'', loading:true, busy:false, notice:'', search:'', filter:'all', menu:false};
Object.assign(state,{activity:null,today:null,period:'today',activityLoading:false,activityError:'',activityRequest:0});
const names={dashboard:'Dashboard',offers:'Offers',campaigns:'Campaigns',beacon:'Beacon',activity:'Activity',account:'Account'};
const icons=['grid','tag','layers','beacon','activity','user'];
const brand=`<a class="brand" href="#/dashboard"><img src="/merchant/beacon-logo.png" alt=""><span>Acoustic<span>Beacon <small>FOR BUSINESS</small></span></span></a>`;
function announce(text) { document.querySelector('#announcer').textContent=text; }
function notice(text) { state.notice=text; announce(text); }
function errorBox(text) { return `<div class="alert" role="alert"><span>${e(text)}</span>${button('Try again','retry',true)}</div>`; }
function render() {
  const previousAudio=[...root.querySelectorAll('audio[data-beacon-audio]')];
  if(!state.workspace || routeFromHash(location.hash)!=='beacon') for(const audio of previousAudio){audio.loop=false;audio.pause();}
  if(!state.workspace && isSignup){
    root.innerHTML=`<div class="signin"><div class="signin-brand">${brand}</div><main id="main" class="signin-card">${state.error?errorBox(state.error):''}${signupForm(state.loading)}</main></div>`;return;
  }
  if (!state.workspace) {
    root.innerHTML=`<div class="signin"><div class="signin-brand">${brand}</div><main id="main" class="signin-card"><span class="eyebrow">ACOUSTIC BEACON FOR BUSINESS</span><h1>Good things<br>start with a signal.</h1><p>Your offers. Your campaigns. One connected workspace.</p>${state.error?errorBox(state.error):''}${state.loading?'<div class="loading" role="status">Opening your workspace…</div>':state.config?.development_sign_in?`<div class="dev-label">Local development workspace</div><p class="small">Explore with persisted sample data. This is not a production sign-in.</p><button class="button wide" data-action="login" data-role="merchant" ${state.busy?'disabled':''}>Open merchant workspace ${icon('arrow')}</button><button class="button secondary wide" data-action="login" data-role="manager" ${state.busy?'disabled':''}>Explore manager workspace</button>`:`<form data-form="production-login"><label>Email<input name="email" type="email" autocomplete="username" required maxlength="320"></label><label>Password<input name="password" type="password" autocomplete="current-password" required maxlength="256"></label><p class="form-error" role="alert"></p><button class="button wide" type="submit">Sign in</button></form><p class="small"><a class="button secondary wide" href="/merchant/signup">Create Merchant Account</a></p><p class="small">Use your Acoustic Beacon account. Contact your account administrator if you need access or a password reset.</p>`}</main><p class="signin-footer">Connect a signal to something worth discovering.</p>${legalLinks}</div>`;
    return;
  }
  const w=state.workspace, route=routeFromHash(location.hash), manager=w.account.role==='manager';
  let content='';
  if(route==='dashboard') content=overview(w,activityCard(state.today,state.activityError));
  else if(route==='offers') content=`<div class="page-intro"><div><span class="eyebrow">${manager?'MERCHANT-APPROVED CONTENT':'SOMETHING WORTH DISCOVERING'}</span><h1>${manager?'Network offers':'Your offers'}</h1><p>${manager?'Select authorized offers for your campaigns. Merchant content stays merchant-owned.':'Create, refine, and choose when your offers are available.'}</p></div>${manager?'':button('Create offer','new-offer')}</div><section class="panel"><div class="list-tools"><label class="search">${icon('search')}<span class="sr-only">Search offers</span><input id="offer-search" type="search" placeholder="Search offers…" value="${e(state.search)}"></label><label class="filter"><span class="sr-only">Offer status</span><select id="offer-filter">${['all','active','inactive','scheduled','expired'].map(s=>`<option value="${s}" ${state.filter===s?'selected':''}>${s==='all'?'All statuses':s[0].toUpperCase()+s.slice(1)}</option>`).join('')}</select></label><span class="result-count" id="offer-count"></span></div><div id="offer-results"></div></section>${manager?'<p class="footnote">Eligibility is checked again when a campaign is saved and when content is served. Revoked consent removes delivery access.</p>':''}`;
  else if(route==='campaigns') content=`<div class="page-intro"><div><span class="eyebrow">CURATE THE DISCOVERY</span><h1>Your campaigns</h1><p>Bring multiple ${manager?'authorized merchant ':''}offers together behind one beacon.</p></div>${button('Create campaign','new-campaign')}</div>${campaignCards(w)}`;
  else if(route==='beacon') content=beaconPage(w,isDemo);
  else if(route==='activity') content=activityView(state.activity,state.period,state.activityLoading,state.activityError);
  else if(route==='account') content=accountPage(w);
  else content=empty('This page is not here','Choose a workspace page from the navigation.','<a class="button" href="#/dashboard">Back to dashboard</a>');
  root.innerHTML=`<div class="app-shell ${state.menu?'menu-open':''}"><aside class="sidebar">${brand}<div class="workspace-label">WORKSPACE</div><nav aria-label="Main navigation">${routes.map((r,i)=>`<a href="#/${r}" class="nav-link ${route===r?'selected':''}" ${route===r?'aria-current="page"':''}>${icon(icons[i])}<span>${names[r]}</span>${route===r?'<b></b>':''}</a>`).join('')}</nav><div class="sidebar-bottom"><div class="local-badge"><i></i> Development workspace</div><p>Real backend. Sample content.<br>No customer activity is simulated.</p><a href="#/account" class="profile"><span class="avatar">${manager?'AB':'AB'}</span><span><strong>${manager?'Network workspace':'Merchant workspace'}</strong><small>${manager?'Manager':'Merchant'} account</small></span>${icon('arrow',15)}</a></div></aside><div class="main-wrap"><header class="topbar"><button class="icon-button mobile-menu" data-action="menu" aria-label="Toggle navigation" aria-expanded="${state.menu}">${icon('menu')}</button><div class="breadcrumb">Workspace <span>/</span> <strong>${e(names[route] || 'Page not found')}</strong></div><div class="topbar-right"><span class="dev-chip">Sample data</span><span class="role-chip">${manager?'Manager':'Merchant'}</span><a href="#/account" class="avatar" aria-label="Account">AB</a></div></header><main id="main" tabindex="-1">${state.error?errorBox(state.error):''}${state.notice?`<div class="toast" role="status">${icon('check',16)} ${e(state.notice)}<button data-action="dismiss" aria-label="Dismiss message">${icon('close',15)}</button></div>`:''}${state.loading?'<div class="refreshing" role="status">Refreshing workspace…</div>':''}${content}<footer class="page-footer"><span>Acoustic Beacon · Merchant workspace</span>${legalLinks}</footer></main></div></div>`;
  if (route==='offers') renderOfferResults();
  if(isDemo){
    const banner=document.createElement('div');banner.className='toast';banner.textContent='PUBLIC DEMO - Fictional business and sample data. Changes stay in this tab and reset on reload.';document.querySelector('main').prepend(banner);
    document.querySelector('.local-badge').textContent='Public product demo';
    document.querySelector('.sidebar-bottom>p').textContent='Isolated sample workspace. No production account or data access.';
    document.querySelector('.dev-chip').textContent='Public demo';
    const logout=document.querySelector('[data-action="sign-out"]');if(logout)logout.textContent='Reset demo';
    document.querySelectorAll('.account-details dd').forEach(el=>{if(el.textContent.includes('Development session'))el.textContent='No sign-in required - isolated demo';if(el.textContent.includes('Local development'))el.textContent='Public demonstration';});
    const imageField=document.querySelector('[name="image_url"]');if(imageField)imageField.disabled=true;
  }
  if(!isDemo && !w.development){
    document.querySelector('.local-badge').textContent='Production workspace';
    document.querySelector('.sidebar-bottom>p').textContent='Your live account and campaign content.';
    document.querySelector('.dev-chip').textContent='Live';
    document.querySelectorAll('.account-details dd').forEach(el=>{if(el.textContent.includes('Development session'))el.textContent='Secure account session';if(el.textContent.includes('Local development'))el.textContent='Production';});
  }
  restoreBroadcast(root,previousAudio);
  installImageFallbacks();
}
function installImageFallbacks() { root.querySelectorAll('.preview-art img').forEach(img=>img.addEventListener('error',()=>{img.parentElement.innerHTML=icon('beacon',46);},{once:true})); }
function renderOfferResults() {
  const list=state.workspace.offers.filter(o=>(state.filter==='all'||statusOf(o)===state.filter)&&`${o.title} ${o.merchant}`.toLowerCase().includes(state.search.toLowerCase()));
  const target=document.querySelector('#offer-results');
  if(target) target.innerHTML=list.length?offersTable(list,state.workspace.account.role==='manager'):empty('No matching offers','Try another search or status filter.');
  const count=document.querySelector('#offer-count'); if(count) count.textContent=`${list.length} offer${list.length===1?'':'s'}`;
}
async function loadWorkspace() {
  state.loading=true; state.error=''; render();
  try {state.workspace=await state.api.request('/workspace');if(isSignup){location.replace('/merchant/');return;}state.today=null;await loadActivity(state.period);}
  catch(error) {if(error.status===401) state.workspace=null; else state.error=error.message;}
  finally {state.loading=false; render();}
}
async function loadActivity(period) {
  if(state.workspace?.account.role==='manager'){state.activity=null;state.today=null;state.activityLoading=false;state.activityError='Customer activity is private to each merchant account. Sign in as a merchant to view its analytics.';return;}
  const request=++state.activityRequest;state.period=period;state.activityLoading=true;state.activity=null;state.activityError='';render();
  try {
    const result=await state.api.request('/activity?period='+period);
    if(request!==state.activityRequest)return;
    state.activity=result;
    if(period==='today')state.today=result;
    else if(!state.today)state.today=await state.api.request('/activity?period=today');
  }catch(error){if(request===state.activityRequest)state.activityError=error.message;}
  finally{if(request===state.activityRequest){state.activityLoading=false;render();}}
}
async function initialize() {
  if(isDemo){state.api=new DemoApi();state.config={production:false,development_sign_in:false};await loadWorkspace();return;}
  state.loading=true; state.error=''; render();
  try {
    const response=await fetch(new URL('/api/v1/dashboard/config', location.origin),{cache:'no-store',signal:AbortSignal.timeout(8000)});
    if(!response.ok) throw new Error('The backend configuration is unavailable. Please try again shortly.');
    state.config=await response.json();
    state.api=new Api(resolveApiBase(state.config.api_base_url,state.config.production,location.origin));
    await loadWorkspace();
  } catch(error) {state.error=error.message; state.loading=false; render();}
}
function modal(title,subtitle,body,formType,id='') {
  document.querySelector('dialog')?.remove();
  const dialog=document.createElement('dialog'); dialog.className='editor';
  dialog.innerHTML=`<div class="dialog-heading"><div><span class="eyebrow">${formType==='offer'?'YOUR NEXT DISCOVERY':'CAMPAIGN WORKSPACE'}</span><h2>${e(title)}</h2><p>${e(subtitle)}</p></div><button class="icon-button" data-action="close-dialog" aria-label="Close dialog">${icon('close')}</button></div><form data-form="${formType}" data-id="${e(id)}">${body}<div class="form-error" role="alert"></div><div class="dialog-actions"><button class="button secondary" type="button" data-action="close-dialog">Cancel</button><button class="button" type="submit">Save ${formType}</button></div></form>`;
  root.append(dialog); dialog.showModal();
  dialog.querySelector('input,textarea,select')?.focus();
  dialog.addEventListener('close',()=>dialog.remove());
  installImageFallbacks();
}
function field(label,name,value='',type='text',required=false,extras='') { return `<label>${e(label)}<input type="${type}" name="${name}" value="${e(value)}" ${required?'required':''} ${extras}></label>`; }
function openOffer(id) {
  const o=state.workspace.offers.find(o=>o.id===id)||{};
  if(state.workspace.account.role==='manager') {
    modal('Offer preview','Owned and maintained by the participating merchant.',preview(o),'preview',id);
    const d=document.querySelector('dialog');d.querySelector('[type=submit]').remove();d.querySelector('[data-action=close-dialog]').focus();return;
  }
  modal(id?'Edit offer':'Create an offer','Use a clear headline and tell customers how to redeem it.',`<div class="editor-grid"><div class="form-fields">${field('Headline','title',o.title,'text',true,'maxlength="200"')}<label>Description<textarea name="description" required maxlength="20000" rows="4">${e(o.description)}</textarea></label><label>Redemption instructions / terms<textarea name="terms" required maxlength="20000" rows="3">${e(o.terms)}</textarea></label><div class="field-row">${field('Starts (your local time)','start_at',localDate(o.start_at),'datetime-local')}${field('Ends (your local time)','end_at',localDate(o.end_at),'datetime-local')}</div>${field('Image URL (optional, HTTPS)','image_url',o.image_url,'url',false,'placeholder="https://…"')}<small class="help">Use a hosted image URL. File uploads are not available yet.</small><label class="check-row"><input name="active" type="checkbox" ${o.active?'checked':''}><span><strong>Offer is active</strong><small>Dates and campaign status still control availability.</small></span></label><label class="check-row"><input name="manager_eligible" type="checkbox" ${o.manager_eligible?'checked':''}><span><strong>Eligible for network campaigns</strong><small>Allow managers to include this offer. They cannot edit or own it. You can revoke access at any time.</small></span></label></div><aside>${preview({...o,merchant:state.workspace.account.business})}</aside></div>`,'offer',id);
}
function openCampaign(id) {
  const c=state.workspace.campaigns.find(c=>c.id===id)||{offer_ids:[]};
  const choices=state.workspace.offers;
  const unavailable=c.offer_ids.filter(id=>!choices.some(o=>o.id===id));
  modal(id?'Edit campaign':'Create a campaign','Choose the offers a connected beacon will serve.',`${field('Campaign name','name',c.name,'text',true,'maxlength="200"')}<div class="field-row">${field('Starts (your local time)','start_at',localDate(c.start_at),'datetime-local')}${field('Ends (your local time)','end_at',localDate(c.end_at),'datetime-local')}</div><label class="check-row"><input name="active" type="checkbox" ${c.active?'checked':''}><span><strong>Campaign is active</strong><small>Only active, in-date and authorized offers are served.</small></span></label><div class="selection-heading"><h3>Select offers</h3><span>You can choose more than one</span></div>${unavailable.length?'<p class="warning">An offer is no longer eligible. It will be removed from this campaign when you save.</p>':''}<div class="offer-selection">${choices.length?choices.map(o=>`<label class="offer-choice"><input type="checkbox" name="offer_ids" value="${e(o.id)}" ${c.offer_ids.includes(o.id)?'checked':''}><span><strong>${e(o.title)}</strong><small>${e(o.merchant)}</small></span>${pill(statusOf(o))}</label>`).join(''):'<p class="help">No eligible offers are available. You can save an empty campaign and add offers later.</p>'}</div><p class="help">Changing this selection does not change your beacon ID.</p>`,'campaign',id);
}
root.addEventListener('input',event=>{
  if(event.target.id==='offer-search'){state.search=event.target.value;renderOfferResults();}
  if(event.target.name==='title' && document.querySelector('#preview-title')) document.querySelector('#preview-title').textContent=event.target.value||'Your offer headline';
  if(event.target.name==='description' && document.querySelector('#preview-description')) document.querySelector('#preview-description').textContent=event.target.value;
});
root.addEventListener('change',event=>{if(event.target.id==='offer-filter'){state.filter=event.target.value;renderOfferResults();}});
root.addEventListener('click',async event=>{
  const control=event.target.closest('[data-action]'); if(!control)return;
  const {action,id,role}=control.dataset;
  if(action==='activity-period')return loadActivity(control.dataset.period);
  if(action==='new-offer'||action==='edit-offer'||action==='preview-offer')return openOffer(id);
  if(action==='new-campaign'||action==='edit-campaign')return openCampaign(id);
  if(action==='close-dialog')return document.querySelector('dialog')?.close();
  if(action==='menu'){state.menu=!state.menu;render();return;}
  if(action==='dismiss'){state.notice='';render();return;}
  if(action==='retry')return state.api?loadWorkspace():initialize();
  if(action==='login') {
    state.busy=true;state.error='';render();
    try {await state.api.request('/dev-session',{method:'POST',body:{role},headers:{'X-Beacon-Development':'1'}});await loadWorkspace();}
    catch(error){state.error=error.message;}
    finally {state.busy=false;render();} return;
  }
  if(action==='sign-out' && isDemo){state.api.reset();state.today=null;state.period='today';await loadWorkspace();return;}
  if(action==='sign-out') {
    control.disabled=true;
    try {await state.api.request('/sign-out',{method:'POST'});state.workspace=null;state.today=null;state.activity=null;state.activityRequest++;state.notice='';state.api.csrf='';}
    catch(error){state.error=error.message;}
    render();
  }
});
root.addEventListener('submit',async event=>{
  const form=event.target.closest('form[data-form]');if(!form)return;event.preventDefault();
  const data=new FormData(form), type=form.dataset.form, id=form.dataset.id;
  if(type==='production-signup'){
    const submit=form.querySelector('[type=submit]'),errorBox=form.querySelector('.form-error');
    submit.disabled=true;errorBox.textContent='';
    try{await state.api.request('/register',{method:'POST',body:registrationPayload(data)});form.reset();location.assign('/merchant/');}
    catch(error){errorBox.textContent=error.message;form.querySelector('[name=password]').value='';form.querySelector('[name=confirm_password]').value='';submit.disabled=false;}
    return;
  }
  if(type==='production-login'){
    const submit=form.querySelector('[type=submit]');submit.disabled=true;submit.textContent='Signing in…';
    const errorBox=form.querySelector('.form-error');errorBox.textContent='';
    try{await state.api.request('/session',{method:'POST',body:{email:data.get('email'),password:data.get('password')}});form.reset();state.error='';await loadWorkspace();}
    catch(error){errorBox.textContent=error.message;form.querySelector('[name=password]').value='';submit.disabled=false;submit.textContent='Sign in';}
    return;
  }
  const errorBox=form.querySelector('.form-error');errorBox.textContent='';
  const submit=form.querySelector('[type=submit]');submit.disabled=true;submit.textContent='Saving…';
  try {
    if(type==='beacon-support' && !isDemo) {
      await state.api.request(`/support/beacons/${id}`,{method:'PUT',body:{active:data.has('active')}});
      notice('Beacon availability updated.');
    } else if(type==='directory-profile') {
      await state.api.request('/profile',{method:'PUT',body:{website:data.get('website')||null,directory_opt_in:data.has('directory_opt_in')}});
      notice('Website and directory preference saved.');
    } else if(type==='offer') {
      const body={title:data.get('title'),description:data.get('description'),terms:data.get('terms'),image_url:data.get('image_url')||null,start_at:dateToApi(data.get('start_at')),end_at:dateToApi(data.get('end_at')),active:data.has('active'),manager_eligible:data.has('manager_eligible')};
      await state.api.request(`/offers${id?'/'+id:''}`,{method:id?'PUT':'POST',body});
      notice('Offer saved. Campaign delivery uses your latest content.');
    } else if(type==='campaign') {
      await state.api.request(`/campaigns${id?'/'+id:''}`,{method:id?'PUT':'POST',body:{name:data.get('name'),active:data.has('active'),start_at:dateToApi(data.get('start_at')),end_at:dateToApi(data.get('end_at')),offer_ids:data.getAll('offer_ids')}});
      notice('Campaign saved. Your beacon ID stays the same.');
    } else if(type==='assignment') {
      await state.api.request(`/beacons/${id}/campaign`,{method:'PUT',body:{campaign_id:data.get('campaign_id')||null}});
      notice('Beacon assignment updated.');
    }
    document.querySelector('dialog')?.close();await loadWorkspace();
  } catch(error) {errorBox.textContent=error.message;announce(error.message);submit.disabled=false;submit.textContent=type==='assignment'?'Save assignment':`Save ${type}`;}
});
window.addEventListener('hashchange',()=>{state.menu=false;state.notice='';render();document.querySelector('#main')?.focus({preventScroll:true});});
initialize();
