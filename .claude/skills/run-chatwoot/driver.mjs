// Logs into the running Chatwoot dev stack and screenshots a page.
// Runs inside mcr.microsoft.com/playwright (see drive.sh). Env:
//   BASE_URL  default http://localhost:3000
//   PAGE      path to open after login, default /app/accounts/1/dashboard
//   OUT       screenshot path, default /out/shot.png
//   EMAIL / PASSWORD  default seeded john@acme.inc / Password1!
import { chromium } from 'playwright';

const base = process.env.BASE_URL || 'http://localhost:3000';
const page = process.env.PAGE || '/app/accounts/1/dashboard';
const out = process.env.OUT || '/out/shot.png';

const browser = await chromium.launch();
const p = await browser.newPage({ viewport: { width: 1400, height: 900 } });
const errors = [];
p.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
p.on('console', m => m.type() === 'error' && errors.push(`console: ${m.text()}`));

// First load after a stack restart is slow: Vite transforms ~hundreds of modules on demand.
await p.goto(`${base}/app/login`, { waitUntil: 'networkidle', timeout: 240000 });
await p.fill('input[name="email_address"]', process.env.EMAIL || 'john@acme.inc');
await p.fill('input[type="password"]', process.env.PASSWORD || 'Password1!');
await p.click('button[type="submit"]');
await p.waitForURL(/\/app\/accounts\/\d+\//, { timeout: 120000 });

if (!p.url().endsWith(page)) await p.goto(`${base}${page}`, { waitUntil: 'networkidle', timeout: 120000 });
// Lists show "Loading ..." placeholders until their API calls return; slow on a cold stack.
await p.waitForFunction(() => !/Loading/.test(document.body.innerText), null, { timeout: 120000 });
await p.waitForTimeout(1000);
await p.screenshot({ path: out });
console.log(JSON.stringify({ url: p.url(), screenshot: out, errors }, null, 2));
await browser.close();
