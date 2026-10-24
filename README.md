# OpenDir · 极简目录页

> 把 nginx 自带的「白底黑字目录列表」换成一张干净的表 —— 纯静态单文件，零后端，配置可持久化。

```
数据由 nginx 的 autoindex_format json 提供  →  前端每 2 分钟静默重新渲染  →  丢文件即生效
```

**版本 1.0.0** · MIT · 无需数据库 / 无需构建服务 / 单文件 30 KB

三种用法，按需挑一个：

| 场景 | 一句话 | 跳到 |
|---|---|---|
| **Docker**（推荐） | `git clone` 后 `docker compose up -d --build`，全环境变量配置 | [30 秒上手](#30-秒上手docker) |
| 已有 nginx 的服务器 | 拷一个 `theme.html` + 一段 nginx 配置上去 | [静态部署](#a-静态部署到已有-nginx) |
| 本机先看效果 | 双击 `dist/preview.html`（内置演示数据），或跑便携 nginx | [本机试跑](#b-windows-本机试跑) |

---

## 这是什么

浏览器读不了服务器目录，所以目录数据仍然由 nginx 给：

1. 目录请求（`/电影/`）没有索引文件 → nginx 返回 403 → `error_page 403` 把本项目的静态外壳顶上去，**浏览器 URL 不变**；
2. 外壳里的 JS 请求 `/电影/?raw=1` → 被 `rewrite` 改写到内部数据面 `/_raw/电影/` → `alias` + `autoindex_format json` 吐出目录 JSON；
3. 前端渲染成表格，并每 2 分钟静默重取一次。

所以：**没有扫盘、没有索引文件、没有后台进程**，把文件扔进目录，下一分钟页面上就有了。

## 特性

| | |
|---|---|
| 目录即数据 | 直接消费 `autoindex_format json`，放文件即生效，不用重新生成索引 |
| 自动刷新 | 默认 2 分钟（可改可关）；标签页在后台时暂停，切回来若已超时立即补刷 |
| 不闪 | 数据没变化就不重建 DOM，滚动位置和焦点都不丢 |
| 交互 | 搜索筛选（`/` 聚焦、`Esc` 清空）· 点表头排序（名称/大小/时间，目录恒在前）· 面包屑 · 上一级 |
| 图标 | 按扩展名区分 9 类：图片 / 视频 / 音频 / 压缩包 / 镜像 / 代码 / 文档 / 程序 / 字体 |
| 深浅色 | 跟随系统 / 浅 / 深，三态循环，记在本地 |
| 设置持久化 | 构建期写在 `settings.json`；页面偏好（刷新间隔、隐藏文件、排序、主题）存在浏览器 `localStorage` |
| 单文件部署 | CSS/JS 全部内联，`theme.html` 一个文件就是全部前端 |
| Docker 友好 | 镜像基于 `nginx:stable-alpine`，**不含任何构建工具**，全部设置走环境变量 |

## 30 秒上手（Docker）

```bash
git clone https://github.com/<你的用户名>/OpenDir.git
cd OpenDir

# 1) 放要分享的文件（容器只读挂载）
mkdir -p ./files

# 2) 配置（可跳过，全有默认值；生成 .env 的交互脚本见下）
cp .env.example .env && $EDITOR .env

# 3) 起
docker compose up -d --build
docker compose logs -f          # 启动摘要：files / theme / json / listen
```

打开 `http://127.0.0.1:8080/` 即可。仓库里已包含构建好的 `dist/docker/index.html`，**克隆后不需要 Node**。

最小 `.env` 只要三行：

```ini
OPENDIR_HOST_DIR=./files      # 宿主机目录
OPENDIR_ROOT=/srv/files       # 容器内路径
OPENDIR_PORT_HOST=8080        # 宿主机端口
```

交互式生成 `.env`：Linux / macOS 用 `sh init-docker.sh`，Windows 用 `init-docker.cmd`。
两者都是「方括号里是当前值，直接回车即保留」，重复运行不会丢设置（旧文件备份成 `.env-backup-<时间戳>`）。

完整部署步骤（上传、反代、HTTPS、排错）见 **[DEPLOY-DOCKER.md](DEPLOY-DOCKER.md)**。

## A. 静态部署到已有 nginx

前提：服务器上已有 nginx，并且愿意多一段 `server { }`。

```powershell
# Windows 侧：初始化设置 + 构建
powershell -ExecutionPolicy Bypass -File init.ps1   # 问：文件目录 / 域名 / 端口 / 刷新间隔…
.\build.cmd                                        # 生成 dist/theme.html 与 dist/nginx.conf
```

```bash
# 传到服务器
install -D dist/theme.html /var/www/opendir/index.html
install -D dist/nginx.conf  /etc/nginx/conf.d/opendir.conf
nginx -t && nginx -s reload
```

配置只改 `settings.json`，然后 `build.cmd` 重新生成 —— nginx 里那段配置是**生成的**，别手改。

## B. Windows 本机试跑

**不想装任何东西**：双击 `dist/preview.html`（内置演示数据，纯前端效果）。
**想跑真实的目录**：需要 nginx，两种方式——

- 装了 Docker：直接走上面的 Docker 路线；
- 想要绿色便携版：把 node + nginx 解压到 `tools/`（该目录不入库），再双击 `run-dev.cmd` —— 它会「构建 → 同步配置 → 起 nginx → 开浏览器 → 按任意键停止」。`tools/env.cmd` 可以开一个已把 node/nginx 加进 PATH 的 shell。

## 配置

### settings.json（构建期，静态部署用）

`init.ps1` 生成，也可以手改后重跑 `build.cmd`；再次运行 `init.ps1` 会以现值为默认值。

| 字段 | 默认 | 说明 |
|---|---|---|
| `server.root` | `/srv/files` | **文件根目录**（服务器真实路径） |
| `server.themePath` | `/var/www/opendir` | 主题安装目录（放 index.html，建议在 root 之外） |
| `server.themeUrl` | `/_opendir` | 主题的 URL 前缀 |
| `server.jsonPrefix` | `/_raw` | 目录 JSON 的内部前缀 |
| `server.jsonArg` | `raw` | JSON 查询参数名（`raw` → `?raw=1`） |
| `server.listen` / `server.serverName` | `80` / `pan.example.com` | nginx 监听与域名 |
| `ui.refreshMs` | `120000` | 自动刷新间隔（毫秒），`0` = 关闭 |
| `ui.showHidden` | `true` | 默认是否显示 `.` 开头的文件 |
| `ui.brand` / `ui.rootLabel` | `OpenDir` / `根目录` | 标题 / 面包屑根文案 |
| `ui.apiBase` | 空 | 独立 JSON 端点前缀（跨域方案） |

想保留一套本机调试配置：复制成 `settings.local.json`（已 gitignore），用
`build-local.cmd` 或 `set OPENDIR_SETTINGS=settings.local.json` 构建。

### Docker 环境变量

| 变量 | 默认 | 变量 | 默认 |
|---|---|---|---|
| `OPENDIR_ROOT` | `/srv/files` | `OPENDIR_REFRESH_MS` | `120000` |
| `OPENDIR_HOST_DIR` | `./files` | `OPENDIR_BRAND` | `OpenDir` |
| `OPENDIR_PORT_HOST` / `OPENDIR_LISTEN` | `8080` / `80` | `OPENDIR_ROOT_LABEL` | `根目录` |
| `OPENDIR_SERVER_NAME` | `_` | `OPENDIR_SHOW_HIDDEN` | `true` |
| `OPENDIR_THEME_URL` | `/_opendir` | `OPENDIR_JSON_ARG` | `raw` |
| `OPENDIR_JSON_PREFIX` | `/_raw` | `OPENDIR_API_BASE` | 空 |

改完 `docker compose up -d` 生效（不必 `--build`）。

### 页面内设置（浏览器侧）

右上角 ⚙：自动刷新间隔、是否显示隐藏文件；深浅色与表格排序也会记住。
全部存在 `localStorage`（键 `opendir-prefs`），「恢复默认」清回构建期默认值。
注意这些偏好**只影响你自己的浏览器**；要让所有访客默认关掉自动刷新，改配置后重新构建。

## 交互速查

| 操作 | 效果 |
|---|---|
| `/` | 聚焦搜索框 |
| `Esc` | 清空搜索 / 关闭设置面板 |
| 点表头 | 按名称·大小·时间排序，再点反向；目录恒在最前 |
| ⟳ | 立即刷新 |
| ◑ | 跟随系统 → 浅色 → 深色 |
| 底栏 | 条目数、总大小、最后更新时间、下次刷新倒计时 |

## nginx 注意事项（踩坑记录）

- **`alias` 不能和 `try_files` 混用**：`try_files` 拼的是完整 URI，会得到 `/srv/files/_raw/电影/电影/` 这类鬼路径。数据面只用 `alias`。
- `index __opendir_none__;` 是故意的：即使目录里有 `index.html`，也要让「403 → 外壳」生效。副作用是**真实文件**若因权限返回 403，也会显示成目录页。
- 数据面加了 `if ($uri !~ /$) { return 404; }`，只放行目录，避免借 `/_raw/` 前缀下载文件。
- 数据面固定 `Cache-Control: no-store`；外壳可以缓存（Docker 版用 no-store，方便改环境变量即时生效）。
- 中文名 / 空格 / `#` 都不用额外处理：JSON 是原始 UTF-8，链接由前端 `encodeURIComponent` 生成。
- error.log 里每次进新目录会有一条 `directory index ... is forbidden` —— 那是**设计**（401/403 就是切换信号），不是故障。

## 目录结构

```
OpenDir/
├─ src/                  页面源码：index.html · style.css · app.js · demo-catalog.json
├─ dist/                 构建产物
│  ├─ theme.html         部署用单文件（静态部署拷这个）
│  ├─ nginx.conf         填好路径的 nginx 片段
│  ├─ preview.html       演示数据预览（双击即看）
│  └─ docker/            index.html + config.js（**入库**，让 clone 后无需 Node 就能 docker build）
├─ Dockerfile            nginx:stable-alpine，无任何构建工具
├─ docker/               entrypoint.sh（环境变量 → 配置）· nginx.conf.template
├─ docker-compose.yml    compose 示例（读 .env，有默认值）
├─ init.ps1              静态部署初始化 → settings.json
├─ init-docker.sh/.cmd    Docker 初始化 → .env（Linux / Windows）
├─ build.cmd / .mjs / .ps1  构建（cmd 会优先用 tools\node，退回 PowerShell）
├─ build-local.cmd       用 settings.local.json 构建
├─ run-dev.cmd           便携 nginx 一键起站（需要 tools/）
├─ docker-up/down/logs.cmd  Docker 快捷操作（Windows）
├─ deploy-docker.cmd     上传 docker 包到服务器（scp + ssh）
├─ release.cmd / .mjs    打发布包
├─ nginx.conf.tpl        nginx 片段模板（占位符由构建填充）
├─ DEPLOY-DOCKER.md      部署到 Linux 服务器的完整步骤
└─ settings.json / .env.example / VERSION / CHANGELOG.md / LICENSE
```

不入库：`tools/`（便携 node+nginx，约 110 MiB）、`settings.local.json`、`.env`、`release/`。

## 开发与打包

```powershell
# 只构建（优先用 tools\node\node.exe，没有则退回 PowerShell 版）
.\build.cmd
node build.mjs            # 有 Node 时的等价命令

# 打发布包 → release/ 下两个 zip
.\release.cmd
```

| 产物 | 内容 |
|---|---|
| `release/OpenDir-<ver>.zip` | 全部源码 + 构建脚本 + Docker 文件 + `dist/` |
| `release/OpenDir-<ver>-docker.zip` | 只含服务器所需：`Dockerfile`、`docker/`、`docker-compose.yml`、`dist/docker/`、`init-docker.sh`、`.env.example`、`DEPLOY-DOCKER.md`、README |

改过 `src/` 之后记得重新 `build.cmd` 并提交 `dist/docker/`，否则从零 `docker build` 会拿不到页面。

## 常见问题

**Q：能不能不用 nginx，纯前端读目录？**
不能，浏览器没有读服务器目录的能力。本项目的前提是「nginx 愿意吐目录 JSON」。

**Q：和 pan.zsh.moe（Ngindex）有什么区别？**
Ngindex 预先生成整站 `catalog.json`，前端一次拉全站索引——请求少，但要构建步骤。
本项目每个目录现取现渲染，放文件即生效，不用扫盘。

**Q：改了 .ps1 之后报「意外的标记」/中文乱码？**
Windows PowerShell 5.1 会按 ANSI 解码没有 BOM 的脚本。`init.ps1` / `init-docker.ps1` 必须存成 **UTF-8 with BOM**（仓库里的已经是）；`.sh` 必须保持 LF，`.gitattributes` 已锁定换行符。

**Q：Docker 版页面提示「无法加载目录列表 (HTTP 404)」？**
`OPENDIR_ROOT` 和 volume 的容器侧路径不一致。看 `docker compose logs` 的启动摘要里 `files:` 那行。

**Q：怎么只让某些文件可见？**
把不该公开的放到 `root` 之外，或用 nginx 的 `location` 规则挡住。

## License

MIT
