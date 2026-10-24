#!/usr/bin/env node
/**
 * 打包发布，输出两个 zip 到 release/：
 *   OpenDir-<ver>.zip         完整包（源码 + 构建脚本 + Docker 文件 + dist 产物）
 *   OpenDir-<ver>-docker.zip  服务器专用包（只需 Dockerfile / docker/ / dist/docker/ / init-docker.sh）
 * 排除：tools/（便携工具链）、settings.local.json、.env、release/、*.log
 */
import { readFile, writeFile, mkdir, readdir, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import zlib from 'node:zlib';

const here = path.dirname(fileURLToPath(import.meta.url));
const version = (await readFile(path.join(here, 'VERSION'), 'utf8')).trim();
const rootName = 'OpenDir-' + version;

/* ---------------- 排除规则 ---------------- */
const SKIP_DIRS = new Set(['tools', 'release', '.git', 'node_modules']);
const SKIP_FILES = [/^settings\.local\.json$/, /^settings-backup-.*\.json$/, /^\.env$/, /^\.env-backup-/, /\.log$/, /^Thumbs\.db$/, /^\.DS_Store$/];

/* ---------------- CRC32 ---------------- */
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
const DOS_TIME = (d) => ((d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1)) & 0xffff;
const DOS_DATE = (d) => (((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate()) & 0xffff;

/* ---------------- 收集文件 ---------------- */
async function walk(dir, base = '') {
  const out = [];
  for (const e of (await readdir(dir, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
    const rel = base ? base + '/' + e.name : e.name;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (SKIP_DIRS.has(e.name)) continue;
      out.push(...(await walk(full, rel)));
    } else {
      if (SKIP_FILES.some((re) => re.test(e.name))) continue;
      out.push({ rel, full, st: await stat(full) });
    }
  }
  return out;
}

/* ---------------- 写 zip ---------------- */
async function makeZip(entries, outFile) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const f of entries) {
    const data = await readFile(f.full);
    const comp = zlib.deflateRawSync(data, { level: 9 });
    const nameBuf = Buffer.from(rootName + '/' + f.rel, 'utf8');
    const crc = crc32(data);
    const t = DOS_TIME(f.st.mtime);
    const d = DOS_DATE(f.st.mtime);

    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0);
    lh.writeUInt16LE(20, 4);
    lh.writeUInt16LE(0x0800, 6);
    lh.writeUInt16LE(8, 8);
    lh.writeUInt16LE(t, 10);
    lh.writeUInt16LE(d, 12);
    lh.writeUInt32LE(crc, 14);
    lh.writeUInt32LE(comp.length, 18);
    lh.writeUInt32LE(data.length, 22);
    lh.writeUInt16LE(nameBuf.length, 26);
    lh.writeUInt16LE(0, 28);
    locals.push(lh, nameBuf, comp);

    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0);
    ch.writeUInt16LE(20, 4);
    ch.writeUInt16LE(20, 6);
    ch.writeUInt16LE(0x0800, 8);
    ch.writeUInt16LE(8, 10);
    ch.writeUInt16LE(t, 12);
    ch.writeUInt16LE(d, 14);
    ch.writeUInt32LE(crc, 16);
    ch.writeUInt32LE(comp.length, 20);
    ch.writeUInt32LE(data.length, 24);
    ch.writeUInt16LE(nameBuf.length, 28);
    ch.writeUInt32LE(0, 38);
    ch.writeUInt32LE(offset, 42);
    centrals.push(ch, nameBuf);

    offset += lh.length + nameBuf.length + comp.length;
  }
  const centralBuf = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralBuf.length, 12);
  eocd.writeUInt32LE(offset, 16);
  const zip = Buffer.concat([...locals, centralBuf, eocd]);
  await mkdir(path.dirname(outFile), { recursive: true });
  await writeFile(outFile, zip);
  return zip.length;
}

/* ---------------- 开始 ---------------- */
const all = await walk(here);
if (!all.length) throw new Error('没有可打包的文件');

const BUNDLE = [
  /^Dockerfile$/,
  /^docker-compose\.yml$/,
  /^docker\//,
  /^dist\/docker\//,
  /^init-docker\.sh$/,
  /^\.env\.example$/,
  /^README\.md$/,
  /^DEPLOY-DOCKER\.md$/,
  /^LICENSE$/,
  /^VERSION$/,
  /^CHANGELOG\.md$/
];
const bundleFiles = all.filter((f) => BUNDLE.some((re) => re.test(f.rel)));

const kb = (n) => (n / 1024).toFixed(1) + ' KiB';
const fullSize = await makeZip(all, path.join(here, 'release', rootName + '.zip'));
const bundleSize = await makeZip(bundleFiles, path.join(here, 'release', rootName + '-docker.zip'));

console.log('OpenDir v' + version + ' 发布包');
console.log('  ' + rootName + '.zip          ' + kb(fullSize).padStart(9) + '   ' + all.length + ' 个文件（完整）');
console.log('  ' + rootName + '-docker.zip   ' + kb(bundleSize).padStart(9) + '   ' + bundleFiles.length + ' 个文件（Linux 服务器用）');
console.log('  已排除  tools/ · settings.local.json · .env · release/ · *.log');
