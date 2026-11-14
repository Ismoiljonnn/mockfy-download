// Two jobs. In the title bar (titlebar.html): its buttons and the page's colours.
// In the site's pages: tell the window the page's background and whether it is dark, so the bar matches.
const { contextBridge, ipcRenderer } = require('electron');

if (location.protocol === 'file:' && location.pathname.endsWith('titlebar.html')) {
  contextBridge.exposeInMainWorld('mfBar', {
    act: (a) => ipcRenderer.send('mf-bar', String(a)),
    onLook: (cb) => ipcRenderer.on('mf-look', (_e, l) => cb(l)),
  });
} else if (location.protocol === 'https:' || location.protocol === 'http:') {
  const send = () => {
    const root = document.documentElement;
    const body = document.body;
    if (!body) return;
    let bg = getComputedStyle(body).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') bg = getComputedStyle(root).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') bg = '#FAF9F5';
    const hex = toHex(bg);
    // dark or light from the background itself (a page may follow the system or its own switch)
    const n = parseInt(hex.slice(1, 7), 16);
    const lum = ((n >> 16) & 255) * 0.299 + ((n >> 8) & 255) * 0.587 + (n & 255) * 0.114;
    ipcRenderer.send('mf-page-look', { bg: hex, dark: lum < 128 });
  };
  const toHex = (c) => {
    const m = c.match(/\d+(\.\d+)?/g);
    if (!m || m.length < 3) return c;
    return '#' + m.slice(0, 3).map((n) => Math.round(+n).toString(16).padStart(2, '0')).join('');
  };
  window.addEventListener('DOMContentLoaded', () => {
    send();
    new MutationObserver(() => setTimeout(send, 30)).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-dark', 'class'] });
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', send);
    window.addEventListener('load', send);
  });
}
