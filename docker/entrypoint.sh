#!/bin/sh
# =============================================================================
#  OpenDir —— 容器启动时把所有设置从环境变量注入（镜像里不含 node / PowerShell）
#  由 nginx 官方镜像的 /docker-entrypoint.d/ 机制在 nginx 启动前执行
# =============================================================================
set -eu

: "${OPENDIR_ROOT:=/srv/files}"
: "${OPENDIR_LISTEN:=80}"
: "${OPENDIR_SERVER_NAME:=_}"
: "${OPENDIR_THEME_URL:=/_opendir}"
: "${OPENDIR_THEME_PATH:=/usr/share/nginx/html/_opendir}"
: "${OPENDIR_JSON_PREFIX:=/_raw}"
: "${OPENDIR_JSON_ARG:=raw}"
: "${OPENDIR_REFRESH_MS:=120000}"
: "${OPENDIR_BRAND:=OpenDir}"
: "${OPENDIR_ROOT_LABEL:=根目录}"
: "${OPENDIR_SHOW_HIDDEN:=true}"
: "${OPENDIR_API_BASE:=}"
: "${OPENDIR_VERSION:=1.0.0}"

export OPENDIR_ROOT OPENDIR_LISTEN OPENDIR_SERVER_NAME OPENDIR_THEME_URL OPENDIR_THEME_PATH
export OPENDIR_JSON_PREFIX OPENDIR_JSON_ARG OPENDIR_REFRESH_MS OPENDIR_BRAND
export OPENDIR_ROOT_LABEL OPENDIR_SHOW_HIDDEN OPENDIR_API_BASE OPENDIR_VERSION

# --- 规整取值 ---
case "$OPENDIR_REFRESH_MS" in
  ''|*[!0-9]*) echo "[opendir] OPENDIR_REFRESH_MS 不是数字，回退 120000"; OPENDIR_REFRESH_MS=120000 ;;
esac
case "$OPENDIR_SHOW_HIDDEN" in
  1|true|yes|on|TRUE|True) OPENDIR_SHOW_HIDDEN=true ;;
  *) OPENDIR_SHOW_HIDDEN=false ;;
esac
OPENDIR_THEME_URL="/$(printf '%s' "$OPENDIR_THEME_URL" | sed -e 's|^/*||' -e 's|/*$||')"
OPENDIR_JSON_PREFIX="/$(printf '%s' "$OPENDIR_JSON_PREFIX" | sed -e 's|^/*||' -e 's|/*$||')"
OPENDIR_ROOT="$(printf '%s' "$OPENDIR_ROOT" | sed -e 's|/*$||')"
OPENDIR_THEME_PATH="$(printf '%s' "$OPENDIR_THEME_PATH" | sed -e 's|/*$||')"

# --- 1. 渲染 nginx 站点配置（只替换 OPENDIR_* 这些变量）---
if ! command -v envsubst >/dev/null 2>&1; then
  echo "[opendir] 错误：镜像里没有 envsubst，无法渲染配置" >&2
  exit 1
fi
VARLIST='${OPENDIR_LISTEN} ${OPENDIR_SERVER_NAME} ${OPENDIR_ROOT} ${OPENDIR_THEME_URL} ${OPENDIR_THEME_PATH} ${OPENDIR_JSON_PREFIX} ${OPENDIR_JSON_ARG}'
envsubst "$VARLIST" < /opt/opendir/nginx.conf.template > /etc/nginx/conf.d/opendir.conf

# --- 2. 生成页面配置 config.js ---
dq() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
mkdir -p "$OPENDIR_THEME_PATH"
cat > "$OPENDIR_THEME_PATH/config.js" <<EOF
window.OPENDIR_CONFIG = {
  "version": "$(dq "$OPENDIR_VERSION")",
  "refreshMs": $OPENDIR_REFRESH_MS,
  "jsonArg": "$(dq "$OPENDIR_JSON_ARG")",
  "apiBase": "$(dq "$OPENDIR_API_BASE")",
  "showHidden": $OPENDIR_SHOW_HIDDEN,
  "brand": "$(dq "$OPENDIR_BRAND")",
  "rootLabel": "$(dq "$OPENDIR_ROOT_LABEL")"
};
EOF

# --- 3. 外壳页面：把 config.js 的占位地址换成真实前缀 ---
sed "s|__OPENDIR_CONFIG_JS__|$OPENDIR_THEME_URL/config.js|" \
  /opt/opendir/index.html > "$OPENDIR_THEME_PATH/index.html"

# --- 4. 启动摘要 ---
echo "==================== OpenDir $OPENDIR_VERSION ===================="
echo "  files   : $OPENDIR_ROOT"
echo "  theme   : $OPENDIR_THEME_URL/  ->  $OPENDIR_THEME_PATH/"
echo "  json    : $OPENDIR_JSON_PREFIX/   ?$OPENDIR_JSON_ARG=1"
echo "  listen  : $OPENDIR_LISTEN   server_name: $OPENDIR_SERVER_NAME"
echo "  refresh : $OPENDIR_REFRESH_MS ms   brand: $OPENDIR_BRAND"
if [ ! -d "$OPENDIR_ROOT" ]; then
  echo "  [warn] 文件目录 $OPENDIR_ROOT 不存在，请把 volume 挂到这个路径" >&2
fi
echo "================================================================"
