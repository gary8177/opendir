#!/usr/bin/env node
/**
 * OpenDir 构建脚本（Node 版，等价于 build.ps1）
 *   读 settings.json（初始化设置，持久化）→ 生成：
 *     dist/theme.html   部署用的单文件页面
 *     dist/index.html   同上（方便把 themePath 直接指向 dist/ 做本地测试）
 *     dist/nginx.conf   填好路径的 nginx 配置
 *     dist/preview.html 本地预览（内联演示数据）
 */
import { readFile, writeFile, mkdir, stat, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const read = (p) => readFile(path.join(here, p), 'utf8');
const write = async (p, text) => {
  await mkdir(path.dirname(path.join(here, p)), { recursive: true });
  await writeFile(path.join(here, p), text, 'utf8');
};

const settingsFile = process.env.OPENDIR_SETTINGS || 'settings.json';
let settings;
try {
  settings = JSON.parse(await read(settingsFile));
} catch (err) {
  console.error('读不到 ' + settingsFile + '，请先运行初始化：');
  console.error('  powershell -ExecutionPolicy Bypass -File init.ps1');
  process.exit(1);
}

const version = (await read('VERSION')).trim();
const tpl = await read('src/index.html');
const css = await read('src/style.css');
const js = await read('src/app.js');
const demo = await read('src/demo-catalog.json');
const nginxTpl = await read('nginx.conf.tpl');

const srv = settings.server || {};
const ui = settings.ui || {};
const buildOpts = settings.build || {};
const warnings = [];

/**
 * 统一成 nginx 能吃的路径：反斜杠换正斜杠、去尾斜杠、检查是否绝对路径。
 * nginx 里 D:\Downloads 会被当成转义序列，必须写 D:/Downloads。
 */
function toPosixPath(value, fallback, label) {
  let v = value === undefined || value === null ? '' : String(value).trim();
  if (!v) v = fallback;
  v = v.replace(/\\/g, '/');
  if (v.slice(0, 2) !== '//') v = v.replace(/\/{2,}/g, '/');
  v = v.replace(/\/+$/, '');
  if (v === '') v = '/';
  const absolute = v.startsWith('/') || /^[A-Za-z]:\//.test(v);
  if (!absolute) {
    warnings.push(label + ' 不是绝对路径（' + v + '）：nginx 的 root/alias 需要绝对路径，Windows 请写成 D:/目录');
  }
  return v;
}

const root = toPosixPath(srv.root, '/srv/files', 'server.root');
const themePath = toPosixPath(srv.themePath, '/var/www/opendir', 'server.themePath');
const themeUrl = '/' + String(srv.themeUrl || '_opendir').replace(/^\/+|\/+$/g, '');
const jsonPrefix = '/' + String(srv.jsonPrefix || '_raw').replace(/^\/+|\/+$/g, '');
const jsonArg = String(srv.jsonArg || 'raw');
const listen = String(srv.listen || '80');
const serverName = String(srv.serverName || '_');

const refreshRaw = Number(ui.refreshMs);
const injected = {
  version: version,
  refreshMs: Number.isFinite(refreshRaw) && refreshRaw >= 0 ? refreshRaw : 120000,
  jsonArg: jsonArg,
  apiBase: ui.apiBase || '',
  showHidden: ui.showHidden !== false,
  brand: ui.brand || 'OpenDir',
  rootLabel: ui.rootLabel || '根目录'
};
const configScript = 'window.OPENDIR_CONFIG = ' + JSON.stringify(injected) + ';';

const expand = (t) =>
  t
    .replace('/*{{STYLE}}*/', () => '\n' + css + '\n')
    .replace('/*{{CONFIG}}*/', () => configScript)
    .replace('/*{{SCRIPT}}*/', () => '\n' + js + '\n');

const theme = expand(tpl)
  .replace('<script>/*{{DEMO}}*/</script>', '')
  .replace('<title>文件列表</title>', () => '<title>' + injected.brand + '</title>');

const preview = expand(tpl).replace('/*{{DEMO}}*/', () => 'window.__DEMO_CATALOG__ = ' + demo.trim() + ';');

// Docker 版：配置改成外部 config.js，容器启动时按环境变量生成
const dockerHtml = tpl
  .replace('<script>/*{{CONFIG}}*/</script>', '<script src="__OPENDIR_CONFIG_JS__"></script>')
  .replace('/*{{STYLE}}*/', () => '\n' + css + '\n')
  .replace('/*{{SCRIPT}}*/', () => '\n' + js + '\n')
  .replace('<script>/*{{DEMO}}*/</script>', '')
  .replace('<title>文件列表</title>', () => '<title>' + injected.brand + '</title>');

const nginxConf = nginxTpl
  .replaceAll('{{VERSION}}', version)
  .replaceAll('{{LISTEN}}', listen)
  .replaceAll('{{SERVER_NAME}}', serverName)
  .replaceAll('{{ROOT}}', root)
  .replaceAll('{{THEME_PATH}}', themePath)
  .replaceAll('{{THEME_URL}}', themeUrl)
  .replaceAll('{{JSON_PREFIX}}', jsonPrefix)
  .replaceAll('{{JSON_ARG}}', jsonArg);

await write('dist/theme.html', theme);
await copyFile(path.join(here, 'dist/theme.html'), path.join(here, 'dist/index.html'));
if (buildOpts.emitNginxConf !== false) {
  await write('dist/nginx.conf', nginxConf);
  // 便携 nginx 存在的话顺带同步一份，省掉手工 copy
  const portable = path.join(here, 'tools/nginx/conf/opendir.conf');
  const syncPortable = await stat(portable).then(() => true).catch(() => false);
  if (syncPortable) {
    await copyFile(path.join(here, 'dist/nginx.conf'), portable);
    console.log('已同步 → tools/nginx/conf/opendir.conf');
  }
}
if (buildOpts.emitPreview !== false) await write('dist/preview.html', preview);
if (buildOpts.emitDocker !== false) {
  await write('dist/docker/index.html', dockerHtml);
  await write('dist/docker/config.js', configScript);
}

const kb = async (p) => ((await stat(path.join(here, p))).size / 1024).toFixed(1) + ' KiB';

for (const w of warnings) console.log('⚠ ' + w);
console.log('OpenDir v' + version);
console.log('  root      ' + root);
console.log('  theme     ' + themePath + '/index.html   (URL ' + themeUrl + '/)');
console.log('  json      ' + jsonPrefix + '/   ?' + jsonArg + '=1');
console.log('  refresh   ' + (injected.refreshMs ? injected.refreshMs / 1000 + ' 秒' : '关闭'));
console.log('dist/theme.html   ' + (await kb('dist/theme.html')));
console.log('dist/index.html   ' + (await kb('dist/index.html')));
if (buildOpts.emitNginxConf !== false) console.log('dist/nginx.conf   ' + (await kb('dist/nginx.conf')));
if (buildOpts.emitPreview !== false) console.log('dist/preview.html ' + (await kb('dist/preview.html')));
if (buildOpts.emitDocker !== false) console.log('dist/docker/      index.html + config.js');
