# =============================================================================
#  OpenDir —— 极简目录页（Docker 版）
#  镜像里只有 nginx 基础镜像 + 构建好的单文件页面，不含 node、不含便携工具；
#  所有站点设置通过环境变量在容器启动时注入（见 docker/entrypoint.sh）。
# =============================================================================
FROM nginx:stable-alpine

LABEL org.opencontainers.image.title="OpenDir" \
      org.opencontainers.image.description="Minimal file listing UI for nginx autoindex (JSON)" \
      org.opencontainers.image.licenses="MIT"

# 构建产物：先在宿主机跑 build.cmd / build.mjs 生成 dist/docker/
COPY dist/docker/index.html /opt/opendir/index.html
COPY docker/nginx.conf.template /opt/opendir/nginx.conf.template
COPY docker/entrypoint.sh /docker-entrypoint.d/50-opendir-config.sh

RUN chmod +x /docker-entrypoint.d/50-opendir-config.sh \
 && rm -f /etc/nginx/conf.d/default.conf \
 && mkdir -p /usr/share/nginx/html/_opendir /srv/files

# ---- 默认设置（全部可用 -e / compose environment 覆盖）----
ENV OPENDIR_ROOT=/srv/files \
    OPENDIR_LISTEN=80 \
    OPENDIR_SERVER_NAME=_ \
    OPENDIR_THEME_URL=/_opendir \
    OPENDIR_THEME_PATH=/usr/share/nginx/html/_opendir \
    OPENDIR_JSON_PREFIX=/_raw \
    OPENDIR_JSON_ARG=raw \
    OPENDIR_REFRESH_MS=120000 \
    OPENDIR_BRAND=OpenDir \
    OPENDIR_ROOT_LABEL=根目录 \
    OPENDIR_SHOW_HIDDEN=true \
    OPENDIR_API_BASE=

EXPOSE 80
VOLUME ["/srv/files"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -q --spider "http://127.0.0.1:${OPENDIR_LISTEN}/" || exit 1

# 官方镜像自带 CMD ["nginx", "-g", "daemon off;"]
