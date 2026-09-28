import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {renderDirectory} from '../lib/directory.mjs';import handler from '../netlify/functions/businesses.mjs';
test('semantic crawlable safe directory links, no private fields',()=>{
 const html=renderDirectory([{business_name:'Joe <Pizza>',website:'https://example.com/',email:'private@example.com'}]);
 assert.ok(html.includes('Joe &lt;Pizza&gt;'));assert.ok(html.includes('href="https://example.com/"'));assert.ok(!html.includes('private@example.com'));
 assert.ok(!renderDirectory([{business_name:'Unsafe',website:'javascript:alert(1)'}]).includes('javascript:'));
 assert.ok(renderDirectory([]).includes('just getting started'));
});
test('server function renders production projection without forwarding credentials',async()=>{
 const original=globalThis.fetch;globalThis.fetch=async(url,options)=>{assert.equal(url,'https://merchant.acousticbeacon.com/api/v1/businesses');assert.ok(!options.headers.Cookie);return Response.json([{business_name:'Merchant',website:'https://merchant.example/'}]);};
 try{const r=await handler(new Request('https://acousticbeacon.com/businesses'));assert.equal(r.status,200);assert.match(await r.text(),/Merchant/);assert.equal(r.headers.get('cache-control'),'no-store');}finally{globalThis.fetch=original;}
});
test('outage is honest and uncached',async()=>{const original=globalThis.fetch;globalThis.fetch=async()=>{throw Error('offline')};try{const r=await handler(new Request('https://acousticbeacon.com/businesses'));assert.equal(r.status,503);assert.match(await r.text(),/temporarily unavailable/);}finally{globalThis.fetch=original;}});
test('home navigation and sitemap expose businesses with mobile controls',async()=>{
 const html=await readFile('index.html','utf8');for(const label of ['Businesses','Demo','About','Contact'])assert.ok(html.includes('>'+label+'</a>'));
 assert.ok(html.includes('aria-controls="primary-navigation"'));assert.ok(html.includes('href="/businesses"'));assert.match(await readFile('sitemap.xml','utf8'),/https:\/\/acousticbeacon.com\/businesses/);
});
