import test from 'node:test';
import assert from 'node:assert/strict';
import {demoAnalytics,periods,activityView,activityCard} from '../src/activity.js';
import {DemoApi} from '../src/demo.js';
test('all five fictional periods aggregate variable buckets with matching totals',()=>{
 const now=new Date('2026-09-27T18:30:00Z');
 for(const [i,[period]] of periods.entries()){
  const a=demoAnalytics(period,now);
  assert.equal(a.sample,true);assert.equal(a.buckets.length,[24,7,30,13,12][i]);
  assert.ok(a.total>0);assert.ok(a.previous_total>0);
  assert.equal(a.total,Object.values(a.totals).reduce((a,b)=>a+b,0));
  assert.equal(a.totals.views,a.buckets.reduce((s,b)=>s+b.views,0));
  assert.ok(new Set(a.buckets.map(b=>b.detections)).size>1);
  assert.deepEqual(a,demoAnalytics(period,now));
  const html=activityView(a,period,false,'');
  assert.equal((html.match(/data-period=/g)||[]).length,5);
  assert.match(html,/View accessible chart data/);assert.match(html,/Fictional/);
 }
});
test('analytics demo never fetches production and cards are actionable',async()=>{
 const original=globalThis.fetch;globalThis.fetch=()=>{throw Error('Network forbidden');};
 try{for(const [p] of periods){const a=await new DemoApi().request('/activity?period='+p);assert.equal(a.sample,true);assert.match(activityCard(a),/href="#\/activity"/);}}finally{globalThis.fetch=original;}
});
test('zero state and unavailable state are honest',()=>{
 const a=demoAnalytics('today',new Date('2026-09-27T00:00:00Z'));
 assert.equal(a.total,0);assert.match(activityView(a,'today',false,''),/No recorded activity/);
 assert.match(activityView(null,'today',false,'Unavailable'),/Unavailable/);
});
