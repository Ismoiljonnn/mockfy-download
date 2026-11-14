// Tells the window the page's background and whether it is dark, so the window buttons (drawn over the
// page's top row) take the page's own colours.
const { ipcRenderer } = require('electron');

if (location.protocol === 'https:' || location.protocol === 'http:') {
  const toHex = (c) => {
    const m = c.match(/\d+(\.\d+)?/g);
    if (!m || m.length < 3) return '#FAF9F5';
    return '#' + m.slice(0, 3).map((n) => Math.round(+n).toString(16).padStart(2, '0')).join('');
  };
  const send = () => {
    // the colour behind the window buttons: the header if there is one, else the page
    const top = document.querySelector('.header-bar, .lp-header') || document.body;
    if (!top) return;
    let bg = getComputedStyle(top).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') bg = getComputedStyle(document.body).backgroundColor;
    if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') bg = getComputedStyle(document.documentElement).backgroundColor;
    const hex = toHex(bg || '');
    const n = parseInt(hex.slice(1, 7), 16);
    const lum = ((n >> 16) & 255) * 0.299 + ((n >> 8) & 255) * 0.587 + (n & 255) * 0.114;
    ipcRenderer.send('mf-page-look', { bg: hex, dark: lum < 128 });
  };
  window.addEventListener('DOMContentLoaded', () => {
    send();
    new MutationObserver(() => setTimeout(send, 30)).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-dark', 'class'] });
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', send);
    window.addEventListener('load', send);
  });
}
