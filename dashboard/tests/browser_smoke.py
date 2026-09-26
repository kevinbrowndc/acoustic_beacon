from pathlib import Path
from playwright.sync_api import sync_playwright, expect
import time
run=str(time.time_ns())
out=Path(__file__).resolve().parents[1]/'test-results'
out.mkdir(exist_ok=True)
with sync_playwright() as p:
    browser=p.chromium.launch()
    page=browser.new_page(viewport={'width':1440,'height':1000})
    errors=[]
    page.on('pageerror',lambda error: errors.append(str(error)))
    page.goto('http://127.0.0.1:8766/merchant/')
    page.get_by_role('button',name='Open merchant workspace').click()
    expect(page.locator('.sidebar')).to_be_visible()
    page.screenshot(path=str(out/'desktop.png'),full_page=True)
    for route in ['offers','campaigns','beacon','activity','account','missing']:
        page.goto('http://127.0.0.1:8766/merchant/#/'+route)
        expect(page.locator('main')).to_be_visible()
    page.goto('http://127.0.0.1:8766/merchant/#/offers')
    page.get_by_role('button',name='Create offer',exact=True).click()
    page.locator('[name=title]').fill('Browser verified sample offer '+run)
    page.locator('[name=description]').fill('A persisted offer created through the merchant dashboard.')
    page.locator('[name=terms]').fill('Development example. No redemption value.')
    page.locator('[name=active]').check()
    page.get_by_role('button',name='Save offer',exact=True).click()
    expect(page.get_by_text('Browser verified sample offer '+run,exact=True)).to_be_visible()
    page.reload()
    expect(page.get_by_text('Browser verified sample offer '+run,exact=True)).to_be_visible()
    page.goto('http://127.0.0.1:8766/merchant/#/campaigns')
    page.get_by_role('button',name='Create campaign',exact=True).click()
    page.locator('[name=name]').fill('Browser verified campaign '+run)
    page.locator('[name=offer_ids]').nth(0).check()
    page.locator('[name=offer_ids]').nth(1).check()
    page.get_by_role('button',name='Save campaign',exact=True).click()
    expect(page.get_by_text('Browser verified campaign '+run,exact=True)).to_be_visible()
    page.set_viewport_size({'width':390,'height':844})
    page.goto('http://127.0.0.1:8766/merchant/#/dashboard')
    page.screenshot(path=str(out/'mobile.png'),full_page=True)
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Mobile overflow'
    page.get_by_role('button',name='Toggle navigation').click()
    page.get_by_role('navigation').get_by_role('link',name='Offers').click()
    page.get_by_role('button',name='Create offer',exact=True).click()
    page.screenshot(path=str(out/'mobile-form.png'),full_page=True)
    assert page.locator('dialog').evaluate('(el)=>el.getBoundingClientRect().right <= innerWidth'), 'Dialog overflow'
    page.get_by_role('button',name='Cancel',exact=True).click()
    page.goto('http://127.0.0.1:8766/merchant/#/account')
    page.get_by_role('button',name='Sign out',exact=True).click()
    page.get_by_role('button',name='Explore manager workspace').click()
    page.goto('http://127.0.0.1:8766/merchant/#/offers')
    expect(page.get_by_role('heading',name='Network offers')).to_be_visible()
    assert page.get_by_role('button',name='Create offer',exact=True).count()==0
    assert not errors, errors
    browser.close()
print('Browser workflow passed: navigation, persistent offer/campaign creation, mobile layout, manager restrictions, no JS errors.')
