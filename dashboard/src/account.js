export function signupForm(loading=false) {
 return `<h1>Create your<br>Merchant account.</h1><p>Your business. Your offers. Your own workspace.</p><form data-form="production-signup"><label>Business name<input name="business_name" autocomplete="organization" required maxlength="200"></label><label>Contact name<input name="contact_name" autocomplete="name" required maxlength="200"></label><label>Email<input name="email" type="email" autocomplete="username" required maxlength="320"></label><label>Password<input name="password" type="password" autocomplete="new-password" required minlength="15" maxlength="256"></label><small>Use at least 15 characters.</small><label>Confirm password<input name="confirm_password" type="password" autocomplete="new-password" required minlength="15" maxlength="256"></label><p class="form-error" role="alert"></p><button class="button wide" type="submit" ${loading?'disabled':''}>Create Merchant Account</button></form><p class="small">Already have an account? <a href="/merchant/">Sign In</a></p>`;
}
export function registrationPayload(form) {
 const password=form.get('password'),confirm=form.get('confirm_password');
 if(password.length<15)throw Error('Use a password of at least 15 characters.');
 if(password!==confirm)throw Error('Passwords must match.');
 return {business_name:form.get('business_name'),contact_name:form.get('contact_name'),email:form.get('email'),password,confirm_password:confirm};
}
