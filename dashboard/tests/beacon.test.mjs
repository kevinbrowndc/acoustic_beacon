import test from 'node:test';
import assert from 'node:assert/strict';
import {beaconPage} from '../src/views.js';
const w={account:{role:'merchant'},campaigns:[],beacons:[{id:'assigned-id',beacon_id:'0x123456',active:true,served_offers:[]}]};
test('assigned beacon offers intentional playback and download, never autoplay',()=>{
 const html=beaconPage(w);
 assert.match(html,/audio controls preload="none"/);
 assert.match(html,/assigned-id\/audio.wav/);
 assert.match(html,/download/);
 assert.doesNotMatch(html,/autoplay/);
});
test('public demo contains no production audio endpoint',()=>{
 assert.doesNotMatch(beaconPage(w,true),/api\/v1|<audio/);
});
test('support controls only appear for manager workspace',()=>{
 const support_beacons=[{id:'id',business:'Example',beacon_id:'0x123456',active:true}];
 assert.doesNotMatch(beaconPage({...w,support_beacons}),/data-form="beacon-support"/);
 assert.match(beaconPage({...w,account:{role:'manager'},support_beacons}),/data-form="beacon-support"/);
});
