// Tells the window the colour under its buttons (top right of the page) and whether it is dark, so the
// buttons, drawn over the page with no background of their own, stay readable on every page.
const { ipcRenderer } = require('electron');

if (location.protocol === 'https:' || location.protocol === 'http:') {
  const rgb = (c) => {
    const m = (c || '').match(/[\d.]+/g);
    if (!m || m.length < 3) return null;
    if (m.length > 3 && +m[3] === 0) return null;                       // fully transparent
    return m.slice(0, 3).map(Number);
  };
  // the first painted colour under a point: a plain background, or the first colour of a gradient
  const colourAt = (x, y) => {
    for (let el = document.elementFromPoint(x, y); el; el = el.parentElement) {
      const s = getComputedStyle(el);
      const plain = rgb(s.backgroundColor);
      if (plain) return plain;
      const grad = s.backgroundImage && s.backgroundImage.match(/rgba?\([^)]*\)|#[0-9a-f]{3,8}/i);
      if (grad) {
        const g = grad[0].startsWith('#') ? hexRgb(grad[0]) : rgb(grad[0]);
        if (g) return g;
      }
    }
    return rgb(getComputedStyle(document.body || document.documentElement).backgroundColor) || [250, 249, 245];
  };
  const hexRgb = (h) => {
    h = h.slice(1);
    if (h.length === 3) h = h.split('').map((c) => c + c).join('');
    const n = parseInt(h.slice(0, 6), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  };
  const send = () => {
    if (!document.body) return;
    const [r, g, b] = colourAt(window.innerWidth - 70, 16);
    const hex = '#' + [r, g, b].map((n) => Math.round(n).toString(16).padStart(2, '0')).join('');
    ipcRenderer.send('mf-page-look', { bg: hex, dark: r * 0.299 + g * 0.587 + b * 0.114 < 150 });
  };
  // the page knows it is in the app even when it came from a cache: room for the window buttons
  const mark = () => {
    const root = document.documentElement;
    root.classList.add('mf-desktop');
    if (process.platform === 'darwin') root.classList.add('mf-mac');
  };
  ipcRenderer.on('mf-full', (_e, on) => document.documentElement.classList.toggle('mf-full', !!on));
  // the scroll bar starts under the page's top row: tell the page how tall that row is
  const top = () => {
    const bar = document.querySelector('.header-bar, .lp-header');
    if (bar) document.documentElement.style.setProperty('--mf-top', Math.round(bar.getBoundingClientRect().height) + 'px');
  };
  window.addEventListener('DOMContentLoaded', () => {
    mark();
    top();
    window.addEventListener('resize', top);
    ipcRenderer.send('mf-ask-full');
    send();
    new MutationObserver(() => setTimeout(send, 30)).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'data-dark', 'class'] });
    matchMedia('(prefers-color-scheme: dark)').addEventListener('change', send);
    window.addEventListener('load', send);
    window.addEventListener('resize', () => setTimeout(send, 100));
    setTimeout(send, 600);                         // after the first transitions settle
  });
}
