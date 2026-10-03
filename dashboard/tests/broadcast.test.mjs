import test from 'node:test';
import assert from 'node:assert/strict';
import {BeaconBroadcast,restoreBroadcast} from '../src/broadcast.js';
class Audio extends EventTarget {
 constructor(){super();this.src='/api/v1/dashboard/beacons/assigned/audio.wav';this.loop=false;this.paused=true;this.currentTime=0;this.plays=0;}
 async play(){this.plays++;this.paused=false;this.dispatchEvent(new Event('playing'));}
 pause(){this.paused=true;this.dispatchEvent(new Event('pause'));}
}
test('continuous uses the exact one-shot source and native loop, stops cleanly',async()=>{
 const audio=new Audio(),player=new BeaconBroadcast(audio),src=audio.src;
 await player.start();assert.equal(audio.src,src);assert.equal(audio.loop,true);assert.equal(audio.plays,1);
 player.stop();assert.equal(audio.loop,false);assert.equal(audio.paused,true);
 await audio.play();assert.equal(audio.loop,false); // Existing one-shot control remains one-shot.
});
test('blocked playback reports failure instead of pretending to broadcast',async()=>{
 const audio=new Audio();audio.play=async()=>{throw Error('blocked');};
 const player=new BeaconBroadcast(audio);await player.start();
 assert.equal(player.continuous,false);assert.equal(audio.loop,false);assert.match(player.error,/did not start/);
});
test('native pause and errors stop continuous state',async()=>{
 const audio=new Audio(),p=new BeaconBroadcast(audio);await p.start();audio.pause();assert.equal(p.continuous,false);
 await p.start();audio.dispatchEvent(new Event('error'));assert.equal(p.continuous,false);assert.equal(audio.loop,false);
});
test('leaving Beacon page stops old audio',async()=>{
 const audio=new Audio();await new BeaconBroadcast(audio).start();
 restoreBroadcast({querySelectorAll:()=>[]},audio);
 assert.equal(audio.paused,true);assert.equal(audio.loop,false);
});
