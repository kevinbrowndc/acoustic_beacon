import test from 'node:test';
import assert from 'node:assert/strict';
import {resolveApiBase,statusOf,escapeHtml,offerPayload,routeFromHash,dateToApi,safeImage} from '../src/domain.js';
import {Api} from '../src/api.js';
test('production API config never falls back to local data',()=>{
  for(const url of ['', 'http://localhost:8000','https://localhost','https://user:pass@example.com','https://api.example.com/path']) assert.throws(()=>resolveApiBase(url,true,'http://localhost'));
  assert.equal(resolveApiBase('https://api.example.com',true,'http://localhost'),'https://api.example.com');
  assert.equal(resolveApiBase('',true,'https://beacon.example.com'),'https://beacon.example.com');
  assert.equal(resolveApiBase('',false,'http://127.0.0.1:8000'),'http://127.0.0.1:8000');
});
test('offer states use real dates and activation',()=>{
  const now=new Date('2030-01-02T00:00:00Z');
  assert.equal(statusOf({active:false},now),'inactive');
  assert.equal(statusOf({active:true,start_at:'2030-01-03T00:00:00Z'},now),'scheduled');
  assert.equal(statusOf({active:true,end_at:now.toISOString()},now),'expired');
  assert.equal(statusOf({active:true,start_at:now.toISOString()},now),'active');
});
test('safe rendering and schema-aligned payload',()=>{
  assert.equal(escapeHtml('<script>"&'), '&lt;script&gt;&quot;&amp;');
  assert.equal(safeImage('javascript:alert(1)'),null);
  assert.equal(safeImage('https://user:pass@example.com/image'),null);
  assert.equal(offerPayload({title:'Offer',id:99}).id,undefined);
  assert.equal(routeFromHash('#/campaigns'),'campaigns');
  assert.equal(dateToApi(''),null);
});
test('API sends CSRF and handles validation failure without fake data',async()=>{
  const original=global.fetch;
  global.fetch=async(url,init)=>{assert.equal(init.headers['X-CSRF-Token'],'token');return {ok:false,status:422,json:async()=>({detail:[{loc:['body','title'],msg:'Required'}]})};};
  try{const api=new Api('http://localhost');api.csrf='token';await assert.rejects(api.request('/offers',{method:'POST',body:{}}),/title: Required/);}finally{global.fetch=original;}
});
test('API timeout and offline failures are actionable',async()=>{
  const original=global.fetch;
  try{
    global.fetch=async()=>{throw new TypeError('network');};
    await assert.rejects(new Api('http://localhost').request('/workspace'),/Cannot reach/);
    global.fetch=async()=>{const error=new Error();error.name='AbortError';throw error;};
    await assert.rejects(new Api('http://localhost').request('/workspace'),/too long/);
  }finally{global.fetch=original;}
});
