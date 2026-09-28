import test from 'node:test';
import assert from 'node:assert/strict';
import {signupForm,registrationPayload} from '../src/account.js';
test('merchant form offers required fields without role selection',()=>{
 const html=signupForm();for(const name of ['business_name','contact_name','website','directory_opt_in','email','password','confirm_password'])assert.ok(html.includes(`name="${name}"`));
 assert.ok(!html.includes('name="role"'));assert.ok(html.includes('minlength="15"'));
});
test('payload is allowlisted and validates password confirmation',()=>{
 const d=new FormData();for(const [k,v] of Object.entries({business_name:'Business',contact_name:'Name',email:'test@example.invalid',password:'a long test passphrase',confirm_password:'a long test passphrase',role:'manager'}))d.set(k,v);
 assert.ok(!('role' in registrationPayload(d)));
 d.set('confirm_password','mismatch');assert.throws(()=>registrationPayload(d),/match/);
 d.set('password','short');assert.throws(()=>registrationPayload(d),/15/);
});

test('directory participation is opt-in, never implicit',()=>{
 const html=signupForm();assert.ok(!html.includes('type="checkbox" checked'));
 const d=new FormData();d.set('password','a long test passphrase');d.set('confirm_password','a long test passphrase');d.set('website','example.com');
 assert.equal(registrationPayload(d).directory_opt_in,false);assert.equal(registrationPayload(d).website,'example.com');
 d.set('directory_opt_in','on');assert.equal(registrationPayload(d).directory_opt_in,true);
});
