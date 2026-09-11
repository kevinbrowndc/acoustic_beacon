
const $ = (s) => document.querySelector(s);
document.querySelectorAll('[data-modal]').forEach(a=>{
  a.addEventListener('click',e=>{
    e.preventDefault();
    const id=a.getAttribute('data-modal');
    document.getElementById(id)?.classList.add('open');
  });
});
document.querySelectorAll('.modal').forEach(m=>{
  m.addEventListener('click',e=>{
    if(e.target===m || e.target.closest('[data-close]')) m.classList.remove('open');
  });
});
document.addEventListener('keydown',e=>{
  if(e.key==='Escape') document.querySelectorAll('.modal.open').forEach(m=>m.classList.remove('open'));
});
