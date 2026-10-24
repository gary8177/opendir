#!/bin/sh
# =============================================================================
#  OpenDir —— Docker 版初始化（Linux / macOS，交互写 .env）
#  用法： sh init-docker.sh        或  sh init-docker.sh -y（全部取默认值）
# =============================================================================
set -eu

here=$(cd "$(dirname "$0")" && pwd)
cd "$here"
envfile=".env"

ACCEPT_DEFAULTS=0
if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]; then
  ACCEPT_DEFAULTS=1
fi

# ---- 默认值（与 docker-compose.yml 缺省一致）----
HOST_DIR="./files"
ROOT="/srv/files"
PORT_HOST="8080"
LISTEN="80"
SERVER_NAME="_"
BRAND="OpenDir"
ROOT_LABEL="根目录"
REFRESH_MS="120000"
SHOW_HIDDEN="true"
THEME_URL="/_opendir"
JSON_PREFIX="/_raw"
JSON_ARG="raw"
API_BASE=""
IMAGE="opendir:1.0.0"
CONTAINER="opendir"

# ---- 已有 .env → 用现值当默认值 ----
if [ -f "$envfile" ]; then
  echo "检测到已有 .env，本次以现有值为默认值（直接回车即保留）。"
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|\#*) continue ;; esac
    key=${line%%=*}
    val=${line#*=}
    val=$(printf '%s' "$val" | sed -e 's/^"//' -e 's/"$//')
    case $key in
      OPENDIR_HOST_DIR)    HOST_DIR=$val ;;
      OPENDIR_ROOT)        ROOT=$val ;;
      OPENDIR_PORT_HOST)   PORT_HOST=$val ;;
      OPENDIR_LISTEN)      LISTEN=$val ;;
      OPENDIR_SERVER_NAME) SERVER_NAME=$val ;;
      OPENDIR_BRAND)       BRAND=$val ;;
      OPENDIR_ROOT_LABEL)  ROOT_LABEL=$val ;;
      OPENDIR_REFRESH_MS)  REFRESH_MS=$val ;;
      OPENDIR_SHOW_HIDDEN) SHOW_HIDDEN=$val ;;
      OPENDIR_THEME_URL)   THEME_URL=$val ;;
      OPENDIR_JSON_PREFIX) JSON_PREFIX=$val ;;
      OPENDIR_JSON_ARG)    JSON_ARG=$val ;;
      OPENDIR_API_BASE)    API_BASE=$val ;;
      OPENDIR_IMAGE)       IMAGE=$val ;;
      OPENDIR_CONTAINER)   CONTAINER=$val ;;
    esac
  done < "$envfile"
fi

ask() { # 标签 当前值 → 输出取值
  if [ "$ACCEPT_DEFAULTS" = "1" ]; then printf '%s' "$2"; return 0; fi
  printf '%s [%s]: ' "$1" "$2" >&2
  IFS= read -r ans || ans=""
  if [ -z "$ans" ]; then printf '%s' "$2"; else printf '%s' "$ans"; fi
}

ask_num() { # 标签 当前值 最小 最大
  cur=$2
  while :; do
    v=$(ask "$1" "$cur")
    case $v in
      ''|*[!0-9]*) ;;
      *)
        if [ "$v" -ge "$3" ] && [ "$v" -le "$4" ]; then printf '%s' "$v"; return 0; fi
        ;;
    esac
    echo "  需要 $3 ~ $4 之间的整数" >&2
    if [ "$ACCEPT_DEFAULTS" = "1" ]; then printf '%s' "$cur"; return 0; fi
  done
}

ask_bool() { # 标签 当前值(true/false)
  cur=$2
  if [ "$cur" = "true" ]; then def="Y"; else def="N"; fi
  if [ "$ACCEPT_DEFAULTS" = "1" ]; then printf '%s' "$2"; return 0; fi
  printf '%s [Y/N，默认 %s]: ' "$1" "$def" >&2
  IFS= read -r ans || ans=""
  case $(printf '%s' "$ans" | tr 'A-Z' 'a-z') in
    '') printf '%s' "$cur" ;;
    y|yes|1|true) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

q() { # 给 .env 的值加双引号并转义反斜杠/引号
  printf '"%s"' "$(printf '%s' "$1" | sed -e 's/[\\"]/\\&/g')"
}

