// Repeat the authenticated, known-good WAV through the same native player.
// No oscillator, resampling code, alternate encoder, timers or overlapping sources.
export class BeaconBroadcast {
  constructor(audio, changed=()=>{}) {
    this.audio=audio;this.changed=changed;this.continuous=false;this.pending=false;this.error='';
    audio.addEventListener('playing',()=>this.update());
    for(const event of ['pause','ended']) audio.addEventListener(event,()=>{
      if(!this.pending){this.continuous=false;audio.loop=false;}
      this.update();
    });
    audio.addEventListener('error',()=>{
      this.continuous=false;this.pending=false;audio.loop=false;
      this.error='Audio could not play. Sign in again if your session expired, then retry.';
      this.update();
    });
  }
  update(){this.changed(this);}
  async start() {
    if(this.pending)return;
    this.pending=true;this.error='';this.continuous=true;
    this.audio.loop=true;this.audio.currentTime=0;this.update();
    try {await this.audio.play();}
    catch {this.continuous=false;this.audio.loop=false;this.error='Playback did not start. Check your audio output and press Start continuous broadcast again.';}
    finally {this.pending=false;this.update();}
  }
  stop(){this.continuous=false;this.audio.loop=false;this.audio.pause();this.audio.currentTime=0;this.update();}
}
const players=new WeakMap();
export function restoreBroadcast(root, previous=[]) {
  const old=Array.isArray(previous)?previous:[previous];
  const replacements=[...root.querySelectorAll('audio[data-beacon-audio]')];
  for(const audio of old){
    const replacement=replacements.find(item=>item.getAttribute('src')===audio.getAttribute('src'));
    if(replacement)replacement.replaceWith(audio);
    else {audio.loop=false;audio.pause();}
  }
  for(const audio of root.querySelectorAll('audio[data-beacon-audio]')) {
    let player=players.get(audio);
    if(!player){player=new BeaconBroadcast(audio);players.set(audio,player);}
    const panel=audio.closest('[data-broadcast-panel]');
    const button=panel.querySelector('[data-broadcast-toggle]');
    const status=panel.querySelector('[data-broadcast-status]');
    player.changed=p=>{
      button.disabled=p.pending;
      button.textContent=p.continuous?'Stop continuous broadcast':'Start continuous broadcast';
      status.textContent=p.error || (p.pending?'Starting broadcast…':p.continuous && !audio.paused?'Broadcasting continuously. Keep this page open and your device awake.':audio.paused?'Broadcast stopped.':'Playing one-shot beacon.');
    };
    button.onclick=()=>{
      if(player.continuous){player.stop();return;}
      // Only one speaker source at a time, even in workspaces with several beacons.
      for(const other of root.querySelectorAll('audio[data-beacon-audio]')) if(other!==audio){other.loop=false;other.pause();}
      return player.start();
    };
    player.update();
  }
}
