'use strict';

/* ============================================================================
 * OpenDir —— 目录页前端
 *   数据源：nginx autoindex_format json
 *   构建时由 build 注入 window.OPENDIR_CONFIG（来自 settings.json）
 *   页面里的偏好（刷新间隔 / 隐藏文件 / 排序 / 深浅色）持久化在 localStorage
 * ========================================================================== */

const CONFIG = Object.assign({
  version: '0.0.0',
  refreshMs: 120000,
  jsonArg: 'raw',
  jsonQuery: '',
  apiBase: '',
  showHidden: true,
  brand: '文件站',
  rootLabel: '根目录',
  demoCatalog: 'demo-catalog.json'
}, window.OPENDIR_CONFIG || {});

const PREF_KEY = 'opendir-prefs';
const $ = function (id) { return document.getElementById(id); };
const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
const dateFmt = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });
const timeFmt = new Intl.DateTimeFormat(undefined, { timeStyle: 'medium' });

const DEFAULTS = {
  refreshMs: CONFIG.refreshMs,
  showHidden: CONFIG.showHidden,
  theme: 'auto',
  sort: { key: 'name', dir: 1 }
};

const EXT_KIND = {
  image: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'avif', 'svg', 'bmp', 'heic', 'ico', 'tif', 'tiff', 'psd'],
  video: ['mp4', 'mkv', 'webm', 'mov', 'avi', 'ts', 'm4v', 'flv', 'rmvb', 'wmv'],
  audio: ['mp3', 'flac', 'wav', 'ogg', 'm4a', 'aac', 'opus', 'ape', 'wma'],
  archive: ['zip', '7z', 'rar', 'gz', 'xz', 'tar', 'bz2', 'zst', 'lz4', '001'],
  disk: ['iso', 'img', 'dmg', 'vhd', 'vhdx', 'qcow2', 'vmdk'],
  code: ['js', 'mjs', 'ts', 'py', 'sh', 'ps1', 'bat', 'cmd', 'rs', 'go', 'c', 'h', 'cpp', 'java', 'css', 'html', 'json', 'yml', 'yaml', 'toml', 'xml', 'sql'],
  doc: ['pdf', 'txt', 'md', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'epub', 'mobi', 'csv', 'srt', 'ass'],
  app: ['exe', 'msi', 'msix', 'deb', 'rpm', 'apk', 'appimage', 'pkg'],
  font: ['ttf', 'otf', 'woff', 'woff2']
};

const ICON = {
  folder: '<path d="M3 7V5h5.5l2 2H21v12H3z"/>',
  file: '<path d="M14 3H6v18h12V7z"/><path d="M14 3v4h4"/>',
  image: '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.5"/><path d="m4 18 5-5 3.5 3.5L16 13l4 5"/>',
  video: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m10 9 5 3-5 3z"/>',
  audio: '<path d="M9 16V6l10-2v10"/><circle cx="6.5" cy="17" r="2.5"/><circle cx="16.5" cy="15" r="2.5"/>',
  archive: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M11.5 3v3h1v2h-1v2h1v2h-1v2h1"/>',
  disk: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2"/>',
  code: '<path d="m8 8-4 4 4 4m8-8 4 4-4 4M14 5l-4 14"/>',
  doc: '<path d="M14 3H6v18h12V7z"/><path d="M14 3v4h4M9 12h6M9 16h4"/>',
  app: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M3 9h18M7 6.5h.01M10 6.5h.01"/>',
  font: '<path d="m5 20 7-16 7 16M8.5 14h7"/>'
};

/* ---------------------------------------------------------------- 偏好持久化 */

let prefs = {};
try {
  const raw = localStorage.getItem(PREF_KEY);
  prefs = raw ? (JSON.parse(raw) || {}) : {};
  if (typeof prefs !== 'object' || Array.isArray(prefs)) prefs = {};
} catch (e) { prefs = {}; }

function savePrefs(patch) {
  for (const key in patch) prefs[key] = patch[key];
  try { localStorage.setItem(PREF_KEY, JSON.stringify(prefs)); } catch (e) { /* 隐私模式 */ }
}

function applyStoredPrefs() {
  if (typeof prefs.refreshMs === 'number' && prefs.refreshMs >= 0) CONFIG.refreshMs = prefs.refreshMs;
  if (typeof prefs.showHidden === 'boolean') CONFIG.showHidden = prefs.showHidden;
}

