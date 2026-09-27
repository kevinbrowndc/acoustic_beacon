import {demoAnalytics} from './activity.js';
export class DemoApi {
  constructor(){this.reset();}
  reset(){
    this.w={account:{role:'merchant',business:'Harbour & Pine · Demo café',email:'hello@example.invalid',description:'A fictional neighbourhood café. Explore safely — nothing here is a real account.'},offers:[
      {id:'coffee',title:'20% off your next coffee',description:'Discover your new favourite flat white or seasonal latte.',terms:'Illustrative demo offer. Not redeemable.',active:true,manager_eligible:true},
      {id:'lunch',title:'Lunch for two, made local',description:'Two sandwiches and two coffees for a relaxed lunch break.',terms:'Illustrative demo offer. Not redeemable.',active:true,manager_eligible:false},
      {id:'weekend',title:'A little extra this weekend',description:'A pastry with your morning coffee.',terms:'Illustrative demo offer. Not redeemable.',active:false,manager_eligible:true}
    ].map(o=>({...o,merchant:'Harbour & Pine',start_at:null,end_at:null,image_url:null})),campaigns:[{id:'morning',name:'Discover Harbour & Pine',active:true,sample:true,offer_ids:['coffee','lunch']},{id:'weekend',name:'Weekend discoveries',active:false,sample:true,offer_ids:['weekend']}],beacons:[{id:'demo-beacon',beacon_id:'0xABC123',active:true,campaign_id:'morning',served_offers:[]}],analytics_available:false};
  }
  async request(path,{method='GET',body}={}){
    if(path.startsWith('/activity?period='))return demoAnalytics(path.split('=')[1]);
    if(path==='/workspace'){
      for(const beacon of this.w.beacons){const c=this.w.campaigns.find(c=>c.id===beacon.campaign_id);beacon.served_offers=c?.active?this.w.offers.filter(o=>o.active&&c.offer_ids.includes(o.id)).map(o=>({...o,merchant:{name:o.merchant}})):[];}
      return structuredClone(this.w);
    }
    const [kind,id]=path.slice(1).split('/');
    if(['offers','campaigns'].includes(kind)&&['POST','PUT'].includes(method)){
      const item={...structuredClone(body),id:id||'demo-'+crypto.randomUUID()};
      if(kind==='offers'){item.merchant='Harbour & Pine';item.image_url=null;}
      if(id){const i=this.w[kind].findIndex(o=>o.id===id);if(i<0)throw Error('Demo item unavailable');this.w[kind][i]=item;}
      else this.w[kind].unshift(item);
      return structuredClone(item);
    }
    if(kind==='beacons'&&method==='PUT'){this.w.beacons.find(b=>b.id===id).campaign_id=body.campaign_id;return {updated:true};}
    throw Error('This action is unavailable in the public demo.');
  }
}
