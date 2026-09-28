const menuButton=document.querySelector('.menu-toggle');
const menu=document.querySelector('#primary-navigation');
if(menuButton&&menu){
 const close=(focus=false)=>{menuButton.setAttribute('aria-expanded','false');menu.removeAttribute('data-open');if(focus)menuButton.focus();};
 menuButton.addEventListener('click',()=>{const open=menuButton.getAttribute('aria-expanded')!=='true';menuButton.setAttribute('aria-expanded',String(open));menu.toggleAttribute('data-open',open);});
 menu.addEventListener('click',event=>{if(event.target.closest('a'))close();});
 document.addEventListener('keydown',event=>{if(event.key==='Escape'&&menuButton.getAttribute('aria-expanded')==='true')close(true);});
 matchMedia('(min-width:760px)').addEventListener('change',()=>close());
}
