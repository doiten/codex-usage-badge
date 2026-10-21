'use strict';
const assert=require('node:assert/strict');
const {chromium}=require('playwright');
const {installUsageBadge,formatRateLimits}=require('../agent.cjs');
const fixture=`<!doctype html><meta charset="utf-8"><style>
*{box-sizing:border-box}body{margin:0;font:14px sans-serif}nav{position:fixed;inset:0 auto 0 0;width:52px;display:flex;flex-direction:column;align-items:center;padding:8px;gap:8px}
.items{flex:1;min-height:0;width:36px;display:flex;flex-direction:column;align-items:center;gap:10px;overflow:auto}.footer{display:flex;flex-direction:column;align-items:center;gap:8px;flex-shrink:0;width:36px}
button{width:32px;height:32px;flex:0 0 32px}input{margin:20px 70px}
</style><nav data-app-navigation-rail><div class="items"><button>Tasks</button><button>Apps</button></div><div class="footer"><button>Help</button><button>Profile</button></div></nav><input id="editor" value="synthetic fixture">`;
const weekly=formatRateLimits({rateLimits:{primary:{usedPercent:27,windowDurationMins:10080}}});
const dual=formatRateLimits({rateLimits:{planType:'unknown',primary:{usedPercent:6,windowDurationMins:300},secondary:{usedPercent:27,windowDurationMins:10080}}});
async function snapshot(page){return page.evaluate(()=>{
  const state=window.__codexUsageBadge.status(),badge=document.getElementById('codex-usage-badge'),rect=badge.getBoundingClientRect();
  const obstacles=[...badge.closest('nav').querySelectorAll('button,a,[role="button"],input,[tabindex]')].filter(e=>e!==badge&&!badge.contains(e)&&!e.contains(badge)).map(e=>e.getBoundingClientRect()).filter(r=>r.width>0&&r.height>0);
  return {...state,top:rect.top,bottom:rect.bottom,x:rect.left+rect.width/2,y:rect.top+rect.height/2,preference:localStorage.getItem('codex-usage-badge.position.v1'),clicks:window.fixtureClicks??0,overlap:obstacles.some(r=>r.left<rect.right&&r.right>rect.left&&r.top<rect.bottom&&r.bottom>rect.top)};
});}
async function install(page,value=weekly){await page.evaluate(installUsageBadge);await page.evaluate(v=>window.__codexUsageBadge.update(v),value);}
async function main(){
  const browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_EXECUTABLE_PATH||undefined});
  const context=await browser.newContext({viewport:{width:320,height:650}});
  await context.route('https://quota.fixture/**',route=>route.fulfill({contentType:'text/html',body:fixture}));
  try {
    const page=await context.newPage();await page.goto('https://quota.fixture/');await page.locator('#editor').focus();
    await page.evaluate(()=>{window.__codexProjectColors={fixture:true};window.__codexThreadTokens={fixture:true};});
    await install(page);
    assert.equal(await page.locator('#editor').evaluate(e=>e===document.activeElement),true);
    const badge=page.locator('#codex-usage-badge');
    await badge.evaluate(e=>e.addEventListener('click',()=>window.fixtureClicks=(window.fixtureClicks??0)+1));
    let s=await snapshot(page);assert.equal(s.placed,true);assert.equal(s.overlap,false);assert.equal(s.offsetY,0);
    const defaultTop=s.top;
    await page.mouse.move(s.x,s.y);await page.mouse.down();await page.mouse.move(s.x,s.y-2);await page.mouse.up();
    s=await snapshot(page);assert.equal(s.clicks,1);assert.equal(s.offsetY,0);
    await page.mouse.move(s.x,s.y);await page.mouse.down();await page.mouse.move(s.x,s.y-72,{steps:6});await page.mouse.up();
    s=await snapshot(page);assert.equal(s.offsetY,-72);assert.equal(s.clicks,1);assert.equal(JSON.parse(s.preference).offsetY,-72);assert.equal(s.overlap,false);
    await page.evaluate(()=>{window.fixtureBadge=window.__codexUsageBadge;});await page.evaluate(installUsageBadge);
    assert.equal(await page.evaluate(()=>window.fixtureBadge===window.__codexUsageBadge),true);
    await page.evaluate(()=>window.__codexUsageBadge.destroy());await install(page);
    s=await snapshot(page);assert.equal(s.offsetY,-72);assert.ok(Math.abs(s.top-(defaultTop-72))<1);
    assert.equal(await page.evaluate(()=>window.__codexProjectColors.fixture&&window.__codexThreadTokens.fixture),true);
    await page.evaluate(v=>window.__codexUsageBadge.update(v),dual);
    assert.equal(await badge.locator('.usage-ring:visible').count(),2);
    assert.deepEqual(await badge.locator('.usage-number:visible').allTextContents(),['94%','73%']);
    s=await snapshot(page);assert.equal(s.positionFits,true);assert.equal(s.overlap,false);assert.equal(s.offsetY,-72);
    const other=await context.newPage();await other.goto('https://quota.fixture/');await install(other,dual);
    assert.equal((await snapshot(other)).offsetY,-72);
    await badge.focus();await page.keyboard.press('ArrowUp');assert.equal((await snapshot(page)).offsetY,-76);
    await other.waitForFunction(()=>window.__codexUsageBadge.status().offsetY===-76);
    await page.keyboard.press('Shift+ArrowUp');assert.equal((await snapshot(page)).offsetY,-92);
    await page.keyboard.press('ArrowDown');assert.equal((await snapshot(page)).offsetY,-88);
    await page.keyboard.press('Home');assert.equal((await snapshot(page)).preference,null);
    await other.waitForFunction(()=>window.__codexUsageBadge.status().offsetY===0);
    await page.keyboard.press('ArrowUp');await badge.dblclick();
    assert.equal((await snapshot(page)).offsetY,0);assert.equal((await snapshot(page)).preference,null);
    s=await snapshot(page);
    await badge.dispatchEvent('pointerdown',{pointerId:7,button:0,isPrimary:true,clientY:s.y});
    await badge.dispatchEvent('pointermove',{pointerId:7,clientY:s.y-30});
    assert.equal((await snapshot(page)).dragging,true);
    await badge.dispatchEvent('pointercancel',{pointerId:7});
    s=await snapshot(page);assert.equal(s.dragging,false);assert.equal(s.offsetY,0);assert.equal(s.preference,null);
    await page.evaluate(()=>{
      const b=document.getElementById('codex-usage-badge'),r=b.getBoundingClientRect(),button=document.createElement('button');
      button.id='fixture-obstacle';button.style.cssText=`position:absolute;left:8px;top:${r.top+8}px;width:36px;height:24px;pointer-events:none`;
      b.closest('nav').appendChild(button);
    });
    await page.waitForFunction(()=>window.__codexUsageBadge.status().appliedOffsetY!==0);
    assert.equal((await snapshot(page)).overlap,false);
    await page.locator('#fixture-obstacle').evaluate(e=>e.style.height='40px');
    await page.waitForTimeout(200);assert.equal((await snapshot(page)).overlap,false);
    await page.locator('#fixture-obstacle').evaluate(e=>e.remove());
    await page.setViewportSize({width:320,height:120});
    await page.waitForFunction(()=>window.__codexUsageBadge.status().positionFits===false);
    assert.equal(await badge.isVisible(),false);
    await page.setViewportSize({width:320,height:650});
    await page.waitForFunction(()=>window.__codexUsageBadge.status().placed===true);
    assert.equal((await snapshot(page)).overlap,false);
    await page.evaluate(v=>window.__codexUsageBadge.update(v),weekly);
    assert.equal(await badge.locator('.usage-ring:visible').count(),1);
    await badge.hover();await page.waitForSelector('#codex-usage-tooltip:visible');
    assert.match(await page.locator('#codex-usage-tooltip').textContent(),/剩余73%/);
    assert.match(await page.locator('#codex-usage-tooltip').textContent(),/上下拖动调整位置/);
    await page.evaluate(()=>window.__codexUsageBadge.destroy());
    assert.equal(await page.locator('[id^="codex-usage-"]').count(),0);
    await other.close();
    const unavailable=await context.newPage();await unavailable.goto('https://quota.fixture/');
    await unavailable.evaluate(()=>{for(const method of ['getItem','setItem','removeItem'])Object.defineProperty(Storage.prototype,method,{value:()=>{throw Error('synthetic unavailable storage');}});});
    await install(unavailable);await unavailable.locator('#codex-usage-badge').focus();await unavailable.keyboard.press('ArrowUp');
    assert.equal(await unavailable.evaluate(()=>window.__codexUsageBadge.status().storageOK),false);
    assert.equal(await unavailable.evaluate(()=>window.__codexUsageBadge.status().placed),true);
    await unavailable.evaluate(()=>window.__codexUsageBadge.destroy());
    console.log('PASS quota dragging/clicks, saved position, reinjection, cross-window sync, keyboard/reset/cancel, period switches, native controls, short-window recovery, tooltip, storage failure and cleanup');
  } finally {await context.close();await browser.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
