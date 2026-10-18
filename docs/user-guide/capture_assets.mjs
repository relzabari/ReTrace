import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const sharp = require('sharp');

const root = path.resolve(process.cwd());
const output = path.join(root, 'docs', 'user-guide', 'assets');
await fs.mkdir(output, { recursive: true });

const json = (body) => ({ status: 200, contentType: 'application/json', body: JSON.stringify(body) });
const start = Date.parse('2026-10-18T08:00:00Z');
const participants = [
  { id:'p1', displayName:'נועה לוי', callsign:'צוות 1', role:'כיתת כוננות', pointCount:84, userId:'u2' },
  { id:'p2', displayName:'יואב כהן', callsign:'צוות 2', role:'כיתת כוננות', pointCount:76, userId:'u3' },
  { id:'p3', displayName:'מיכל ישראלי', callsign:'חמ״ל', role:'חמל', pointCount:45, userId:'u4' },
];
const makePoints = (participant, offsetLat, offsetLon) => ({
  participantId:participant.id,
  displayName:participant.displayName,
  count:36,
  points:Array.from({length:36}, (_, index) => ({
    capturedAt:new Date(start + index * 15000).toISOString(),
    latitude:31.952 + offsetLat + Math.sin(index / 5) * .0012 + index * .00013,
    longitude:35.125 + offsetLon + Math.cos(index / 6) * .0014 + index * .00016,
  }))
});
const tracks = {
  p1:makePoints(participants[0], 0, 0),
  p2:makePoints(participants[1], .0025, -.0018),
  p3:makePoints(participants[2], -.002, .0022),
};
const events = [{
  id:'ev1', occurredAt:new Date(start + 270000).toISOString(), latitude:31.9562, longitude:35.129,
  reporterName:'מיכל ישראלי', reporterRole:'חמל', description:'חסימת ציר זמנית'
}];

function responseFor(url, method) {
  const pathname = new URL(url).pathname;
  if (pathname.endsWith('/auth/me')) return json({id:'u1', email:'admin@example.org', role:'ADMIN'});
  if (pathname.endsWith('/exercises') && method === 'GET') return json({items:[{id:'ex1', name:'תרגיל מוכנות יישובי', status:'ACTIVE', createdAt:new Date(start - 3600000).toISOString()}]});
  if (pathname.endsWith('/exercises/ex1/map-bootstrap')) return json({exercise:{id:'ex1', name:'תרגיל מוכנות יישובי', status:'ACTIVE', createdAt:new Date(start - 3600000).toISOString()}, participants});
  if (pathname.endsWith('/exercises/ex1/events')) return json({items:events});
  if (pathname.includes('/exercises/ex1/tracks/')) return json(tracks[pathname.split('/').pop()] ?? tracks.p1);
  if (pathname.endsWith('/exercises/ex1/access')) return json({items:[
    {id:'u1', email:'admin@example.org', role:'ADMIN'},
    {id:'u5', email:'manager@example.org', role:'MANAGER'},
  ]});
  if (pathname.endsWith('/users')) return json({items:[
    {id:'u1', email:'admin@example.org', role:'ADMIN'},
    {id:'u5', email:'manager@example.org', role:'MANAGER'},
    {id:'u2', email:'user@example.org', role:'USER'},
  ]});
  if (pathname.endsWith('/exercises/ex1/live')) return json({participants:participants.map((p, i) => ({...p, latestPoint:tracks[p.id].points.at(-1)})), events});
  return {status:404, contentType:'application/json', body:JSON.stringify({detail:'Not found'})};
}

const server = http.createServer(async (request, response) => {
  const pathname = new URL(request.url, 'http://127.0.0.1').pathname;
  if (pathname === '/' || pathname === '/index.html') {
    response.writeHead(200, {'content-type':'text/html; charset=utf-8'});
    response.end(await fs.readFile(path.join(root, 'backend', 'app', 'static', 'index.html')));
    return;
  }
  response.writeHead(404);
  response.end('Not found');
});
await new Promise(resolve => server.listen(8791, '127.0.0.1', resolve));