const state = {
  path: '/',
  items: [],
  status: 'loading',
  error: '',
  filter: '',
  sort: prefs.sort && prefs.sort.key ? { key: prefs.sort.key, dir: prefs.sort.dir === -1 ? -1 : 1 } : { key: DEFAULTS.sort.key, dir: DEFAULTS.sort.dir },
  sig: '',
  updated: null,
  nextAt: 0
};

let controller = null;
let tickTimer = null;
let demoPath = '/';
let demoMap = null;

/* ---------------------------------------------------------------- 环境 */

function inDemo() {
  return typeof window.__DEMO_CATALOG__ !== 'undefined' ||
    new URLSearchParams(location.search).has('demo');
}

function normalizeDir(p) {
  // 先解码再统一编码，避免已经把列表项百分号编码过的路径被二次编码
  const segs = String(p).split('/').filter(Boolean).map(function (seg) {
    let plain = seg;
    try { plain = decodeURIComponent(seg); } catch (e) { /* 不是合法转义，原样保留 */ }
    return encodeURIComponent(plain);
  });
  return '/' + segs.join('/') + (segs.length ? '/' : '');
}

function currentDir() {
  if (inDemo()) return demoPath;
  let raw = location.pathname;
  try { raw = decodeURIComponent(raw); } catch (e) { /* 保留原样 */ }
  return normalizeDir(raw);
}

function prettyPath(dir) {
  try { return decodeURIComponent(dir); } catch (e) { return dir; }
}

function joinPath(dir, name, isDir) {
  return dir + encodeURIComponent(name) + (isDir ? '/' : '');
}

function dirHref(p) {
  return inDemo() ? '#' : p;
}

function queryString() {
  const q = CONFIG.jsonQuery || (CONFIG.jsonArg + '=1');
  return q + '&_=' + Date.now();
}

function listingURL(dir) {
  const base = CONFIG.apiBase ? CONFIG.apiBase.replace(/\/+$/, '') + dir : dir;
  return base + '?' + queryString();
}

/* ---------------------------------------------------------------- 数据 */

function isEntry(item) {
  if (!item || typeof item !== 'object') return false;
  const name = item.name;
  if (typeof name !== 'string' || !name || name === '.' || name === '..') return false;
  if (/[/\\\u0000-\u001f\u007f]/.test(name)) return false;
  return item.type === 'file' || item.type === 'directory';
}

function loadDemoScript() {
  if (window.__DEMO_CATALOG__) return Promise.resolve();
  return new Promise(function (resolve, reject) {
    const s = document.createElement('script');
    s.src = CONFIG.demoCatalog;
    s.onload = function () { resolve(); };
    s.onerror = function () { reject(new Error('演示数据加载失败')); };
    document.head.append(s);
  });
}

async function fetchListing(dir, signal) {
  if (inDemo()) {
    await loadDemoScript();
    if (!demoMap) {
      demoMap = new Map();
      const source = window.__DEMO_CATALOG__ || {};
      Object.keys(source).forEach(function (k) { demoMap.set(normalizeDir(k), source[k]); });
    }
    await new Promise(function (r) { setTimeout(r, 80); });
    return demoMap.get(dir) || [];
  }
  const res = await fetch(listingURL(dir), {
    signal: signal,
    cache: 'no-store',
    headers: { Accept: 'application/json' }
  });
  if (!res.ok) throw new Error('HTTP ' + res.status + ' ' + res.statusText);
  const data = await res.json();
  if (!Array.isArray(data)) throw new Error('目录 JSON 格式不正确');
  return data;
}

async function load(opts) {
  const o = opts || {};
  const dir = currentDir();
  state.path = dir;
  if (o.reset) window.scrollTo(0, 0);
  if (controller) controller.abort();
  const ac = new AbortController();
  controller = ac;
  if (!o.silent) {
    state.status = 'loading';
    state.error = '';
    render();
  }
  try {
    const raw = await fetchListing(dir, ac.signal);
    if (ac.signal.aborted) return;
    state.items = raw.filter(isEntry).map(function (it) {
      return {
        name: it.name,
        type: it.type,
        size: Number(it.size) || 0,
        mtime: it.mtime ? new Date(it.mtime) : null
      };
    });
    state.status = '';
    state.error = '';
    state.updated = new Date();
  } catch (err) {
    if (ac.signal.aborted) return;
    state.error = String((err && err.message) || err);
    if (o.silent && state.items.length) {
      state.status = '';
    } else {
      state.status = 'error';
      state.items = [];
    }
  } finally {
    if (controller === ac) controller = null;
  }
  state.nextAt = CONFIG.refreshMs ? Date.now() + CONFIG.refreshMs : 0;
  render();
}

