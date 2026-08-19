# REF.md

プロジェクト中に参照した一次資料へのリンクと、参照した判断をまとめる。

## 課題

- [Inception subject v5.3](./en.subject_inception.pdf)（プロジェクト同梱）

## 2026-08-19 — 実行環境とベースイメージ

- [Alpine Linux release branches](https://www.alpinelinux.org/releases/)
  - 最新安定系列は v3.24、penultimate stable は v3.23。コンテナの `FROM` は `alpine:3.23` とする。
- [Docker Desktop: WSL 2 backend on Windows](https://docs.docker.com/desktop/features/wsl/)
  - Docker Desktop の WSL 2 engine と、対象ディストリビューションの WSL Integration を有効化する。
- [Docker Desktop: Develop with Docker Desktop using WSL 2](https://docs.docker.com/desktop/features/wsl/use-wsl/)
  - 開発ソースは WSL の Linux ファイルシステム側に置く方針の根拠。

## 2026-08-19 — Phase 3 MariaDB

- [Alpine Linux: MariaDB](https://wiki.alpinelinux.org/wiki/MariaDB)
  - Alpine では `mariadb` と `mariadb-client` を導入し、データディレクトリを `mariadb-install-db --user=mysql --datadir=/var/lib/mysql` で初期化する。
  - `/etc/my.cnf.d/` の設定ファイルで `bind-address` などを変更できる。
- [Alpine package index: mariadb-client v3.23](https://pkgs.alpinelinux.org/packages?branch=v3.23&name=mariadb-client)
  - Alpine 3.23 の x86_64 パッケージが利用できることと、MariaDB 11.4 系であることを確認した。
- [MariaDB: mariadb-install-db](https://mariadb.com/docs/server/clients-and-utilities/deployment-tools/mariadb-install-db)
  - `--user`、`--datadir`、`--auth-root-authentication-method=socket`、`--skip-test-db` の意味を確認した。
- [MariaDB: mariadbd options](https://mariadb.com/docs/server/server-management/starting-and-stopping-mariadb/mariadbd-options)
  - `mariadbd` をフォアグラウンドの PID 1 として起動する設計の根拠。

### 実機検証での修正

Alpine 3.23 の MariaDB 11.4.12 で `--extra-file` にユーザー作成 SQL を渡すと、bootstrap 中の `--skip-grant-tables` により `CREATE USER` が失敗した。そのため、system tables の作成とアプリケーション用 SQL の実行を分け、一時 socket サーバ経由で後者を実行する設計に変更した。

## 2026-08-19 — Phase 4 WordPress / PHP-FPM

- [WordPress: Before You Install](https://developer.wordpress.org/advanced-administration/before-install/)
  - PHP、MariaDB、HTTPS が必要という実行要件を確認した。
- [WordPress: How to install WordPress](https://developer.wordpress.org/advanced-administration/before-install/howto-install/)
  - DB ユーザー、`wp-config.php`、WordPress インストールの責務を確認した。
- [WP-CLI: Installing](https://make.wordpress.org/cli/handbook/guides/installing/)
  - WP-CLI は公式推奨の PHAR を PATH 上に配置する方式を採用した。
- [WP-CLI: Verifying downloads](https://make.wordpress.org/cli/handbook/guides/verifying-downloads/)
  - PHAR の検証方法を確認した。現段階では公式の stable PHAR URL を使用し、イメージ build 時に `wp --info` を実行する。
- [Alpine package index: PHP84 mysqli](https://pkgs.alpinelinux.org/contents?arch=x86_64&branch=v3.23&name=php84-mysqli&repo=community)
  - Alpine 3.23 の PHP84 拡張パッケージ名と配置を確認した。
- [PHP: FastCGI Process Manager](https://www.php.net/manual/en/install.fpm.php)
  - php-fpm を nginx から FastCGI で利用する構成の根拠。

## 2026-08-20 — Phase 5 NGINX / TLS

- [NGINX: Configuring HTTPS servers](https://nginx.org/en/docs/http/configuring_https_servers.html)
  - `listen 443 ssl`、証明書、`ssl_protocols TLSv1.2 TLSv1.3` の構成を確認した。
- [NGINX: ngx_http_ssl_module](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
  - TLS 設定ディレクティブの公式リファレンス。
- [NGINX: ngx_http_fastcgi_module](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
  - `fastcgi_pass wordpress:9000` と `SCRIPT_FILENAME` を含む FastCGI パラメータの根拠。
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
  - `ARG DOMAIN_NAME` と exec form の `CMD` を使用する根拠。

## 2026-08-20 — Phase 6 Docker Compose / Makefile

- [Compose file reference: services](https://docs.docker.com/reference/compose-file/services/)
  - 3サービスの `build`、`restart`、`healthcheck`、`depends_on` を定義する際の公式リファレンス。
- [Compose file reference: volumes](https://docs.docker.com/reference/compose-file/volumes/)
  - `local` driver と `driver_opts` の bind mount で、named volume を `${DATA_PATH}/mariadb` と `${DATA_PATH}/wordpress` に対応させる根拠。
- [Compose file reference: secrets](https://docs.docker.com/reference/compose-file/secrets/)
  - ホスト上の1ファイル1シークレットをトップレベルで宣言し、必要なサービスだけに付与する構成の根拠。
- [Compose: control startup order](https://docs.docker.com/compose/how-tos/startup-order/)
  - WordPress が MariaDB の `service_healthy` を待つ `depends_on` 条件の根拠。
- [Docker Compose down reference](https://docs.docker.com/reference/cli/docker/compose/down/)
  - 通常の `down` では named volume を残し、`clean` / `fclean` の削除範囲を分ける判断の根拠。

## 参照予定

残りのPhaseでも、課題文にない判断は公式資料で確認できたものだけ採用する。
