import test from 'node:test';
import assert from 'node:assert/strict';
import {DemoApi} from '../src/demo.js';
test('demo edits remain isolated and reset without network access',async()=>{
 const prior=globalThis.fetch;globalThis.fetch=()=>{throw Error('Network forbidden');};
 try {const demo=new DemoApi(),other=new DemoApi();await demo.request('/offers/coffee',{method:'PUT',body:{title:'Changed',active:false}});assert.equal((await demo.request('/workspace')).offers[0].title,'Changed');assert.equal((await other.request('/workspace')).offers[0].title,'20% off your next coffee');demo.reset();assert.equal((await demo.request('/workspace')).beacons[0].served_offers.length,2);await assert.rejects(()=>demo.request('/dev-session',{method:'POST'}));}finally{globalThis.fetch=prior;}
});