/* ---------------------------------------------------------------- 格式化 */

function formatSize(bytes) {
  if (!isFinite(bytes) || bytes < 0) return '—';
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB'];
  let i = 0;
  let v = bytes;
  while (v >= 1024 && i < units.length - 1) { v = v / 1024; i++; }
  const text = i === 0 ? String(v) : (v >= 10 ? v.toFixed(0) : v.toFixed(1));
  return text + ' ' + units[i];
}

function formatDate(d) {
  return d && !isNaN(d.getTime()) ? dateFmt.format(d) : '—';
}

function kindOf(item) {
  if (item.type === 'directory') return 'folder';
  const name = item.name;
  const dot = name.lastIndexOf('.');
  if (dot < 1) return 'file';
  const ext = name.slice(dot + 1).toLowerCase();
  for (const kind in EXT_KIND) {
    if (EXT_KIND[kind].indexOf(ext) !== -1) return kind;
  }
  return 'file';
}

function formatInterval(ms) {
  if (!ms) return '已关闭';
  if (ms < 60000) return Math.round(ms / 1000) + ' 秒';
  return Math.round(ms / 60000) + ' 分钟';
}

/* ---------------------------------------------------------------- 渲染 */

function iconEl(kind) {
  const span = document.createElement('span');
  span.className = 'ico ' + kind;
  span.setAttribute('aria-hidden', 'true');
  span.innerHTML = '<svg viewBox="0 0 24 24">' + ICON[kind] + '</svg>';
  return span;
}

