// Load Immunefi's bug-bounty list in headless Chromium, scroll to the end,
// save the rendered HTML, the links to program pages and any embedded JSON.
const { chromium } = require('/opt/npm-tools/node_modules/playwright');
const fs = require('fs');
const out = process.argv[2];
(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome',
    args: ['--no-sandbox'], proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined });
  const ctx = await browser.newContext({ ignoreHTTPSErrors: false, userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36' });
  const page = await ctx.newPage();
  const responses = [];
  page.on('response', async r => {
    const u = r.url();
    if (/json|graphql|api/i.test(r.headers()['content-type'] || '') || /\/api\//.test(u)) {
      try { const b = await r.text(); if (b.length > 2000) responses.push({ url: u, len: b.length, body: b }); } catch (e) {}
    }
  });
  await page.goto('https://immunefi.com/bug-bounty/', { waitUntil: 'networkidle', timeout: 120000 });
  let last = 0;
  for (let i = 0; i < 60; i++) {
    await page.mouse.wheel(0, 20000);
    await page.waitForTimeout(800);
    const n = await page.$$eval('a[href*="/bug-bounty/"]', as => as.length);
    if (n === last && i > 5) break;
    last = n;
  }
  const links = await page.$$eval('a[href*="/bug-bounty/"]', as => as.map(a => ({ href: a.href, text: a.innerText.trim().slice(0, 200) })));
  fs.writeFileSync(out + '/list_links.json', JSON.stringify(links, null, 1));
  fs.writeFileSync(out + '/list_page.html', await page.content());
  fs.writeFileSync(out + '/list_api.json', JSON.stringify(responses.map(r => ({ url: r.url, len: r.len })), null, 1));
  responses.forEach((r, i) => fs.writeFileSync(out + '/api_' + i + '.json', r.body));
  console.log('links', links.length, 'api responses', responses.length);
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
