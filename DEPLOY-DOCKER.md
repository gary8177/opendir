# 部署到 Linux 服务器的 Docker

场景：**Windows 上开发，Linux 服务器上用 Docker 跑**。服务器只要装好 Docker + Compose，
不需要 Node、PowerShell，也不需要仓库里的 `tools/`。

---

## 0. 传什么文件

| 方式 | 文件 | 说明 |
|---|---|---|
| **A. docker 专用包**（推荐） | `release/OpenDir-<ver>-docker.zip` | 只含 Dockerfile、`docker/`、`docker-compose.yml`、`dist/docker/`、`init-docker.sh`、`.env.example`，**已含构建好的页面**，服务器无需构建 |
| B. 完整发布包 | `release/OpenDir-<ver>.zip` | 还含源码、构建脚本、`.cmd`；服务器上同样能起 |

两个 zip 都在 Windows 侧用 `release.cmd`（或 `node release.mjs`）生成。

## 1. 上传解压

Windows：

```powershell
scp .\release\OpenDir-1.0.0-docker.zip user@服务器:/opt/
```

服务器：

```bash
cd /opt
unzip OpenDir-1.0.0-docker.zip
cd OpenDir-1.0.0
```

## 2. 准备文件目录

```bash
sudo mkdir -p /srv/files      # 放要分享的文件；容器以只读挂载
```

## 3. 初始化（写 .env）

```bash
sh init-docker.sh
```

向导会问：宿主机目录、容器内路径、端口、标题、刷新间隔、隐藏文件、内部前缀。
方括号里是当前值，**直接回车即保留**；重复运行不丢设置（旧文件备份成 `.env-backup-<时间戳>`）。
无交互条件时用 `sh init-docker.sh -y`，或直接手写 `.env`（最小三行）：

```ini
OPENDIR_HOST_DIR=/srv/files
OPENDIR_ROOT=/srv/files
OPENDIR_PORT_HOST=8080
```

## 4. 起容器

```bash
docker compose up -d --build
docker compose logs -f     # 启动摘要：files / theme / json / listen / refresh
```

首次会拉 `nginx:stable-alpine`。浏览器打开 `http://服务器IP:8080/` 即目录页。

## 5. 验收

```bash
curl -s  "http://127.0.0.1:8080/?raw=1" | head -c 200   # 应返回 JSON 数组
curl -sI "http://127.0.0.1:8080/"                       # 应 200 + text/html
curl -sI "http://127.0.0.1:8080/_raw/some-file"         # 应 404（数据面只放行目录）
```

## 6. 挂在已有 nginx 后面（HTTPS）

宿主机 nginx 已占 80/443 时，让容器只听内网端口再反代：

```nginx
server {
    listen 443 ssl http2;
    server_name pan.example.com;

    ssl_certificate     /etc/letsencrypt/live/pan.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pan.example.com/privkey.pem;

    client_max_body_size 0;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_buffering    off;
    }
}
```

⚠️ **不要挂在子路径**（如 `/files/`）：页面生成的链接是以 `/` 开头的绝对路径，
只支持独立域名或根路径。

## 7. 日常运维

```bash
docker compose up -d           # 改 .env 后重启生效（不必 --build）
docker compose logs -f
docker compose down
docker compose up -d --build   # 换新版本：重新上传 zip 覆盖后
```

## 8. 常见坑

| 现象 | 原因 | 处理 |
|---|---|---|
| `/bin/sh^M: bad interpreter` | 脚本被改成 CRLF | `sed -i 's/\r$//' init-docker.sh docker/entrypoint.sh` |
| 页面能开但提示「无法加载目录列表 (HTTP 404)」 | `OPENDIR_ROOT` 与挂载点不一致 | 看 `docker compose logs` 摘要里 `files:` 那行是否等于 volume 容器侧路径 |
| 列表为空 | 宿主机目录没内容 | 确认 `OPENDIR_HOST_DIR` 指向真实目录 |
| `unknown command: docker compose` | 只有旧版 docker-compose | 改用 `docker-compose up -d --build` 或装 Compose V2 |
| 拉不到基础镜像 | 服务器无外网 | 有网机器 `docker save nginx:stable-alpine -o nginx.tar` → 上传 → `docker load -i nginx.tar` |
| 端口被占 | 8080 已有服务 | 改 `.env` 的 `OPENDIR_PORT_HOST` 后 `docker compose up -d` |

## 9. 不想用 Docker？

服务器已有 nginx 时静态部署更轻：Windows 侧 `build.cmd` 生成 `dist/theme.html` 与 `dist/nginx.conf`，
传到 `/var/www/opendir/index.html` 与 `/etc/nginx/conf.d/`，然后 `nginx -t && nginx -s reload`。
配置走 `settings.json`（`init.ps1` 生成），与 Docker 版互不影响。