function navHandler(target) {
  return function (ev) {
    if (ev.button || ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
    ev.preventDefault();
    navigate(target);
  };
}

function navigate(p) {
  const target = normalizeDir(p);
  $('filter').value = '';
  state.filter = '';
  if (inDemo()) {
    demoPath = target;
  } else {
    history.pushState(null, '', target);
  }
  load({ reset: true });
}

function renderBreadcrumb() {
  const nav = $('breadcrumb');
  nav.textContent = '';
  const segs = prettyPath(state.path).split('/').filter(Boolean);
  let acc = '/';
  const parts = [{ label: CONFIG.rootLabel, path: '/' }];
  segs.forEach(function (s) {
    acc += encodeURIComponent(s) + '/';
    parts.push({ label: s, path: acc });
  });
  parts.forEach(function (part, i) {
    if (i) {
      const sep = document.createElement('span');
      sep.className = 'sep';
      sep.textContent = '/';
      nav.append(sep);
    }
    const a = document.createElement('a');
    a.textContent = part.label;
    a.href = dirHref(part.path);
    if (i === parts.length - 1) a.setAttribute('aria-current', 'page');
    else a.addEventListener('click', navHandler(part.path));
    nav.append(a);
  });
  nav.hidden = false;
  document.title = (segs.length ? segs[segs.length - 1] : CONFIG.rootLabel) + ' · ' + CONFIG.brand;
}

function buildRow(item) {
  const tr = document.createElement('tr');
  const tdName = document.createElement('td');
  tdName.className = 'col-name';
  const a = document.createElement('a');
  a.className = 'entry';
  const isDir = item.type === 'directory';
  a.href = dirHref(joinPath(state.path, item.name, isDir));
  if (!isDir) a.setAttribute('download', item.name);
  a.title = item.name + ' — ' + formatSize(item.size);
  const label = document.createElement('span');
  label.className = 'name';
  label.textContent = item.name;
  a.append(iconEl(kindOf(item)), label);
  if (isDir) a.addEventListener('click', navHandler(joinPath(state.path, item.name, true)));
  tdName.append(a);
  tr.append(tdName);

  const tdSize = document.createElement('td');
  tdSize.className = 'col-size';
  tdSize.textContent = isDir ? '—' : formatSize(item.size);
  tr.append(tdSize);

  const tdDate = document.createElement('td');
  tdDate.className = 'col-date';
  tdDate.textContent = formatDate(item.mtime);
  tr.append(tdDate);
  return tr;
}

function buildParentRow() {
  const tr = document.createElement('tr');
  tr.className = 'parent';
  const tdName = document.createElement('td');
  tdName.className = 'col-name';
  const parent = state.path.replace(/[^/]+\/$/, '') || '/';
  const a = document.createElement('a');
  a.className = 'entry';
  a.href = dirHref(parent);
  a.addEventListener('click', navHandler(parent));
  const label = document.createElement('span');
  label.className = 'name';
  label.textContent = '..（上一级）';
  a.append(iconEl('folder'), label);
  tdName.append(a);
  tr.append(tdName);
  tr.append(document.createElement('td'), document.createElement('td'));
  return tr;
}

function visibleItems() {
  const q = state.filter.trim().toLowerCase();
  const list = state.items.filter(function (it) {
    if (!CONFIG.showHidden && it.name.charAt(0) === '.') return false;
    return !q || it.name.toLowerCase().indexOf(q) !== -1;
  });
  const key = state.sort.key;
  const dirn = state.sort.dir;
  list.sort(function (a, b) {
    if (a.type !== b.type) return a.type === 'directory' ? -1 : 1;
    let r = 0;
    if (key === 'size') r = (a.size || 0) - (b.size || 0);
    else if (key === 'mtime') r = ((a.mtime ? a.mtime.getTime() : 0) - (b.mtime ? b.mtime.getTime() : 0));
    if (r === 0) r = collator.compare(a.name, b.name);
    return r * dirn;
  });
  return list;
}

function updateMeta(items) {
  const total = items.reduce(function (s, it) { return s + (it.type === 'file' ? it.size : 0); }, 0);
  $('meta').textContent = items.length ? (items.length + ' 项 · 共 ' + formatSize(total)) : '';

  const st = $('status');
  st.className = 'status';
  if (state.status === 'error') {
    st.classList.add('is-error');
    st.textContent = '无法加载目录列表' + (state.error ? '（' + state.error + '）' : '') + '，请稍后重试。';
  } else if (state.status === 'loading' && !state.items.length) {
    st.textContent = '正在加载…';
  } else if (!items.length) {
    st.textContent = state.filter ? '没有匹配的文件。' : '这个目录是空的。';
  } else {
    st.textContent = '';
  }
  updateTicker();
}

function updateTicker() {
  const el = $('updated');
  if (!state.updated || state.status === 'error') { el.textContent = ''; return; }
  const stamp = '最后更新 ' + timeFmt.format(state.updated);
  if (!CONFIG.refreshMs) { el.textContent = stamp + ' · 自动刷新已关闭'; return; }
  const left = Math.max(0, Math.round((state.nextAt - Date.now()) / 1000));
  const mm = String(Math.floor(left / 60)).padStart(2, '0');
  const ss = String(left % 60).padStart(2, '0');
  el.textContent = stamp + ' · ' + mm + ':' + ss + ' 后自动刷新';
}

function render() {
  renderBreadcrumb();
  const items = visibleItems();
  const sig = JSON.stringify([
    state.path, state.filter, state.sort, state.status, CONFIG.showHidden,
    items.map(function (it) {
      return [it.name, it.type, it.size, it.mtime ? it.mtime.getTime() : 0];
    })
  ]);
  if (sig !== state.sig) {
    state.sig = sig;
    const tbody = $('list');
    const frag = document.createDocumentFragment();
    if (state.path !== '/') frag.append(buildParentRow());
    items.forEach(function (it) { frag.append(buildRow(it)); });
    tbody.textContent = '';
    tbody.append(frag);
    updateSortHeaders();
  }
  updateMeta(items);
}

function updateSortHeaders() {
  document.querySelectorAll('[data-sort]').forEach(function (btn) {
    const active = btn.dataset.sort === state.sort.key;
    const th = btn.closest('th');
    if (th) th.setAttribute('aria-sort', active ? (state.sort.dir === 1 ? 'ascending' : 'descending') : 'none');
    const arrow = btn.querySelector('.arrow');
    if (arrow) arrow.textContent = active ? (state.sort.dir === 1 ? '↑' : '↓') : '';
  });
}

/* ---------------------------------------------------------------- 主题与设置面板 */

function applyTheme(next) {
  const value = ['auto', 'light', 'dark'].indexOf(next) !== -1 ? next : 'auto';
  document.documentElement.dataset.theme = value;
  savePrefs({ theme: value });
}

function cycleTheme() {
  const order = ['auto', 'light', 'dark'];
  const now = document.documentElement.dataset.theme || 'auto';
  applyTheme(order[(order.indexOf(now) + 1) % order.length]);
}

function syncPanel() {
  const select = $('pref-refresh');
  if (!select) return;
  let matched = false;
  for (const opt of select.options) {
    if (Number(opt.value) === CONFIG.refreshMs) { select.value = opt.value; matched = true; }
  }
  if (!matched) {
    const opt = document.createElement('option');
    opt.value = String(CONFIG.refreshMs);
    opt.textContent = formatInterval(CONFIG.refreshMs) + '（自定义）';
    select.append(opt);
    select.value = String(CONFIG.refreshMs);
  }
  if ($('pref-hidden')) $('pref-hidden').checked = !!CONFIG.showHidden;
  if ($('panel-version')) $('panel-version').textContent = 'v' + CONFIG.version;
}

function setPanel(open) {
  const panel = $('settings-panel');
  const btn = $('settings');
  if (!panel || !btn) return;
  panel.hidden = !open;
  btn.setAttribute('aria-expanded', String(open));
  if (open) syncPanel();
}

function resetPrefs() {
  prefs = {};
  try { localStorage.removeItem(PREF_KEY); } catch (e) { /* ignore */ }
  CONFIG.refreshMs = DEFAULTS.refreshMs;
  CONFIG.showHidden = DEFAULTS.showHidden;
  state.sort = { key: DEFAULTS.sort.key, dir: DEFAULTS.sort.dir };
  applyTheme(DEFAULTS.theme);
  startTimer();
  syncPanel();
  render();
}

/* ---------------------------------------------------------------- 定时器 */

function startTimer() {
  if (tickTimer) { clearInterval(tickTimer); tickTimer = null; }
  if (!CONFIG.refreshMs) { state.nextAt = 0; updateTicker(); return; }
  state.nextAt = Date.now() + CONFIG.refreshMs;
  tickTimer = setInterval(function () {
    updateTicker();
    if (document.hidden) {
      state.nextAt = Date.now() + CONFIG.refreshMs;   // 页面不可见时暂停计时
      return;
    }
    if (Date.now() >= state.nextAt) {
      state.nextAt = Date.now() + CONFIG.refreshMs;
      load({ silent: true });
    }
  }, 1000);
}

/* ---------------------------------------------------------------- 初始化 */

function init() {
  applyStoredPrefs();
  applyTheme(prefs.theme || DEFAULTS.theme);

  if (inDemo()) demoPath = normalizeDir(new URLSearchParams(location.search).get('p') || '/');
  if ($('brand-name')) $('brand-name').textContent = CONFIG.brand;

  $('brand').addEventListener('click', navHandler('/'));
  $('refresh').addEventListener('click', function () {
    const btn = $('refresh');
    btn.classList.remove('spin');
    void btn.offsetWidth;
    btn.classList.add('spin');
    load();
  });
  $('theme').addEventListener('click', cycleTheme);

  $('filter').addEventListener('input', function (ev) {
    state.filter = ev.target.value;
    render();
  });

  document.querySelectorAll('[data-sort]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      const key = btn.dataset.sort;
      state.sort = { key: key, dir: state.sort.key === key ? -state.sort.dir : 1 };
      savePrefs({ sort: state.sort });
      render();
    });
  });

  // 设置面板
  $('settings').addEventListener('click', function (ev) {
    ev.stopPropagation();
    setPanel($('settings-panel').hidden);
  });
  $('pref-refresh').addEventListener('change', function (ev) {
    const ms = Number(ev.target.value);
    CONFIG.refreshMs = ms >= 0 ? ms : 0;
    savePrefs({ refreshMs: CONFIG.refreshMs });
    startTimer();
    updateTicker();
  });
  $('pref-hidden').addEventListener('change', function (ev) {
    CONFIG.showHidden = ev.target.checked;
    savePrefs({ showHidden: CONFIG.showHidden });
    render();
  });
  $('pref-reset').addEventListener('click', resetPrefs);
  document.addEventListener('click', function (ev) {
    const wrap = $('settings-wrap');
    if (wrap && !wrap.contains(ev.target)) setPanel(false);
  });

  document.addEventListener('keydown', function (ev) {
    const tag = (ev.target && ev.target.tagName) || '';
    const typing = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT';
    if (ev.key === 'Escape') {
      if (!($('settings-panel').hidden)) { setPanel(false); return; }
      if (typing) {
        $('filter').value = '';
        state.filter = '';
        $('filter').blur();
        render();
      }
      return;
    }
    if (ev.key === '/' && !typing) {
      ev.preventDefault();
      $('filter').focus();
      $('filter').select();
    }
  });

  document.addEventListener('visibilitychange', function () {
    if (!document.hidden && CONFIG.refreshMs && Date.now() >= state.nextAt) {
      state.nextAt = Date.now() + CONFIG.refreshMs;
      load({ silent: true });
    }
  });

  window.addEventListener('popstate', function () { load(); });

  syncPanel();
  startTimer();
  load();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
