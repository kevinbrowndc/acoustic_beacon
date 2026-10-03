import sys,secrets
from pathlib import Path
sys.path.insert(0,str(Path('backend').resolve()))
from alembic import command
from alembic.config import Config
from sqlalchemy.orm import Session
from fastapi.testclient import TestClient
from playwright.sync_api import sync_playwright,expect
from app.config import Settings
from app.database import make_engine
from app.bootstrap_manager import provision
from app.main import create_app
Path('dashboard/test-results').mkdir(exist_ok=True)
url='sqlite:///'+str(Path('dashboard/test-results/auth-browser-'+secrets.token_hex(5)+'.db').resolve()).replace('\\','/')
config=Config('backend/alembic.ini');config.attributes['database_url']=url;command.upgrade(config,'head')
engine=make_engine(url);password=secrets.token_urlsafe(24)
origin='https://merchant.acousticbeacon.com'
settings=Settings(environment='production',database_url='postgresql://fake:fake@localhost/fake',_env_file=None)
with TestClient(create_app(settings,engine),base_url=origin) as api,sync_playwright() as p:
 b=p.chromium.launch();context=b.new_context();page=context.new_page();errors=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 def proxy(route):
  req=route.request
  r=api.request(req.method,req.url,headers=req.headers,content=req.post_data_buffer)
  route.fulfill(status=r.status_code,headers=dict(r.headers),body=r.content)
 page.route('**/*',proxy)
 page.goto(origin+'/merchant/')
 page.get_by_role('link',name='Create Merchant Account',exact=True).click()
 expect(page.locator('[name=business_name]')).to_be_visible()
 page.locator('[name=business_name]').fill('Browser registered business')
 page.locator('[name=contact_name]').fill('Browser contact')
 page.locator('[name=email]').fill('browser-merchant@example.invalid')
 page.locator('[name=password]').fill(password);page.locator('[name=confirm_password]').fill(password)
 page.get_by_role('button',name='Create Merchant Account',exact=True).click()
 expect(page.get_by_text('Production workspace',exact=True)).to_be_visible()
 page.reload();expect(page.get_by_text('Production workspace',exact=True)).to_be_visible()
 expect(page.locator('.refreshing')).to_have_count(0)
 page.goto(origin+'/merchant/#/beacon')
 expect(page.locator('audio')).to_be_visible()
 page.locator('audio').evaluate('(a)=>{a.muted=true;window.originalAudio=a;window.wraps=0;let last=0;a.addEventListener("timeupdate",()=>{if(last>5 && a.currentTime<1)window.wraps++;last=a.currentTime;});}')
 page.get_by_role('button',name='Start continuous broadcast',exact=True).click()
 expect(page.locator('[data-broadcast-status]')).to_contain_text('Broadcasting continuously')
 page.wait_for_function('window.wraps>=1',timeout=15000)
 assert page.locator('audio').evaluate('(a)=>a.loop && !a.paused')
 # A normal save refresh must retain the same live player, not restart/stop it.
 page.get_by_role('button',name='Save assignment',exact=True).click()
 expect(page.locator('.refreshing')).to_have_count(0)
 expect(page.locator('.toast')).to_contain_text('Beacon assignment updated.')
 assert page.evaluate('document.querySelector("audio")===window.originalAudio')
 assert page.locator('audio').evaluate('(a)=>a.loop && !a.paused')
 page.get_by_role('button',name='Stop continuous broadcast',exact=True).click()
 assert page.locator('audio').evaluate('(a)=>a.paused && !a.loop')
 for width in [390,320]:
  page.set_viewport_size({'width':width,'height':844})
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
 page.set_viewport_size({'width':1280,'height':900})
 page.get_by_role('button',name='Start continuous broadcast',exact=True).click()
 page.goto(origin+'/merchant/#/offers')
 assert page.evaluate('window.originalAudio.paused && !window.originalAudio.loop')
 page.goto(origin+'/merchant/#/account');expect(page.get_by_text('browser-merchant@example.invalid')).to_be_visible()
 expect(page.get_by_text('Secure account session',exact=True)).to_be_visible()
 page.get_by_role('button',name='Sign out',exact=True).click();expect(page.locator('[name=email]')).to_be_visible()
 assert api.get('/api/v1/dashboard/workspace').status_code==401
 page.get_by_role('link',name='Create Merchant Account',exact=True).click()
 page.set_viewport_size({'width':390,'height':844});assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
 page.screenshot(path='dashboard/test-results/production-signup.png',full_page=True)
 assert not errors,errors
 b.close()
engine.dispose()
print('Continuous browser loop, preserved player across save, stop, navigation stop, mobile and sign-out PASS')
