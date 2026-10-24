// Local preview validation against a fresh headless Chrome profile. No TV traffic.
// Requires playwright-core in /private/tmp/tv-remote-design-qa (QA only).
// Usage: node design-qa.cjs file:///.../rendered.html [output-directory]
const { chromium } = require('/private/tmp/tv-remote-design-qa/node_modules/playwright-core');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
  const browser = await chromium.launch({
    executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless:true
  });
  const directory = path.resolve(process.argv[3] || '/private/tmp/tv-remote-design-qa/multi-room-results');
  fs.mkdirSync(directory,{recursive:true});
  const results = [];
  try {
    for (const width of [320,390,736]) {
      for (const scheme of ['light','dark']) {
        const context = await browser.newContext({viewport:{width,height:1600},colorScheme:scheme});
        const page = await context.newPage();
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        await page.goto(process.argv[2], {waitUntil:'load'});
        const frame = page.frameLocator('iframe');
        const root = frame.locator('#tv-remote-design');
        const samsung = root.locator('[data-select-samsung]');
        const apple = root.locator('[data-select-apple]');
        const room = root.locator('[data-select-room]');
        const feedback = root.locator('.remote-feedback');
        const checks = [];
        const record = name => checks.push(name);
        const noOverflow = async () => {
          const geometry = await root.evaluate(element => ({
            rootWidth:element.getBoundingClientRect().width,
            documentWidth:element.ownerDocument.documentElement.clientWidth,
            scrollWidth:element.ownerDocument.documentElement.scrollWidth,
            controls:[...element.querySelectorAll('button,select,input,textarea')].filter(control=>control.getClientRects().length).map(control=>({
              label:control.getAttribute('aria-label')||control.textContent.trim(),
              width:control.getBoundingClientRect().width,
              height:control.getBoundingClientRect().height
            }))
          }));
          assert.ok(geometry.scrollWidth <= geometry.documentWidth, 'horizontal overflow');
          return geometry;
        };

        assert.equal(await samsung.locator('option').count(),4);
        assert.equal(await apple.locator('option').count(),4);
        assert.equal(await room.locator('option').count(),3);
        await root.locator('[data-command="Up"]').click();
        assert.match(await feedback.innerText(), /Living Room Apple TV \(Living Room\): Up/);
        await root.locator('[data-target="samsung"]').click();
        assert.equal(await root.locator('[data-open="keyboard"]').isDisabled(), true);
        await root.locator('[data-command="Back"]').click();
        assert.match(await feedback.innerText(), /Samsung S95BD \(Living Room\): Back/);
        await root.locator('[data-volume="Mute"]').click();
        assert.match(await feedback.innerText(), /Samsung S95BD \(Living Room\): Toggle mute/);
        await root.locator('[data-open="apps"]').click();
        assert.equal(await root.locator('[data-sheet="inputs"]').isVisible(),true);
        await root.locator('[data-close]').click();
        await root.locator('[data-target="apple"]').click();
        await root.locator('[data-open="keyboard"]').click();
        await root.locator('#remote-text').fill('Example search');
        await root.locator('[data-send-text]').click();
        assert.match(await feedback.innerText(), /Living Room Apple TV \(Living Room\): Text entry simulated/);
        assert.equal(await root.locator('#remote-text').inputValue(),'');
        record('independent command routing and keyboard');

        await room.selectOption('bedroom');
        assert.equal(await samsung.inputValue(),'s-bedroom');
        assert.equal(await apple.inputValue(),'a-bedroom');
        assert.equal(await root.locator('[data-room-title]').innerText(),'Bedroom');
        await root.locator('[data-command="Up"]').click();
        assert.match(await feedback.innerText(), /Bedroom Apple TV \(Bedroom\): Up/);
        await samsung.selectOption('s-living');
        assert.equal(await apple.inputValue(),'a-bedroom');
        assert.match(await root.locator('[data-room-title]').innerText(), /Bedroom · Custom/);
        await root.locator('[data-volume="Volume up"]').click();
        assert.match(await feedback.innerText(), /Samsung S95BD \(Living Room\): Volume up/);
        await root.locator('[data-command="Home"]').click();
        assert.match(await feedback.innerText(), /Bedroom Apple TV \(Bedroom\): Home/);
        await room.selectOption('living');
        await room.selectOption('bedroom');
        assert.equal(await samsung.inputValue(),'s-bedroom','temporary selection changed saved room');
        assert.equal(await apple.inputValue(),'a-bedroom');
        record('room default pairs and temporary overrides');

        await samsung.selectOption('s-living');
        await root.locator('[data-open="manageRooms"]').click();
        assert.equal(await root.locator('[data-assignment-room]').inputValue(),'bedroom');
        assert.equal(await root.locator('[data-assignment-samsung]').innerText(),'Samsung S95BD');
        assert.equal(await root.locator('[data-assignment-apple]').innerText(),'Bedroom Apple TV');
        await noOverflow();
        await root.screenshot({path:path.join(directory,`room-assignment-${width}-${scheme}.png`)});
        await root.locator('[data-save-room]').click();
        assert.equal(await root.locator('[data-room-title]').innerText(),'Bedroom');
        assert.match(await feedback.innerText(), /Bedroom · Room assignment saved/);
        await room.selectOption('living');
        await room.selectOption('bedroom');
        assert.equal(await samsung.inputValue(),'s-living','explicit room save did not persist');
        assert.equal(await apple.inputValue(),'a-bedroom');
        record('explicit room assignment saving');

        await room.selectOption('office');
        assert.equal(await samsung.inputValue(),'s-office');
        assert.equal(await apple.inputValue(),'');
        assert.equal(await root.locator('[data-command="Up"]').isDisabled(),true);
        assert.equal(await root.locator('[data-volume="Volume up"]').isDisabled(),true);
        await root.locator('[data-target="samsung"]').click();
        assert.equal(await samsung.inputValue(),'s-office');
        assert.equal(await root.locator('[data-command="Up"]').isDisabled(),true);
        assert.match(await root.locator('[data-connection]').innerText(), /Office Samsung offline/);
        await apple.selectOption('a-office');
        await root.locator('[data-target="apple"]').click();
        await root.locator('[data-command="Up"]').click();
        assert.match(await feedback.innerText(), /Office Apple TV \(Office\): Up/);
        assert.equal(await samsung.inputValue(),'s-office','offline Samsung substituted another TV');
        assert.equal(await root.locator('[data-volume="Volume up"]').isDisabled(),true);
        await root.locator('[data-open="keyboard"]').click();
        assert.equal(await root.locator('[data-keyboard-unavailable]').isVisible(),true);
        assert.equal(await root.locator('#remote-text').isVisible(),false);
        await root.locator('[data-close]').click();
        record('single-kind rooms, offline preservation, per-device capabilities');

        await room.selectOption('living');
        await root.locator('[data-open="pairing"]').first().click();
        await root.locator('.remote-pin-form button').click();
        assert.match(await root.locator('#remote-pair-error').innerText(), /four-digit/);
        await root.locator('#remote-pin').fill('1234');
        await apple.selectOption('a-bedroom');
        assert.equal(await root.locator('[data-screen="control"]').isVisible(),true);
        assert.equal(await root.locator('#remote-pin').inputValue(),'');
        assert.match(await feedback.innerText(), /Bedroom Apple TV \(Bedroom\) selected/);
        await room.selectOption('living');
        await root.locator('[data-open="pairing"]').first().click();
        await root.locator('#remote-pin').fill('1234');
        await root.locator('.remote-pin-form button').click();
        assert.equal(await root.locator('[data-pair="samsung"]').isVisible(),true);
        assert.equal(await root.locator('#remote-pin').inputValue(),'');
        await root.locator('[data-allow]').click();
        await root.locator('[data-finish]').click();
        record('pairing and pending pairing cancellation on selection');

        await root.locator('[data-open="devices"]').first().click();
        await noOverflow();
        await root.screenshot({path:path.join(directory,`devices-${width}-${scheme}.png`)});
        await root.locator('[data-partial]').click();
        assert.equal(await samsung.inputValue(),'s-living');
        assert.equal(await root.locator('[data-volume="Volume up"]').isDisabled(),true);
        await root.locator('[data-command="Up"]').click();
        assert.match(await feedback.innerText(), /Living Room Apple TV \(Living Room\): Up/);
        await root.locator('[data-open="devices"]').first().click();
        await root.locator('[data-partial]').click();
        assert.equal(await root.locator('[data-volume="Volume up"]').isDisabled(),false);
        await root.locator('[data-open="devices"]').first().click();
        await root.locator('[data-keyboard-focus]').click();
        assert.equal(await root.locator('[data-keyboard-unavailable]').isVisible(),true);
        await root.locator('[data-close]').click();
        await root.locator('[data-open="devices"]').first().click();
        await root.locator('[data-keyboard-focus]').click();
        assert.equal(await root.locator('#remote-text').isVisible(),true);
        await root.locator('[data-close]').click();
        await root.locator('[data-open="devices"]').first().click();
        await root.locator('[data-simulate-offline]').click();
        assert.equal(await root.locator('[data-screen="offline"]').isVisible(),true);
        await room.selectOption('bedroom');
        assert.equal(await root.locator('[data-screen="offline"]').isVisible(),true);
        await root.locator('[data-reconnect]').click();
        record('partial device outage and Wi-Fi outage');

        await room.selectOption('living');
        await root.locator('[data-toggle-pad]').click();
        const pad = root.locator('.remote-touchpad');
        assert.equal(await pad.isVisible(),true);
        await pad.click();
        assert.match(await feedback.innerText(), /Living Room Apple TV \(Living Room\): Select/);
        const padBounds=await pad.boundingBox();
        await page.mouse.move(padBounds.x+padBounds.width/2,padBounds.y+padBounds.height/2);
        await page.mouse.down();
        await apple.selectOption('a-bedroom');
        const selectedFeedback=await feedback.innerText();
        await page.mouse.move(padBounds.x+padBounds.width/2+50,padBounds.y+padBounds.height/2);
        await page.mouse.up();
        assert.equal(await feedback.innerText(),selectedFeedback,'old gesture sent to a new Apple TV');
        await pad.click();
        assert.match(await feedback.innerText(), /Bedroom Apple TV \(Bedroom\): Select/);
        record('touchpad gesture cancellation and new-device routing');

        await room.selectOption('living');
        await root.locator('[data-toggle-pad]').click();
        const geometry = await noOverflow();
        assert.equal(errors.length,0,errors.join('\n'));
        await root.screenshot({path:path.join(directory,`remote-${width}-${scheme}.png`)});
        results.push({width,scheme,checks,javascriptErrors:errors,geometry});
        await context.close();
      }
    }
    fs.writeFileSync(path.join(directory,'results.json'),JSON.stringify(results,null,2));
    console.log(JSON.stringify(results.map(({width,scheme,checks,javascriptErrors,geometry})=>({width,scheme,checks,javascriptErrors,overflow:geometry.scrollWidth>geometry.documentWidth})),null,2));
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
