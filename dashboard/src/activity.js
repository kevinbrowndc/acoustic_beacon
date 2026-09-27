import {escapeHtml as e} from './domain.js';
export const periods=[['today','Today'],['7d','7 days'],['30d','30 days'],['90d','90 days'],['12m','12 months']];
const kinds={detections:'Beacon detections',views:'Offer views',saves:'Offer saves',actions:'Redemptions / actions'};
export const comparison=a=>a?.change_percent==null?'No previous-period comparison yet':`${a.change_percent>0?'+':''}${a.change_percent}% vs previous period`;
export function activityCard(a,error='') {
 return `<a href="#/activity" class="stat activity-link"><div class="stat-top"><span>Customer activity</span><span aria-hidden="true">↗</span></div><strong>${a?a.total.toLocaleString():'—'}</strong><small>Today · UTC</small><small>${e(error?'Activity unavailable':a?comparison(a):'Loading activity…')}</small></a>`;
}
export function activityView(a,period,loading,error) {
 const controls=periods.map(([key,label])=>`<button class="button ${period===key?'':'secondary'}" data-action="activity-period" data-period="${key}" aria-pressed="${period===key}">${label}</button>`).join('');
 let body='<p role="status">Loading activity…</p>';
 if(error)body=`<div class="alert" role="alert">${e(error)} <button class="button secondary" data-action="activity-period" data-period="${period}">Try again</button></div>`;
 else if(a){
  const points=a.buckets.map(b=>Object.keys(kinds).reduce((n,k)=>n+b[k],0)), max=Math.max(1,...points);
  const width=720,height=210,gap=600/points.length;
  const bars=points.map((n,i)=>`<rect x="${60+i*gap+gap*.12}" y="${height-n/max*170}" width="${gap*.76}" height="${n/max*170}" rx="2"><title>${e(a.buckets[i].start)}: ${n} events</title></rect>`).join('');
  const label=b=>new Date(b.start).toLocaleString('en-GB',{timeZone:'UTC',...(a.bucket==='hourly'?{hour:'2-digit',minute:'2-digit'}:a.bucket==='monthly'?{month:'short',year:'2-digit'}:{day:'numeric',month:'short'})});
  const ticks=[0,Math.floor((points.length-1)/2),points.length-1].map(i=>`<text x="${60+i*gap+gap/2}" y="238" text-anchor="middle">${e(label(a.buckets[i]))}</text>`).join('');
  body=`<div class="activity-summary"><div><span>Total customer activity</span><h2>${a.total.toLocaleString()}</h2><p>${e(comparison(a))}</p></div><span>${e(a.bucket)} buckets · UTC</span></div><div class="activity-metrics">${Object.entries(kinds).map(([k,l])=>`<div><span>${l}</span><strong>${a.totals[k].toLocaleString()}</strong></div>`).join('')}</div>${a.total===0?'<p class="activity-zero">No recorded activity in this period. Customer events will appear here when available.</p>':''}<svg class="activity-chart" viewBox="0 0 ${width} 250" role="img" aria-label="${e(periods.find(p=>p[0]===period)[1])} customer activity: ${a.total} events"><line x1="60" y1="210" x2="660" y2="210"/><text x="50" y="44" text-anchor="end">${max}</text><text x="50" y="210" text-anchor="end">0</text>${bars}${ticks}</svg><details class="activity-table"><summary>View accessible chart data</summary><div class="table-scroll"><table><thead><tr><th>Period (UTC)</th>${Object.values(kinds).map(k=>`<th>${k}</th>`).join('')}</tr></thead><tbody>${a.buckets.map(b=>`<tr><td>${e(label(b))}</td>${Object.keys(kinds).map(k=>`<td>${b[k]}</td>`).join('')}</tr>`).join('')}</tbody></table></div></details><p class="footnote">${e(a.tracking_note)} Counts are events, not unique customers. Comparisons use the equally elapsed preceding period.</p>`;
 }
 return `<div class="page-intro"><div><span class="eyebrow">UNDERSTAND YOUR REACH</span><h1>Customer activity</h1><p>Discoveries and interactions, over time.</p></div></div><section class="panel activity-panel" aria-busy="${loading}"><div class="activity-periods" aria-label="Activity period">${controls}</div>${body}</section>`;
}
// Deterministic fictional hourly counts spanning two years, for honest comparisons.
export function demoAnalytics(period,now=new Date()) {
 const day=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate()));
 const month=(d,n)=>new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+n,1));
 const days={today:1,'7d':7,'30d':30,'90d':90};
 let start,prevStart,prevEnd,edges=[],bucket;
 if(period==='12m'){
  start=month(now,-11);prevStart=month(start,-12);prevEnd=new Date(+month(now,-12)+(+now-+month(now,0)));
  for(let i=0;i<=12;i++)edges.push(month(start,i));bucket='monthly';
 }else{
  start=new Date(+day-(days[period]-1)*86400000);prevStart=new Date(+start-days[period]*86400000);prevEnd=new Date(+now-days[period]*86400000);
  const step=period==='today'?3600000:period==='90d'?7*86400000:86400000,end=+day+86400000;
  edges=[start];while(+edges.at(-1)<end)edges.push(new Date(Math.min(+edges.at(-1)+step,end)));
  bucket=period==='today'?'hourly':period==='90d'?'weekly':'daily';
 }
 const counts=(a,b)=>{
  const result={detections:0,views:0,saves:0,actions:0};
  for(let t=+a;t<+b;t+=3600000){
   const d=new Date(t),h=d.getUTCHours(),seed=Math.floor(t/3600000),noise=((Math.imul(seed,1664525)+1013904223)>>>0)%17;
   const n=h<6||h>21?0:Math.max(0,Math.round((5+noise)*(1+.35*Math.sin(seed/190))*(d.getUTCDay()===0?.65:1)));
   result.detections+=n;result.views+=Math.floor(n*.68);result.saves+=Math.floor(n*.19);result.actions+=Math.floor(n*.11);
  }return result;
 };
 const buckets=edges.slice(0,-1).map((a,i)=>({start:a.toISOString(),...counts(a,new Date(Math.min(+edges[i+1],+now)))}));
 const totals=Object.fromEntries(Object.keys(kinds).map(k=>[k,buckets.reduce((n,b)=>n+b[k],0)]));
 const total=Object.values(totals).reduce((a,b)=>a+b,0),previous_total=Object.values(counts(prevStart,prevEnd)).reduce((a,b)=>a+b,0);
 return {period,bucket,timezone:'UTC',buckets,totals,total,previous_total,change_percent:previous_total?Math.round((total-previous_total)*1000/previous_total)/10:null,sample:true,tracking_note:'Fictional demonstration activity. No real customers, detections or redemptions.'};
}
