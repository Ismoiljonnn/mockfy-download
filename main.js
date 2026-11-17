// Mockfy desktop: a window on mockfy.uz with what a browser tab cannot give (its own icon and window,
// no tabs or address bar, no spellcheck in tests). No title bar: the site's own top row is where the
// window is dragged (it knows it is in the app), and the window buttons sit over its right end in its colours.
// Sign-in goes through the computer's browser (Google blocks it inside apps): the site sends the app a
// one-time code on mockfy://auth?code=...
const { app, BrowserWindow, shell, session, Menu, nativeTheme, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');

const APP_URL = (process.env.MOCKFY_URL || 'https://mockfy.uz').replace(/\/$/, '');
const ORIGIN = new URL(APP_URL).origin;
const PROTOCOL = 'mockfy';
const BAR = 52;                                   // the window buttons' height: the page's top row
const MAC = process.platform === 'darwin';
let win = null;
let view = null;
let pendingLink = process.argv.find((a) => a.startsWith(`${PROTOCOL}://`)) || null;

// a separate profile for trying a build while the installed app is open: MOCKFY_PROFILE=test
if (process.env.MOCKFY_PROFILE) app.setPath('userData', path.join(app.getPath('appData'), `Mockfy-${process.env.MOCKFY_PROFILE}`));

// faster pages: the GPU draws them, compiled scripts are kept between visits
app.commandLine.appendSwitch('enable-gpu-rasterization');
app.commandLine.appendSwitch('enable-zero-copy');
if (process.platform === 'win32') app.setAppUserModelId('uz.mockfy.desktop');   // the taskbar and notifications know it as Mockfy

// how the app introduces itself to mockfy.uz (pages, the service worker, everything): the site then opens
// on sign-in instead of the landing page, keeps room for the window buttons and lists every section
const UA = `${app.userAgentFallback} MockfyDesktop/${app.getVersion()}`;
app.userAgentFallback = UA;

// ---- one window, and mockfy:// links reach it -------------------------------------------
// A second launch (a mockfy:// link from the browser, a second click on the icon) hands its link to the
// window already open and ends at once, before it can draw a window of its own.
const FIRST = app.requestSingleInstanceLock();
if (!FIRST) {
  app.exit(0);
} else {
  app.on('second-instance', (_e, argv) => {
    const link = argv.find((a) => a.startsWith(`${PROTOCOL}://`));
    if (link) openLink(link);
    if (win) {
      if (win.isMinimized()) win.restore();
      win.show();
      win.setAlwaysOnTop(true); win.focus(); win.setAlwaysOnTop(false);     // Windows: really come to the front
    }
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
  if (win) { win.webContents.loadURL(target); win.show(); win.focus(); } else pendingLink = link;
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
    try { win.setTitleBarOverlay({ color: '#00000000', symbolColor: look.dark ? '#ECECEC' : '#141413', height: BAR }); } catch { /* older systems */ }
  }
}
ipcMain.on('mf-page-look', (e, l) => {
  if (!win || e.sender !== win.webContents || !l || typeof l.bg !== 'string') return;
  look = { bg: l.bg, dark: !!l.dark };
  applyLook();
});

function createWindow() {
  const st = loadState();
  win = new BrowserWindow({
    x: st.x, y: st.y, width: st.width || 1280, height: st.height || 820, minWidth: 900, minHeight: 600,
    title: 'Mockfy', show: false,
    titleBarStyle: 'hidden',
    ...(MAC ? { trafficLightPosition: { x: 16, y: 18 } }
      : { titleBarOverlay: { color: '#00000000', symbolColor: look.dark ? '#ECECEC' : '#141413', height: BAR } }),
    backgroundColor: look.bg,
    icon: path.join(__dirname, 'build', 'icon.png'),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), spellcheck: false, contextIsolation: true, sandbox: true, v8CacheOptions: 'bypassHeatCheck', backgroundThrottling: false },
  });
  view = win;                                     // the page is the window's own contents
  if (st.maximized) win.maximize();
  const wc = win.webContents;
  wc.setUserAgent(UA);

  win.once('ready-to-show', () => win.show());
  ['resize', 'move', 'close'].forEach((ev) => win.on(ev, saveState));
  win.on('closed', () => { win = null; view = null; });
  win.on('page-title-updated', (e) => e.preventDefault());   // the window is always just "Mockfy" (taskbar, Alt+Tab)
  wc.on('did-navigate', applyLook);
  // full screen (F11): no window buttons, so the page takes back the room it kept for them
  // (the state is passed as the event says: isFullScreen() still has the old value while these fire on Windows)
  const tellFull = (on) => { if (!wc.isDestroyed()) wc.send('mf-full', on); };
  win.on('enter-full-screen', () => tellFull(true));
  win.on('leave-full-screen', () => tellFull(false));
  ipcMain.on('mf-ask-full', (e) => { if (e.sender === wc) tellFull(win.isFullScreen()); });
  if (process.env.MOCKFY_SHOT) {                  // development: a picture of the window after each page loads
    wc.on('did-finish-load', () => setTimeout(() => wc.capturePage().then((img) => fs.writeFileSync(process.env.MOCKFY_SHOT, img.toPNG())), 2500));
  }

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

// ---- updates: Windows downloads a new version in the background and installs it when the app closes
// (electron-updater reads latest.yml from the newest mockfy-download release). macOS needs a signed app
// for this, so the Mac version is updated from the download page for now.
function autoUpdate() {
  if (!app.isPackaged || MAC) return;
  let updater;
  try { ({ autoUpdater: updater } = require('electron-updater')); } catch { return; }
  updater.autoDownload = true;
  updater.autoInstallOnAppQuit = true;
  updater.on('error', () => { /* no connection or no release yet: try again later */ });
  const check = () => updater.checkForUpdates().catch(() => {});
  check();
  setInterval(check, 4 * 60 * 60 * 1000);
}

// Windows search finds apps by their Start menu shortcut. The installer makes one, but an update or a
// clean-up can lose it; the app puts it back itself (and keeps it pointing at this copy).
function ensureStartMenuShortcut() {
  if (process.platform !== 'win32' || !app.isPackaged) return;
  try {
    const link = path.join(app.getPath('appData'), 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Mockfy.lnk');
    const want = { target: process.execPath, appUserModelId: 'uz.mockfy.desktop', description: 'Mockfy', icon: process.execPath, iconIndex: 0 };
    let ok = false;
    try { ok = shell.readShortcutLink(link).target === process.execPath; } catch { ok = false; }
    if (!ok) shell.writeShortcutLink(link, fs.existsSync(link) ? 'replace' : 'create', want);
  } catch { /* never stops the app */ }
}

if (FIRST) app.whenReady().then(() => {
  // the site's service worker fetches pages too: every request of the app says it is the desktop app
  session.defaultSession.setUserAgent(UA);
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
  autoUpdate();
  ensureStartMenuShortcut();
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
