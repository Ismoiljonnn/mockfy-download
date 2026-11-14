// Mockfy desktop: a window on mockfy.uz with what a browser tab cannot give (its own icon and window,
// no tabs or address bar, no spellcheck in tests). Sign-in goes through the computer's browser
// (Google blocks it inside apps): the site sends the app a one-time code on mockfy://auth?code=...
const { app, BrowserWindow, shell, session, Menu, nativeTheme } = require('electron');
const path = require('path');
const fs = require('fs');

const APP_URL = (process.env.MOCKFY_URL || 'https://mockfy.uz').replace(/\/$/, '');
const ORIGIN = new URL(APP_URL).origin;
const PROTOCOL = 'mockfy';
let win = null;
let pendingLink = process.argv.find((a) => a.startsWith(`${PROTOCOL}://`)) || null;

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
  if (win) { win.loadURL(target); win.show(); win.focus(); } else pendingLink = link;
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

function createWindow() {
  const st = loadState();
  win = new BrowserWindow({
    x: st.x, y: st.y, width: st.width || 1280, height: st.height || 820, minWidth: 900, minHeight: 600,
    title: 'Mockfy', show: false, autoHideMenuBar: true,
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#1A1A1A' : '#FAF9F5',
    icon: path.join(__dirname, 'build', 'icon.png'),
    webPreferences: { spellcheck: false, contextIsolation: true, sandbox: true },   // no spellcheck: it would help in Writing tests
  });
  if (st.maximized) win.maximize();
  win.webContents.setUserAgent(`${win.webContents.getUserAgent()} MockfyDesktop/${app.getVersion()}`);
  win.once('ready-to-show', () => win.show());
  ['resize', 'move', 'close'].forEach((ev) => win.on(ev, saveState));
  win.on('closed', () => { win = null; });

  // sign-in and other sites open in the browser; our own pages stay here
  win.webContents.on('will-navigate', (e, url) => {
    if (isSignIn(url)) { e.preventDefault(); shell.openExternal(`${APP_URL}/auth/desktop/start`); return; }
    if (!isOurs(url)) { e.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); }
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (isSignIn(url)) shell.openExternal(`${APP_URL}/auth/desktop/start`);
    else if (isOurs(url)) win.loadURL(url);
    else if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });

  // no connection: a small page with a retry button instead of a blank window
  win.webContents.on('did-fail-load', (_e, code, _desc, url, isMain) => {
    if (!isMain || code === -3) return;                                       // -3: the load was replaced
    win.loadFile(path.join(__dirname, 'offline.html'), { query: { to: url || APP_URL } });
  });

  const link = pendingLink; pendingLink = null;
  if (link) { win.loadURL(APP_URL); openLink(link); } else win.loadURL(`${APP_URL}/dashboard`);
}

app.whenReady().then(() => {
  // the microphone for Speaking, notifications; only for Mockfy itself
  session.defaultSession.setPermissionRequestHandler((wc, permission, cb) => {
    cb(isOurs(wc.getURL()) && ['media', 'notifications', 'clipboard-sanitized-write', 'fullscreen'].includes(permission));
  });
  if (process.platform === 'darwin') {
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
  wc.on('before-input-event', (e, input) => {           // F5 / Ctrl+R reload, Ctrl+= zoom on Windows (no menu there)
    if (input.type !== 'keyDown' || process.platform === 'darwin') return;
    const ctrl = input.control;
    if (input.key === 'F5' || (ctrl && input.key.toLowerCase() === 'r')) { wc.reload(); e.preventDefault(); }
    else if (ctrl && (input.key === '=' || input.key === '+')) { wc.setZoomLevel(wc.getZoomLevel() + 0.5); e.preventDefault(); }
    else if (ctrl && input.key === '-') { wc.setZoomLevel(wc.getZoomLevel() - 0.5); e.preventDefault(); }
    else if (ctrl && input.key === '0') { wc.setZoomLevel(0); e.preventDefault(); }
    else if (input.key === 'F11') { const w = BrowserWindow.fromWebContents(wc); if (w) w.setFullScreen(!w.isFullScreen()); e.preventDefault(); }
  });
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
