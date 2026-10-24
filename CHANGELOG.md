# Changelog

## 1.0.0 — 2026-10-24

首个发布版本。

### 页面

- 纯静态单文件页（CSS/JS 内联），数据来自 nginx `autoindex_format json`
- 每 2 分钟静默刷新索引（可关、可调），标签页在后台时暂停、切回补刷
- 数据无变化时不重建 DOM，滚动位置与焦点不丢
- 搜索筛选（`/` 聚焦、`Esc` 清空）、表头排序（名称/大小/时间，目录恒在前）
- 面包屑 + 上一级、按扩展名区分 9 类图标、深浅色三态
- 内联 SVG favicon（不产生 `/favicon.ico` 404）

### 配置

- `init.ps1` 交互式初始化 → `settings.json`（构建期持久化，重跑以现值为默认）
- 页面偏好（刷新间隔 / 隐藏文件 / 排序 / 主题）持久化在浏览器 `localStorage`
- Windows 路径自动转正斜杠，相对路径会告警
- `OPENDIR_SETTINGS` 环境变量可指定另一份配置（例如 `settings.local.json`）

### 部署

- 单文件 + nginx 片段：`dist/theme.html` + `dist/nginx.conf`
- 便携工具链：`tools/`（Node + nginx 二进制，不入库），`run-dev.cmd` 一键本地起站
- Docker：`nginx:stable-alpine` 基础镜像，**不含任何构建工具**，全部设置由环境变量在启动时注入
- 打包：`release.mjs` / `release.cmd` → `release/OpenDir-<version>.zip`

### 已知取舍

- 目录请求依赖「无索引文件 → 403 → `error_page` 换页」这一机制，因此 error.log 里每次进入新目录会留一条
  `directory index ... is forbidden`（设计使然，不是故障）
- 真实文件若因权限返回 403，也会显示成目录页