echo ""
echo "== OpenDir Docker 初始化 =="
echo "（方括号里是默认值，直接回车表示保留）"
echo ""
echo "-- 文件目录 --"
HOST_DIR=$(ask "宿主机上放文件的目录" "$HOST_DIR")
ROOT=$(ask "容器内对应路径" "$ROOT")
echo ""
echo "-- 端口 --"
PORT_HOST=$(ask_num "宿主机端口" "$PORT_HOST" 1 65535)
LISTEN=$(ask_num "容器内监听端口" "$LISTEN" 1 65535)
echo ""
echo "-- 站点 --"
SERVER_NAME=$(ask "server_name（_ 表示匹配所有域名）" "$SERVER_NAME")
BRAND=$(ask "站点标题" "$BRAND")
ROOT_LABEL=$(ask "面包屑根节点文案" "$ROOT_LABEL")
cur_sec=$((REFRESH_MS / 1000))
sec=$(ask_num "自动刷新间隔（秒，0 = 关闭）" "$cur_sec" 0 3600)
REFRESH_MS=$((sec * 1000))
SHOW_HIDDEN=$(ask_bool "默认显示 . 开头的隐藏文件" "$SHOW_HIDDEN")
echo ""
echo "-- 高级（一般直接回车）--"
THEME_URL=$(ask "页面外壳 URL 前缀" "$THEME_URL")
JSON_PREFIX=$(ask "目录 JSON 内部前缀" "$JSON_PREFIX")
JSON_ARG=$(ask "目录 JSON 查询参数名" "$JSON_ARG")
API_BASE=$(ask "独立 JSON 端点（留空 = 同站）" "$API_BASE")
IMAGE=$(ask "镜像标签" "$IMAGE")
CONTAINER=$(ask "容器名" "$CONTAINER")
echo ""

if [ -f "$envfile" ]; then
  backup=".env-backup-$(date +%Y%m%d-%H%M%S)"
  cp "$envfile" "$backup"
  echo "已备份原 .env：$backup"
fi

{
  echo '# OpenDir —— Docker 版设置（由 init-docker.sh 生成，compose 会自动读取）'
  echo '# 宿主机上放文件的目录'
  echo "OPENDIR_HOST_DIR=$(q "$HOST_DIR")"
  echo '# 容器内对应路径'
  echo "OPENDIR_ROOT=$(q "$ROOT")"
  echo '# 端口：宿主机 : 容器'
  echo "OPENDIR_PORT_HOST=$(q "$PORT_HOST")"
  echo "OPENDIR_LISTEN=$(q "$LISTEN")"
  echo "OPENDIR_SERVER_NAME=$(q "$SERVER_NAME")"
  echo '# 页面'
  echo "OPENDIR_BRAND=$(q "$BRAND")"
  echo "OPENDIR_ROOT_LABEL=$(q "$ROOT_LABEL")"
  echo "OPENDIR_REFRESH_MS=$(q "$REFRESH_MS")"
  echo "OPENDIR_SHOW_HIDDEN=$(q "$SHOW_HIDDEN")"
  echo '# 内部前缀'
  echo "OPENDIR_THEME_URL=$(q "$THEME_URL")"
  echo "OPENDIR_JSON_PREFIX=$(q "$JSON_PREFIX")"
  echo "OPENDIR_JSON_ARG=$(q "$JSON_ARG")"
  echo "OPENDIR_API_BASE=$(q "$API_BASE")"
  echo '# 镜像'
  echo "OPENDIR_IMAGE=$(q "$IMAGE")"
  echo "OPENDIR_CONTAINER=$(q "$CONTAINER")"
} > "$envfile"

echo "已写入 .env："
cat "$envfile"
echo ""

if [ ! -f "dist/docker/index.html" ]; then
  echo "警告：没有 dist/docker/index.html，镜像构建会失败。" >&2
  echo "      请用 OpenDir-<ver>-docker.zip（已包含构建产物），或在 Windows 侧先跑 build.cmd" >&2
  echo "" >&2
fi

if [ ! -d "$HOST_DIR" ]; then
  echo "提醒：宿主机目录 $HOST_DIR 还不存在，容器里的 /srv/files 会是空的。" >&2
  echo "" >&2
fi

echo "接下来："
echo "  docker compose up -d --build"
echo "  浏览器打开 http://<服务器IP>:$PORT_HOST/"
echo ""

if [ "$ACCEPT_DEFAULTS" = "0" ]; then
  printf '现在构建镜像并启动吗？[y/N]: '
  IFS= read -r go || go=""
  case $(printf '%s' "$go" | tr 'A-Z' 'a-z') in
    y|yes) docker compose up -d --build ;;
    *) echo "稍后手动执行： docker compose up -d --build" ;;
  esac
fi
