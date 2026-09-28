import {renderDirectory} from '../../lib/directory.mjs';
export default async function handler(request){
 if(!['GET','HEAD'].includes(request.method))return new Response('Method not allowed',{status:405,headers:{Allow:'GET, HEAD'}});
 let rows=[],failed=false;
 try{
  const response=await fetch('https://merchant.acousticbeacon.com/api/v1/businesses',{headers:{Accept:'application/json'},signal:AbortSignal.timeout(8000),cache:'no-store'});
  if(!response.ok)throw Error('Unavailable');rows=await response.json();if(!Array.isArray(rows))throw Error('Invalid response');
 }catch{failed=true;}
 return new Response(request.method==='HEAD'?null:renderDirectory(rows,failed),{status:failed?503:200,headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Netlify-CDN-Cache-Control':'no-store','Content-Security-Policy':"default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",'Referrer-Policy':'strict-origin-when-cross-origin'}});
}
