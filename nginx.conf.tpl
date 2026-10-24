# =============================================================================
#  OpenDir 生成的 nginx 配置   v{{VERSION}}
#    · 页面外壳：{{THEME_PATH}}/index.html
#    · 目录数据：autoindex_format json（内部前缀 {{JSON_PREFIX}}/）
#  ⚠ 本文件由 build 从 nginx.conf.tpl 生成，改配置请编辑 settings.json 后重新 build。
#  放在哪：Linux → /etc/nginx/conf.d/opendir.conf（自动被 include）
#          Windows → nginx\conf\opendir.conf，并在 nginx.conf 的 http{} 里加一行 include opendir.conf;
# =============================================================================

server {
    listen      {{LISTEN}};
    server_name {{SERVER_NAME}};

    root  {{ROOT}};
    charset utf-8;

    # 目录 JSON / 单页 HTML 都很吃压缩，开 gzip
    gzip            on;
    gzip_min_length 1024;
    gzip_comp_level 5;
    gzip_vary       on;
    gzip_types      application/json text/css application/javascript image/svg+xml text/plain;

    autoindex off;              # 不用 nginx 自带的 HTML 目录页
    index __opendir_none__;        # 故意指向不存在的文件：目录请求必然走不到索引文件，
                                # 从而落到下面的 403 → 外壳渲染

    # ---------------------------------------------------------------------
    # 1) 页面外壳（单文件，CSS/JS 已内联）
    #    放在文件根目录之外，这样它不会出现在文件列表里
    # ---------------------------------------------------------------------
    location = {{THEME_URL}}/index.html {
        alias {{THEME_PATH}}/index.html;
        add_header Cache-Control "public, max-age=300";
    }

    # ---------------------------------------------------------------------
    # 2) 目录请求
    #    · 目录且没有索引文件 → nginx 返回 403 → 换成外壳页面（HTTP 200）
    #    · 带 ?{{JSON_ARG}}=1 的请求 → 重写到数据面 {{JSON_PREFIX}}/ 拿 JSON
    # ---------------------------------------------------------------------
    location / {
        error_page 403 =200 {{THEME_URL}}/index.html;

        if ($arg_{{JSON_ARG}}) {
            rewrite ^ {{JSON_PREFIX}}$uri last;
        }
    }

    # ---------------------------------------------------------------------
    # 3) 数据面：alias 到同一棵目录树，只输出 JSON，只放行目录
    #    GET {{JSON_PREFIX}}/some/dir/?{{JSON_ARG}}=1
    #    → [{"name":"..","type":"file","mtime":"...","size":123}, ...]
    # ---------------------------------------------------------------------
    location {{JSON_PREFIX}}/ {
        alias {{ROOT}}/;                    # 结尾斜杠必须有
        autoindex on;
        autoindex_format json;
        autoindex_exact_size off;
        autoindex_localtime off;            # mtime 输出 GMT，浏览器自己转本地时区
        add_header Cache-Control "no-store";

        # 只放行目录（URI 必须以 / 结尾），避免借这个前缀直接下载文件
        if ($uri !~ /$) {
            return 404;
        }
    }
}
