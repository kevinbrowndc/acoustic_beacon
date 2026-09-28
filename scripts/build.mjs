import {mkdir,cp} from 'node:fs/promises';
await mkdir('public',{recursive:true});
for(const file of ['index.html','thanks.html','contact.html','contact-success.html','privacy.html','terms.html','privacy','robots.txt','sitemap.xml','assets'])await cp(file,'public/'+file,{recursive:true});
console.log('Marketing site packaged; server-rendered directory uses the public read-only API.');
