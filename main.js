// Mockfy desktop: a window on mockfy.uz with what a browser tab cannot give (its own icon and window,
// no tabs or address bar, no spellcheck in tests). The window has our own slim title bar (titlebar.html,
// in the page's own colours, like Telegram's); the site is shown under it in a WebContentsView.
// Sign-in goes through the computer's browser (Google blocks it inside apps): the site sends the app a
// one-time code on mockfy://auth?code=...
const { app, BrowserWindow, WebContentsView, shell, session, Menu, nativeTheme, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');

const APP_URL = (process.env.MOCKFY_URL || 'https://mockfy.uz').replace(/\/$/, '');
const ORIGIN = new URL(APP_URL).origin;
const PROTOCOL = 'mockfy';
const BAR = 38;                                   // title bar height
const MAC = process.platform === 'darwin';
let win = null;
let view = null;
let pendingLink = process.argv.find((a) => a.startsWith(`${PROTOCOL}://`)) || null;

// a separate profile for trying a build while the installed app is open: MOCKFY_PROFILE=test
if (process.env.MOCKFY_PROFILE) app.setPath('userData', path.join(app.getPath('appData'), `Mockfy-${process.env.MOCKFY_PROFILE}`));

// ---- one window, and mockfy:// links reach it -------------------------------------------
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', (_e, argv) => {
    const link = argv.find((a) => a.startsWith(`${PROTOCOL}://`));
    if (link) openLink(link);
    if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
  });
}
app.on('open-url', (e, url) => { e.preventDefault(); openLink(url); });       // macOS
if (process.defaultApp && process.argv.length >= 2) {
  app.setAsDefaultProtocolClient(PROTOCOL, process.execPath, [path.resolve(process.argv[1])]);
} else {
  app.setAsDefaultProtocolClient(PROTOCOL);
}

function openLink(link) {
  let u;
  try { u = new URL(link); } catch { return; }
  const code = u.searchParams.get('code');
  if (u.hostname !== 'auth' || !code || !/^[A-Za-z0-9_-]{20,64}$/.test(code)) return;
  const target = `${APP_URL}/auth/desktop/claim?code=${encodeURIComponent(code)}`;
  if (view) { view.webContents.loadURL(target); win.show(); win.focus(); } else pendingLink = link;
}

// ---- remembered window size ----------------------------------------------------------------
const stateFile = () => path.join(app.getPath('userData'), 'window.json');
function loadState() {
  try { return JSON.parse(fs.readFileSync(stateFile(), 'utf8')); } catch { return { width: 1280, height: 820 }; }
}
function saveState() {
  if (!win || win.isDestroyed()) return;
  const b = win.getNormalBounds();
  try { fs.writeFileSync(stateFile(), JSON.stringify({ ...b, maximized: win.isMaximized() })); } catch { /* not important */ }
}

const isOurs = (url) => { try { return new URL(url).origin === ORIGIN; } catch { return false; } };
const isSignIn = (url) => {
  try {
    const u = new URL(url);
    return (u.origin === ORIGIN && (u.pathname === '/auth/desktop/start' || u.pathname === '/auth/google'))
      || u.hostname === 'accounts.google.com' || u.hostname === 'oauth.telegram.org';
  } catch { return false; }
};

// ---- colours: the bar takes the page's own background --------------------------------------
let look = { bg: nativeTheme.shouldUseDarkColors ? '#1A1A1A' : '#FAF9F5', dark: nativeTheme.shouldUseDarkColors };
function applyLook() {
  if (!win || win.isDestroyed()) return;
  win.setBackgroundColor(look.bg);
  if (!MAC) {
    try { win.setTitleBarOverlay({ color: look.bg, symbolColor: look.dark ? '#ECECEC' : '#141413', height: BAR }); } catch { /* older systems */ }
  }
  win.webContents.send('mf-look', { ...look, canBack: !!view && view.webContents.navigationHistory.canGoBack() });
}
ipcMain.on('mf-page-look', (e, l) => {
  if (!view || e.sender !== view.webContents || !l || typeof l.bg !== 'string') return;
  look = { bg: l.bg, dark: !!l.dark };
  applyLook();
});
ipcMain.on('mf-bar', (e, action) => {
  if (!view || !win || e.sender !== win.webContents) return;
  const wc = view.webContents;
  if (action === 'back' && wc.navigationHistory.canGoBack()) wc.navigationHistory.goBack();
  else if (action === 'reload') wc.reload();
  else if (action === 'home') wc.loadURL(`${APP_URL}/dashboard`);
  else if (action === 'max') { if (win.isMaximized()) win.unmaximize(); else win.maximize(); }
});

