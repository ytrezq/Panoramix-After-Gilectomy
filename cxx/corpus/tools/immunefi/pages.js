// Load each program's information and scope pages in headless Chromium and
// save their HTML (the RSC payload holds the assets in scope).
const { chromium } = require('/opt/npm-tools/node_modules/playwright');
const fs = require('fs');
const [listFile, outDir] = process.argv.slice(2);
const slugs = JSON.parse(fs.readFileSync(listFile)).map(b => b.slug);
(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome',
    args: ['--no-sandbox'], proxy: process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY } : undefined });
  const ctx = await browser.newContext({ viewport: { width: 1400, height: 1000 } });
  const page = await ctx.newPage();
  for (const slug of slugs) {
    for (const tab of ['information', 'scope']) {
      const f = `${outDir}/${slug}_${tab}.html`;
      if (fs.existsSync(f)) continue;
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          await page.goto(`https://immunefi.com/bug-bounty/${slug}/${tab}/`, { waitUntil: 'networkidle', timeout: 90000 });
          await page.waitForTimeout(500);
          fs.writeFileSync(f, await page.content());
          break;
        } catch (e) { console.error(slug, tab, attempt, String(e).slice(0, 120)); await page.waitForTimeout(3000); }
      }
    }
    process.stdout.write('.');
  }
  console.log('\ndone');
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
