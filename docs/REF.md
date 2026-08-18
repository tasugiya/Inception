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

## 参照予定

実装時に Docker Compose、named volume、secrets、user-defined network、PID 1、WordPress、WP-CLI、Alpine パッケージの公式資料を追加する。課題文にない判断は、公式資料で確認できたものだけ採用する。
