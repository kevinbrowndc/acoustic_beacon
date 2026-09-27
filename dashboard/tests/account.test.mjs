import test from 'node:test';
import assert from 'node:assert/strict';
import {signupForm,registrationPayload} from '../src/account.js';
test('merchant form offers required fields without role selection',()=>{
 const html=signupForm();for(const name of ['business_name','contact_name','email','password','confirm_password'])assert.ok(html.includes(`name="${name}"`));
 assert.ok(!html.includes('name="role"'));assert.ok(html.includes('minlength="15"'));
});
test('payload is allowlisted and validates password confirmation',()=>{
 const d=new FormData();for(const [k,v] of Object.entries({business_name:'Business',contact_name:'Name',email:'test@example.invalid',password:'a long test passphrase',confirm_password:'a long test passphrase',role:'manager'}))d.set(k,v);
 assert.ok(!('role' in registrationPayload(d)));
 d.set('confirm_password','mismatch');assert.throws(()=>registrationPayload(d),/match/);
 d.set('password','short');assert.throws(()=>registrationPayload(d),/15/);
});
