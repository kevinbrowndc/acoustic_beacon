const form=document.querySelector('#contact-form');
if(form){
 let pending=false, sent=false;
 const button=form.querySelector('[type="submit"]');
 const status=document.querySelector('#contact-status');
 form.addEventListener('submit',async event=>{
  event.preventDefault();
  if(pending||sent)return;
  for(const field of form.querySelectorAll('input:not([type="hidden"]),textarea'))field.value=field.value.trim();
  if(!form.reportValidity())return;
  pending=true;button.disabled=true;button.textContent='Sending…';form.setAttribute('aria-busy','true');status.textContent='';
  const body=new URLSearchParams(new FormData(form)).toString();
  try{
   const response=await fetch('/',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body,signal:AbortSignal.timeout(20000)});
   if(!response.ok)throw new Error('Submission failed');
   sent=true;form.hidden=true;
   const success=document.querySelector('#contact-success');success.hidden=false;success.focus();
  }catch{
   status.textContent='We could not confirm your submission. Your message is still here. Please check your connection and try again in a moment.';status.focus();
  }finally{
   pending=false;form.removeAttribute('aria-busy');button.disabled=sent;button.textContent=sent?'Message sent':'Send Message';
  }
 });
}