function layout() {
  if (!win || !view) return;
  const [w, h] = win.getContentSize();
  view.setBounds({ x: 0, y: BAR, width: w, height: Math.max(0, h - BAR) });
}

function createWindow() {
  const st = loadState();
  win = new BrowserWindow({
    x: st.x, y: st.y, width: st.width || 1280, height: st.height || 820, minWidth: 900, minHeight: 600,
    title: 'Mockfy', show: false,
    titleBarStyle: 'hidden',
    ...(MAC ? { trafficLightPosition: { x: 14, y: 12 } }
      : { titleBarOverlay: { color: look.bg, symbolColor: look.dark ? '#ECECEC' : '#141413', height: BAR } }),
    backgroundColor: look.bg,
    icon: path.join(__dirname, 'build', 'icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
  });
  win.loadFile(path.join(__dirname, 'titlebar.html'), { query: { mac: MAC ? '1' : '' } });
  if (st.maximized) win.maximize();

  view = new WebContentsView({
    webPreferences: { preload: path.join(__dirname, 'preload.js'), spellcheck: false, contextIsolation: true, sandbox: true },
  });
  view.setBackgroundColor(look.bg);
  win.contentView.addChildView(view);
  layout();
  const wc = view.webContents;
  wc.setUserAgent(`${wc.getUserAgent()} MockfyDesktop/${app.getVersion()}`);

  win.once('ready-to-show', () => win.show());
  win.on('resize', () => { layout(); saveState(); });
  ['move', 'close'].forEach((ev) => win.on(ev, saveState));
  win.on('closed', () => { win = null; view = null; });
  wc.on('page-title-updated', (_e, t) => win && win.setTitle(t));
  wc.on('did-navigate', applyLook);
  wc.on('did-navigate-in-page', applyLook);

  // sign-in and other sites open in the browser; our own pages stay here
  wc.on('will-navigate', (e, url) => {
    if (isSignIn(url)) { e.preventDefault(); shell.openExternal(`${APP_URL}/auth/desktop/start`); return; }
    if (!isOurs(url)) { e.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); }
  });
  wc.setWindowOpenHandler(({ url }) => {
    if (isSignIn(url)) shell.openExternal(`${APP_URL}/auth/desktop/start`);
    else if (isOurs(url)) wc.loadURL(url);
    else if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });

  // no connection: a small page with a retry button instead of a blank window
  wc.on('did-fail-load', (_e, code, _desc, url, isMain) => {
    if (!isMain || code === -3) return;                                       // -3: the load was replaced
    wc.loadFile(path.join(__dirname, 'offline.html'), { query: { to: url || APP_URL } });
  });

  const link = pendingLink; pendingLink = null;
  if (link) { wc.loadURL(APP_URL); openLink(link); } else wc.loadURL(`${APP_URL}/dashboard`);
}

app.whenReady().then(() => {
  // the microphone for Speaking, notifications; only for Mockfy itself
  session.defaultSession.setPermissionRequestHandler((wc, permission, cb) => {
    cb(isOurs(wc.getURL()) && ['media', 'notifications', 'clipboard-sanitized-write', 'fullscreen'].includes(permission));
  });
  if (MAC) {
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { role: 'appMenu' }, { role: 'editMenu' },
      { label: 'View', submenu: [{ role: 'reload' }, { role: 'togglefullscreen' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'resetZoom' }] },
      { role: 'windowMenu' },
    ]));
  } else {
    Menu.setApplicationMenu(null);
  }
  createWindow();
  app.on('activate', () => { if (!win) createWindow(); });
});

app.on('web-contents-created', (_e, wc) => {
  wc.on('before-input-event', (e, input) => {           // F5 / Ctrl+R reload, Ctrl+= zoom, Alt+Left back (Windows has no menu)
    if (input.type !== 'keyDown' || MAC || !view) return;
    const page = view.webContents;
    const ctrl = input.control;
    if (input.key === 'F5' || (ctrl && input.key.toLowerCase() === 'r')) { page.reload(); e.preventDefault(); }
    else if (ctrl && (input.key === '=' || input.key === '+')) { page.setZoomLevel(page.getZoomLevel() + 0.5); e.preventDefault(); }
    else if (ctrl && input.key === '-') { page.setZoomLevel(page.getZoomLevel() - 0.5); e.preventDefault(); }
    else if (ctrl && input.key === '0') { page.setZoomLevel(0); e.preventDefault(); }
    else if (input.alt && input.key === 'ArrowLeft' && page.navigationHistory.canGoBack()) { page.navigationHistory.goBack(); e.preventDefault(); }
    else if (input.key === 'F11' && win) { win.setFullScreen(!win.isFullScreen()); e.preventDefault(); }
  });
});

app.on('window-all-closed', () => { if (!MAC) app.quit(); });