const browser = await chromium.launch({headless:true, executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'});
try {
  const context = await browser.newContext({viewport:{width:1600, height:1050}, deviceScaleFactor:1});
  await context.addInitScript(() => {
    localStorage.setItem('retraceAccessToken', 'guide-demo-token');
    localStorage.setItem('retraceRefreshToken', 'guide-demo-refresh');
  });
  const page = await context.newPage();
  await page.route('**/api/v1/**', async route => {
    const result = responseFor(route.request().url(), route.request().method());
    await route.fulfill(result);
  });
  await page.goto('http://127.0.0.1:8791/', {waitUntil:'networkidle'});
  await page.selectOption('#exerciseSelect', 'ex1');
  await page.waitForFunction(() => document.querySelectorAll('#participants input[type=checkbox]').length === 3);
  const boxes = await page.$$('#participants input[type=checkbox]');
  await boxes[0].check();
  await boxes[1].check();
  await page.waitForTimeout(1800);
  await page.check('#participantNamesEnabled');
  await page.screenshot({path:path.join(output, 'web-dashboard.png'), fullPage:false});

  await page.click('#exportVideoButton');
  await page.waitForTimeout(300);
  await page.screenshot({path:path.join(output, 'web-export-dialog.png'), fullPage:false});
  await page.click('#cancelVideoExportButton');

  await page.evaluate(() => {
    liveViewActive = true;
    updateLiveActionButtons();
    openWebEventDialog();
  });
  await page.waitForTimeout(900);
  await page.screenshot({path:path.join(output, 'web-event-dialog.png'), fullPage:false});
  await page.keyboard.press('Escape');

  const loginContext = await browser.newContext({viewport:{width:1200, height:800}, deviceScaleFactor:1});
  const login = await loginContext.newPage();
  await login.goto('http://127.0.0.1:8791/', {waitUntil:'networkidle'});
  await login.screenshot({path:path.join(output, 'web-login.png'), fullPage:false});
  await loginContext.close();
} finally {
  await browser.close();
  server.close();
}

async function annotate(source, target, circles) {
  const meta = await sharp(source).metadata();
  const svg = `<svg width="${meta.width}" height="${meta.height}" xmlns="http://www.w3.org/2000/svg">
    ${circles.map(({cx,cy,rx,ry}) => `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="none" stroke="#e11d48" stroke-width="10"/>`).join('')}
  </svg>`;
  await sharp(source).composite([{input:Buffer.from(svg)}]).png().toFile(target);
}

await annotate(path.join(root,'design-mockups','01-setup-screen-redesign.png'), path.join(output,'mobile-setup-create.png'), [
  {cx:610,cy:1160,rx:285,ry:70},
]);
await annotate(path.join(root,'design-mockups','01-setup-screen-redesign.png'), path.join(output,'mobile-setup-join.png'), [
  {cx:610,cy:1570,rx:290,ry:72},
]);
await annotate(path.join(root,'design-mockups','02-tracking-screen-redesign.png'), path.join(output,'mobile-tracking-stop.png'), [
  {cx:210,cy:443,rx:175,ry:78},
]);
await annotate(path.join(root,'design-mockups','02-tracking-screen-redesign.png'), path.join(output,'mobile-event-report.png'), [
  {cx:480,cy:1378,rx:430,ry:62},
]);
await annotate(path.join(output,'web-dashboard.png'), path.join(output,'web-dashboard-export.png'), [
  {cx:458,cy:36,rx:53,ry:28},
]);
await annotate(path.join(output,'web-dashboard.png'), path.join(output,'web-dashboard-playback.png'), [
  {cx:1160,cy:1006,rx:165,ry:32},
]);
await annotate(path.join(output,'web-export-dialog.png'), path.join(output,'web-export-create.png'), [
  {cx:1082,cy:758,rx:48,ry:30},
]);
await annotate(path.join(output,'web-login.png'), path.join(output,'web-login-action.png'), [
  {cx:600,cy:491,rx:195,ry:29},
]);
await annotate(path.join(output,'web-event-dialog.png'), path.join(output,'web-event-save.png'), [
  {cx:1075,cy:843,rx:55,ry:30},
]);

console.log(output);
