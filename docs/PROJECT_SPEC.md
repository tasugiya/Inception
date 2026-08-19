# PROJECT_SPEC.md — Inception 構成仕様

> 前提: `PROJECT_DEFINE.md` の要件定義（REQ / INTERP / DEFENSE）
> 対象: mandatory part のみ
> 作成日: 2026-08-17

**このドキュメントの方針について**: 実装コードの完成形は意図的に載せていない。理由は2つある。(1) subject Ch.IV が「自分で理解し責任を持てるものだけを使え」と明記しており、コピーできる完成コードはピア評価でのリスクになる。(2) 本書の目的は「何を・なぜ作るか」を確定することであり、書き方そのものは公式ドキュメントを引きながら自分で書くほうが理解が残る。したがって本書は **ファイル単位の責務・必要な設定項目名・処理の順序・検証方法** を規定し、行単位のコードは要点のみ示す。

---

## 1. システム全体像

```
                        [ ホスト（ラップトップ / 42校舎マシン）]
                                     │
                        ┌────────────┴─────────────┐
                        │      ゲスト VM (Debian)     │
                        │   /etc/hosts:              │
                        │     127.0.0.1 <login>.42.fr│
                        │                            │
   ブラウザ ──443/TLS──▶ │  ┌──────────────────────┐  │
                        │  │ docker network        │  │
                        │  │   "inception"(bridge) │  │
                        │  │                       │  │
                        │  │  [nginx]              │  │
                        │  │    :443 (公開)         │  │
                        │  │      │ FastCGI 9000   │  │
                        │  │      ▼                │  │
                        │  │  [wordpress]          │  │
                        │  │    php-fpm :9000      │  │
                        │  │      │ MySQL 3306     │  │
                        │  │      ▼                │  │
                        │  │  [mariadb] :3306      │  │
                        │  └──────────────────────┘  │
                        │                            │
                        │  named volumes             │
                        │   wordpress_data ─┐        │
                        │   mariadb_data ───┼─▶ /home/<login>/data/
                        └────────────────────────────┘
```

**ボリュームのマウント関係**

| volume | マウント先 | 用途 |
|---|---|---|
| `mariadb_data` | `mariadb:/var/lib/mysql` | DB のデータディレクトリ |
| `wordpress_data` | `wordpress:/var/www/html`（rw）<br>`nginx:/var/www/html`（**ro**） | WordPress のサイトファイル |

> nginx 側を read-only でマウントするのは、nginx が静的ファイルの配信しか行わないため。「なぜ ro か」はディフェンスで加点になる小さな設計判断。

**通信の流れ（1リクエスト）**
1. ブラウザ → `https://<login>.42.fr` → VM の 443 → nginx コンテナ
2. nginx が TLS を終端。`.php` へのリクエストを FastCGI で `wordpress:9000` に転送
3. php-fpm が WordPress を実行。DB が必要なら `mariadb:3306` へ MySQL プロトコルで接続
4. 応答が逆順に戻る

---

## 2. 技術選定

### 2.1 ベースイメージ: `alpine:3.23`

| 判断軸 | 評価 |
|---|---|
| penultimate stable か | ○ 2026-08 時点で最新は 3.24 系、その1つ前が 3.23 系 |
| イメージサイズ / ビルド時間 | ○ 数 MB。VM 上での反復ビルドが速い |
| 設定ファイルの単純さ | ○ Debian の `sites-enabled` / `conf.d` の多段構成に比べ追いやすい |
| 学習コスト | △ musl / BusyBox 由来の差異があるが、本課題の範囲では影響しない |

**代替**: `debian:bookworm`。パッケージが素直で情報も多いが、イメージが大きく（数百 MB）、`apt` のキャッシュ削除など定型処理が増える。**シンプルさ最優先の方針から Alpine を採用**。

> **提出直前に必ず再確認すること**: `https://alpinelinux.org/releases/` を開き、最新安定系列が 3.24 のままか確認する。3.25 が出ていれば penultimate は 3.24 に変わる。

### 2.2 各サービスの構成要素（Alpine 3.23 で確認済み）

| サービス | 主要パッケージ | 版（3.23 時点） | 実行バイナリ（PID 1） |
|---|---|---|---|
| mariadb | `mariadb`, `mariadb-client` | 11.4.x（LTS） | `mariadbd --user=mysql` |
| wordpress | `php84-fpm` + 拡張群 | PHP 8.4.x | `php-fpm84 -F` |
| nginx | `nginx`, `openssl` | — | `nginx -g "daemon off;"` |

**PHP のバージョン選定**: Alpine 3.23 の community には `php83` / `php84` / `php85` がある。WordPress プロジェクトは PHP 8.3 以上を推奨し、WordPress 6.8 以降は PHP 8.4 を正式サポートとしている。→ **`php84` 系を採用**（8.5 はエコシステムの追随がまだ進行中のため避ける）。

**WordPress 用 PHP 拡張（最小セット）**

`php84-fpm` に加えて: `php84-mysqli`（DB 接続）, `php84-phar`（WP-CLI の PHAR 実行）, `php84-curl` + `php84-openssl`（HTTPS 通信）, `php84-json`, `php84-mbstring`, `php84-xml`, `php84-dom`, `php84-simplexml`, `php84-zip`, `php84-fileinfo`, `php84-session`, `php84-tokenizer`, `php84-ctype`, `php84-iconv`, `php84-exif`, `php84-opcache`

> 実装時は一度この一覧で入れて WordPress を動かし、**警告が出ない最小集合まで削ってから確定する**。「なぜこの拡張が要るのか」を1つずつ言えるのが理想（`mysqli` = DB、`phar` = WP-CLI、`curl`/`openssl` = 更新チェックとダウンロード、`mbstring` = マルチバイト、`dom`/`xml` = 各種パース、といった説明ができればよい）。

### 2.3 MariaDB のバージョン整合

Alpine 3.23 の MariaDB は 11.4 系（LTS）。WordPress の推奨要件（MariaDB 10.6 以上）を満たす。

---

## 3. リポジトリ構成

```
inception/
├── Makefile                       # ルート必須。全体のビルドと起動
├── README.md                      # Ch.VI 要件
├── USER_DOC.md                    # Ch.VII 要件（利用者向け）
├── DEV_DOC.md                     # Ch.VII 要件（開発者向け）
├── .gitignore                     # secrets/*.txt と srcs/.env を除外
│
├── secrets/                       # 実体は Git 追跡外
│   ├── db_password.txt.example
│   ├── wp_admin_password.txt.example
│   ├── wp_user_password.txt.example
│   ├── db_password.txt            # ← .gitignore
│   ├── wp_admin_password.txt      # ← .gitignore
│   └── wp_user_password.txt       # ← .gitignore
│
├── tools/
│   └── vm-setup.sh                # VM プロビジョニング（任意・§10 参照）
│
└── srcs/
    ├── .env.example               # 追跡する
    ├── .env                       # ← .gitignore
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── zz-inception.cnf
        │   └── tools/
        │       └── entrypoint.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/
        │   │   └── www.conf
        │   └── tools/
        │       └── entrypoint.sh
        └── nginx/
            ├── Dockerfile
            ├── .dockerignore
            └── conf/
                └── default.conf
```

**subject のディレクトリ例との差分と理由**

| 差分 | 理由 |
|---|---|
| `requirements/bonus/` を作らない | bonus 非実施（DEFINE §6） |
| `requirements/tools/`（サービス外の共通 tools）を作らない | 共通ツールが無いため。各サービス配下の `tools/` は作る |
| nginx に `tools/` が無い | 証明書をビルド時に生成するため entrypoint スクリプトが不要（§5.3） |
| `secrets/credentials.txt` ではなく用途別の3ファイル | Docker secrets は「1ファイル = 1つの値」が原則。1ファイルに複数の値を入れるとコンテナ側にパース処理が必要になり、原則2（説明できないものは入れない）に反する。subject のファイル名一覧は example であり規定ではない |
| `.env.example` / `*.txt.example` を追加 | クローン直後から手順どおりに再現できるようにするため（DEFINE §2.3） |

**ファイル別の責務一覧**

| パス | 責務 |
|---|---|
| `Makefile` | データディレクトリ作成 → compose 経由でビルド＆起動。停止・再構築・掃除のターゲットを提供 |
| `srcs/docker-compose.yml` | 3サービス / 1ネットワーク / 2ボリューム / 3シークレット の宣言。依存関係と再起動ポリシー |
| `srcs/.env` | 非機密の設定値（§4.1） |
| `secrets/*.txt` | パスワード（1ファイル1値、改行なし推奨） |
| `*/Dockerfile` | ベースイメージ指定・パッケージ導入・設定ファイル配置・起動コマンド定義 |
| `*/conf/*` | サービス固有の設定ファイル |
| `*/tools/entrypoint.sh` | 初回のみ必要な初期化と、本体プロセスの `exec` 起動 |
| `*/.dockerignore` | ビルドコンテキストから不要ファイルを除外（例: `*.md`） |

---

## 4. 設定値の設計

### 4.1 `srcs/.env`（非機密のみ）

| 変数 | 例 | 用途 | 参照先 |
|---|---|---|---|
| `LOGIN` | `tasugiya` | データパスの組み立て | compose（`device`）, Makefile |
| `DOMAIN_NAME` | `tasugiya.42.fr` | nginx `server_name`、証明書 CN、WP のサイト URL | nginx ビルド引数, wordpress env |
| `DATA_PATH` | `/home/tasugiya/data` | named volume の実体配置先 | compose `driver_opts.device`, Makefile |
| `MYSQL_DATABASE` | `wordpress` | 作成する DB 名 | mariadb env, wordpress env |
| `MYSQL_USER` | `wp_user` | WordPress が使う DB ユーザー | mariadb env, wordpress env |
| `WP_TITLE` | `Inception` | サイトタイトル | wordpress env |
| `WP_ADMIN_USER` | `tasu_boss` | WP 管理者名（**admin を含めない**） | wordpress env |
| `WP_ADMIN_EMAIL` | `tasu_boss@example.com` | 管理者メール | wordpress env |
| `WP_USER` | `tasu_writer` | 2人目のユーザー | wordpress env |
| `WP_USER_EMAIL` | `tasu_writer@example.com` | 2人目のメール | wordpress env |

> `.env` は compose ファイルと同じディレクトリ（`srcs/`）に置く。Compose はプロジェクトディレクトリの `.env` を自動で読み、`${VAR}` を補間する。Makefile では `--env-file srcs/.env` を明示して、実行ディレクトリに依存しないようにする。

### 4.2 `secrets/`（機密）

| ファイル | コンテナ内パス | 使うサービス | 内容 |
|---|---|---|---|
| `db_password.txt` | `/run/secrets/db_password` | mariadb, wordpress | `MYSQL_USER` のパスワード |
| `wp_admin_password.txt` | `/run/secrets/wp_admin_password` | wordpress | WP 管理者のパスワード |
| `wp_user_password.txt` | `/run/secrets/wp_user_password` | wordpress | WP 2人目のパスワード |

**DB の root パスワードを持たない設計を採用する**

MariaDB 10.4 以降、`root@localhost` は既定で `unix_socket` プラグイン認証になる。これは「コンテナ内の root システムユーザーだけがローカルソケット経由でログインできる」という意味で、**そもそもネットワーク経由で root にログインする経路が存在しない**。したがって root パスワードという秘密を1つ増やさずに済む。

- **DEFENSE**: 「このスタックで DB にネットワーク認証するのは WordPress ユーザーだけ。root はコンテナ内ソケット限定で、漏洩しうるパスワード自体が存在しない。これは MariaDB 自身の既定設計に沿っている」
- レビューで root ログインの実演を求められたら `docker exec -it mariadb mariadb -u root` でそのまま入れる。
- **保険（もしレビュアーが root パスワードの存在を要求した場合）**: `secrets/db_root_password.txt` を追加し、初期化 SQL に
  `ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket OR mysql_native_password USING PASSWORD('<root_pw>');`
  を1行足せば、ソケット認証を残したままパスワード認証も併用できる。**この選択は TODO の判断項目とする**（実装コストは小さいので後付け可能）。

### 4.3 環境変数の渡し方

`env_file:` でまとめて流し込まず、**サービスごとに `environment:` で必要な変数だけを列挙する**。

- **DEFENSE**: 「最小権限。mariadb に WP 管理者名を渡す理由はないし、nginx に DB 名を渡す理由もない。何がどこで必要かが compose を読むだけで分かる」

サービス別の必要変数:

| サービス | environment | secrets |
|---|---|---|
| mariadb | `MYSQL_DATABASE`, `MYSQL_USER` | `db_password` |
| wordpress | `DOMAIN_NAME`, `MYSQL_DATABASE`, `MYSQL_USER`, `WP_TITLE`, `WP_ADMIN_USER`, `WP_ADMIN_EMAIL`, `WP_USER`, `WP_USER_EMAIL` | `db_password`, `wp_admin_password`, `wp_user_password` |
| nginx | （不要。`DOMAIN_NAME` はビルド引数で渡す） | なし |

---

## 5. コンテナ別仕様

### 5.1 mariadb

**Dockerfile の骨子**

| ステップ | 内容 | 注意 |
|---|---|---|
| 1 | `FROM alpine:3.23` | タグ必須 |
| 2 | `RUN apk add --no-cache mariadb mariadb-client` | 1つの RUN にまとめる |
| 3 | `COPY conf/zz-inception.cnf /etc/my.cnf.d/` | ファイル名の理由は下記 |
| 4 | `COPY tools/entrypoint.sh /usr/local/bin/` + 実行権限付与 | |
| 5 | `ENTRYPOINT ["entrypoint.sh"]`（exec 形式） | shell 形式にしない |

**設定ファイル名を `zz-inception.cnf` にする理由**
Alpine の `/etc/my.cnf` は `!includedir /etc/my.cnf.d/` で同ディレクトリを **ファイル名順** に読み込む。パッケージ既定の `mariadb-server.cnf` より後に読ませて確実に上書きするため、`z` で始まる名前にする。ここもディフェンスで説明できる小さな設計判断。

**設定内容**

```ini
[mysqld]
skip-networking = 0     ; ネットワーク待受を有効化
bind-address    = 0.0.0.0
skip-name-resolve       ; ホスト名逆引きをやめる（同一 network 内なので不要・起動が速い）
datadir         = /var/lib/mysql
```

**entrypoint.sh の処理順序**

```
1. データディレクトリ未初期化か判定
     [ ! -d /var/lib/mysql/mysql ]  ← システム DB の有無で判定する
2. 起動ごとに `/run/mysqld` を作成（`/run` は named volume ではないため）
3. 未初期化の場合のみ:
   a. 初期化 SQL を /tmp に生成
        CREATE DATABASE IF NOT EXISTS `${MYSQL_DATABASE}`;
        CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '<db_password の中身>';
        GRANT ALL PRIVILEGES ON `${MYSQL_DATABASE}`.* TO '${MYSQL_USER}'@'%';
        FLUSH PRIVILEGES;
   b. mariadb-install-db --user=mysql --datadir=/var/lib/mysql \
        --auth-root-authentication-method=socket --skip-test-db
   c. 一時的に socket 専用の mariadbd を起動し、readiness を待つ
   d. mariadb client で /tmp/init.sql を実行し、mariadb-admin shutdown で停止
   e. /tmp/init.sql を削除
4. exec /usr/bin/mariadbd --user=mysql
```

**設計上のポイント**
- `mariadb-install-db` は system tables の bootstrap 中に grant tables を無効化して実行するため、`--extra-file` に `CREATE USER` / `GRANT` を渡す方法は Alpine 3.23 の MariaDB 11.4 では使えないことを実機で確認した。そこで、system tables 作成後に socket 専用の一時サーバを起動して SQL を実行する。
- 一時サーバの readiness 待機は有限回数の `for` ループであり、コンテナを生かすための無限ループではない。本番の最後は `exec` で MariaDB が PID 1 になる。
- `--skip-test-db` で不要な `test` データベースを作らない。
- パスワードは `$(cat /run/secrets/db_password)` として **実行時に読む**。Dockerfile にも `.env` にも出てこない。
- 初期化 SQL は `/tmp` に置き、使用後に削除する（volume 上に残さない）。
- 最終行の `exec` により `mariadbd` が PID 1 になる。

**healthcheck**（compose 側で定義）
- `mariadb-admin ping -u root --protocol=socket`（コンテナ内 root ＝ ソケット認証で通る）
- `interval: 5s` / `timeout: 5s` / `retries: 20` / `start_period: 20s`
- 実装時に一度手で叩いて成功することを確認する。もし通らなければ `mariadb -u root -e "SELECT 1"` に置き換える。

### 5.2 wordpress

**Dockerfile の骨子**

| ステップ | 内容 |
|---|---|
| 1 | `FROM alpine:3.23` |
| 2 | `RUN apk add --no-cache curl php84-fpm <拡張群>` |
| 3 | WP-CLI の PHAR を取得し `/usr/local/bin/wp` に実行権限付きで配置 |
| 4 | WordPress 本体を **ビルド時に** `/usr/src/wordpress` へ取得（`wp core download --path=/usr/src/wordpress --allow-root`） |
| 5 | `COPY conf/www.conf /etc/php84/php-fpm.d/www.conf` |
| 6 | `COPY tools/entrypoint.sh /usr/local/bin/` + 実行権限 |
| 7 | `WORKDIR /var/www/html` |
| 8 | `ENTRYPOINT ["entrypoint.sh"]` |

**WordPress 本体をビルド時に取得する理由**
- volume はコンテナ起動時に `/var/www/html` を覆うため、ビルド時にそこへ展開したファイルは初回起動で見えなくなる。→ ビルド時は **volume 外の `/usr/src/wordpress`** に置き、起動時にコピーする（公式 wordpress イメージと同じ考え方）。
- 実行時にネットワークが不要になり、再ビルドなしの再起動が速い。「イメージは自己完結している」と説明できる。

**PHP memory_limit**: 現在の WordPress コアを WP-CLI で展開するには Alpine PHP の既定 `128M` では不足したため、`/etc/php84/conf.d/99-wordpress.ini` で `memory_limit=256M` を明示する。これはビルド時の `wp core download` と runtime の WP-CLI の共通設定である。

**www.conf の必須変更点**

| 項目 | 既定 | 変更後 | 理由 |
|---|---|---|---|
| `listen` | `127.0.0.1:9000` | `0.0.0.0:9000` | 別コンテナの nginx から IPv4 で到達できるようにする |
| `user` / `group` | `nobody` | `nobody`（据え置き） | ファイル所有者を合わせる（entrypoint で `chown`） |
| プロセス管理 | `pm = dynamic` | 据え置き | 変更する理由がない |

> 既定のままだと nginx から `502 Bad Gateway` になる。これは最も頻出のつまずき箇所。

**entrypoint.sh の処理順序**

```
1. /var/www/html が空なら /usr/src/wordpress の中身をコピー
2. wp core is-installed --allow-root が失敗する（=未インストール）場合のみ:
   a. wp config create
        --dbname=$MYSQL_DATABASE
        --dbuser=$MYSQL_USER
        --dbpass="$(cat /run/secrets/db_password)"
        --dbhost=mariadb:3306
   b. wp core install
        --url=https://$DOMAIN_NAME
        --title="$WP_TITLE"
        --admin_user=$WP_ADMIN_USER
        --admin_password="$(cat /run/secrets/wp_admin_password)"
        --admin_email=$WP_ADMIN_EMAIL
        --skip-email
   c. wp user create $WP_USER $WP_USER_EMAIL
        --role=author
        --user_pass="$(cat /run/secrets/wp_user_password)"
3. chown -R nobody:nobody /var/www/html
4. exec /usr/sbin/php-fpm84 -F
```

- WP-CLI は root で動かすため全コマンドに `--allow-root` が要る。
- `--skip-email` を付けないと管理者宛メール送信を試みて時間がかかる。
- `-F` は `--nodaemonize` の短縮形（php-fpm(8) man 記載）。これで php-fpm が前景に留まり PID 1 になる。
- 2 の判定により、**2回目以降の起動では何もせず php-fpm を上げるだけ** になる（冪等性）。

### 5.3 nginx

**Dockerfile の骨子**

| ステップ | 内容 |
|---|---|
| 1 | `FROM alpine:3.23` |
| 2 | `ARG DOMAIN_NAME` （compose の `build.args` から受け取る） |
| 3 | `RUN apk add --no-cache nginx openssl` |
| 4 | 自己署名証明書を生成: `openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 -subj "/CN=${DOMAIN_NAME}" -addext "subjectAltName=DNS:${DOMAIN_NAME}" -keyout /etc/nginx/ssl/inception.key -out /etc/nginx/ssl/inception.crt` |
| 5 | `COPY conf/default.conf /etc/nginx/http.d/default.conf`（既定ファイルを置き換え） |
| 6 | `sed` で conf 内のドメインプレースホルダを `${DOMAIN_NAME}` に置換 |
| 7 | `CMD ["nginx", "-g", "daemon off;"]` |

**entrypoint スクリプトを持たない理由**: 起動時に必要な初期化が無いため。証明書はイメージに焼き込み、設定はビルド時に確定する。「スクリプトが要らないなら書かない」が原則1・2に沿う。

- 証明書の鍵はイメージ内で生成され、**リポジトリにはコミットされない**。自己署名のローカル開発用証明書であり、R15 の「credentials を Git に置くな」に抵触しない。
- `ARG` + `sed` により、ドメイン名の単一情報源は `.env` のまま保たれる（原則3）。

**nginx の設定構造**
Alpine の `nginx.conf` は末尾で `include /etc/nginx/http.d/*.conf;` を行う。したがって編集するのは `http.d/default.conf` の1ファイルだけでよい。

**default.conf の必須ディレクティブ**

| ディレクティブ | 値 | 対応する要件 |
|---|---|---|
| `listen` | `443 ssl` | R6（443 のみ） |
| `server_name` | `<login>.42.fr` | R14 |
| `ssl_certificate` / `ssl_certificate_key` | 生成した crt / key | R6 |
| `ssl_protocols` | `TLSv1.2 TLSv1.3` | R6（**この1行が要件の中核**） |
| `root` | `/var/www/html` | — |
| `index` | `index.php` | — |
| `location /` | `try_files $uri $uri/ /index.php?$args;` | WordPress のパーマリンク |
| `location ~ \.php$` | `fastcgi_pass wordpress:9000;` + `include fastcgi.conf;` | R7・R10 |

- 80 番の `listen` を **書かない**（R6）。
- `include fastcgi.conf;`（Alpine の nginx パッケージに同梱）は `SCRIPT_FILENAME` を含む標準パラメータ一式を設定する。`fastcgi_params` を使う場合は `SCRIPT_FILENAME` を自分で追加する必要がある点に注意。
- `fastcgi_pass wordpress:9000;` の `wordpress` は compose のサービス名。Docker の埋め込み DNS が解決する（R10 の DEFENSE そのもの）。

---

## 6. docker-compose.yml 仕様

**トップレベル要素**

| 要素 | 内容 |
|---|---|
| `services` | `mariadb`, `wordpress`, `nginx` |
| `networks` | `inception`（`driver: bridge`）— R10 の "network line" |
| `volumes` | `mariadb_data`, `wordpress_data`（`local` + `driver_opts`）— R9 |
| `secrets` | `db_password`, `wp_admin_password`, `wp_user_password`（`file: ../secrets/*.txt`）— R15 |

> `version:` キーは Compose v2 で不要（記述しても無視される）。書かない。
> secrets の `file:` は **compose ファイルからの相対パス** なので `../secrets/...` になる。

**サービス共通で設定する項目**

| キー | 値 | 要件 |
|---|---|---|
| `build.context` | `./requirements/<service>` | R2 |
| `image` | `<service>:1.0` | R3（名前＝サービス名、タグは `latest` 以外） |
| `container_name` | `<service>` | レビュー時の可読性 |
| `networks` | `[inception]` | R10 |
| `restart` | `unless-stopped` | R11 |

**サービス個別**

| サービス | 個別設定 |
|---|---|
| mariadb | `volumes: [mariadb_data:/var/lib/mysql]`, `environment`（§4.3）, `secrets: [db_password]`, `healthcheck`（§5.1） |
| wordpress | `volumes: [wordpress_data:/var/www/html]`, `environment`, `secrets`×3, `depends_on: {mariadb: {condition: service_healthy}}` |
| nginx | `ports: ["443:443"]`, `volumes: [wordpress_data:/var/www/html:ro]`, `build.args: {DOMAIN_NAME: ${DOMAIN_NAME}}`, `depends_on: [wordpress]` |

**`ports` は nginx にのみ書く。** mariadb / wordpress には `ports` も `expose` も書かない（`expose` は Compose v2 では実質ドキュメント目的のみで、書かないほうが「443 が唯一の入口」という意図が明確になる）。

**volume 宣言**

```yaml
volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/mariadb
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/wordpress
```

`${DATA_PATH}` は `srcs/.env` から補間される。**このディレクトリが存在しないと起動に失敗する** ため、Makefile 側で必ず先に作る。

---

## 7. Makefile 仕様

| ターゲット | 動作 | 備考 |
|---|---|---|
| `all`（既定） | `up` を呼ぶ | `make` 単独で全部立ち上がる（R2） |
| `check` | `.env` と `secrets/*.txt` の存在を確認。無ければ手順を表示して失敗 | レビュー当日の事故防止 |
| `dirs` | `mkdir -p $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress` | R9 の前提条件 |
| `up` | `check` `dirs` の後 `docker compose ... up -d --build` | イメージビルドを含む |
| `down` | `docker compose ... down` | コンテナ・ネットワーク削除。データは残る |
| `re` | `down` → `up` | 再構築 |
| `clean` | `down` + イメージ削除（`--rmi local`） | データは残る |
| `fclean` | `clean` + `docker volume rm` + `sudo rm -rf $(DATA_PATH)/*` | **データが消える**。USER_DOC に明記 |
| `logs` / `ps` | 状態確認の補助 | レビューでそのまま使える |

**変数定義**

```make
COMPOSE_FILE := srcs/docker-compose.yml
ENV_FILE     := srcs/.env
COMPOSE      := docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)
DATA_PATH    := $(shell grep -E '^DATA_PATH=' $(ENV_FILE) | cut -d= -f2)
```

- `DATA_PATH` を `.env` から読むことで、Makefile 内にパスを直書きしない（原則3）。
- 全ターゲットを `.PHONY` に登録する。

---

## 8. Git 運用と機密情報

**`.gitignore`**

```gitignore
srcs/.env
secrets/*.txt
!secrets/*.txt.example
```

**追跡するテンプレート**
- `srcs/.env.example` — 実値の代わりに `CHANGE_ME` や説明的なダミーを入れる
- `secrets/*.txt.example` — `CHANGE_ME` のみ

**運用ルール**
1. パスワードを含むファイルは **一度もコミットしない**。一度でも入れたら履歴に残るため、`git log -p | grep -i password` で確認する習慣を持つ。
2. 提出前チェック: `git ls-files | grep -E '\.env$|secrets/.*\.txt$'` が空であること。
3. `make check` は secrets の中身が `CHANGE_ME` のままなら失敗させる。

---

## 9. ドキュメント成果物の骨子

### README.md（英語）

```
*This project has been created as part of the 42 curriculum by <login>.*   ← 1行目・斜体

## Description            目的と概要
## Instructions           前提 / セットアップ / make の使い方 / アクセス方法
## Project description
   - Docker の使い方と同梱ソースの説明
   - 主要な設計判断（ベースイメージ / PID 1 / secrets 分離 / named volume の実体配置）
   - Virtual Machines vs Docker
   - Secrets vs Environment Variables
   - Docker Network vs Host Network
   - Docker Volumes vs Bind Mounts
## Resources              公式ドキュメントのリンク + AI の利用範囲の明記
```

> 「主要な設計判断」節は PROJECT_DEFINE.md の INTERP / DEFENSE をそのまま英訳すれば埋まる。

### USER_DOC.md
1. このスタックが提供するもの（3サービスの役割と1枚図）
2. 起動と停止（`make` / `make down` / `make fclean` の違いと影響範囲）
3. サイトと管理画面へのアクセス（`https://<login>.42.fr` / `/wp-admin`、証明書警告の説明）
4. 認証情報の所在（`secrets/` と `.env` の役割、変更方法、変更後に必要な操作）
5. 正常性の確認（`docker ps` の期待出力、`make logs`、healthcheck の見方）

### DEV_DOC.md
1. 前提（VM、Docker Engine、Compose v2、`/etc/hosts`）
2. ゼロからの構築手順（clone → `.env` と secrets の作成 → `make`）
3. Makefile と Compose の関係、各ターゲットの中身
4. コンテナとボリュームの管理コマンド集
5. データの保存先と永続化の仕組み（`docker volume inspect` の出力例つき）
6. トラブルシュート（502 / DB 接続失敗 / ポート使用中 / 証明書）

---

## 10. 仮想マシン仕様とセットアップ

### 10.1 運用モデル

**開発環境と提出前 VM を役割分担して用意する。**

| | 開発用環境 | 検証・レビュー用 VM |
|---|---|---|
| 所在 | 自分の WSL2 + Docker Desktop | 42校舎マシンの VirtualBox + Debian GUI |
| 用途 | 実装と反復 | クローンして最終確認、レビュー本番 |
| リポジトリ | 直接編集 → push | `git clone` → `make` |

「校舎マシンでクローンして動く」ことが最終要件なので、**開発用 VM でも必ず一度クローンからの手順を通す**。ローカルにしか無いファイル（`.env` / secrets / データ）に暗黙依存していないかは、この方法でしか検出できない。

### 10.2 ハイパーバイザ 【判断済み】

| 環境 | 選択肢 | メモ |
|---|---|---|
| 開発環境 | **WSL2 + Docker Desktop** | 反復開発用。Docker Desktop の WSL Integration を有効化する |
| 42校舎マシン | **VirtualBox** | Debian GUI を導入し、subject の VM 要件を満たす最終リハーサル用。CPU アーキテクチャと VirtualBox の利用可否は現地で確認する |

> 校舎マシンでの VM 実体の置き場所は **`sgoinfre`（または `goinfre`）配下**。ホームディレクトリは容量制限があり、VM イメージを置くと途中で容量不足になる。校舎の実機で VirtualBox と CPU アーキテクチャを最初に確認する。

### 10.3 ゲスト OS 仕様

| 項目 | 値 | 理由 |
|---|---|---|
| ディストリ | **Debian 13 (trixie)** netinst | Docker 公式 apt リポジトリが trixie を正式サポート。Born2beroot の経験が流用できる |
| バージョン制約 | 最新安定版でよい | penultimate 規則はコンテナのベースイメージのみに適用（DEFINE §2.2） |
| CPU | 2 vCPU | |
| メモリ | 4096 MB（最低 2048） | |
| ディスク | 20 GB 可変 | イメージ・ボリューム・GUI を含めて余裕を持つ |
| デスクトップ環境 | **XFCE + Firefox ESR** | レビューでブラウザ表示を見せる必要があるため。軽量な XFCE を選ぶ |
| 追加パッケージ | `sudo`, `git`, `curl`, `make`, `openssh-server`（任意） | |
| ネットワーク | NAT（既定） | サイトは VM 内のブラウザで見るので、ポートフォワードは不要 |

**GUI を入れる判断について**: 「シンプルに」の原則からは headless が魅力的だが、レビューでは「ブラウザで `https://<login>.42.fr` を開いて WordPress と管理画面を見せる」ことが実質的に求められる。VM 内 GUI が最も確実で、ホスト側のネットワーク設定に依存しない。
**代替（headless で進める場合）**: `curl -k -I https://<login>.42.fr` で確認しつつ、ホストのブラウザから見せたいときは NAT のポートフォワード（host 8443 → guest 443）+ ホストの `/etc/hosts` を使う。ただし URL が `:8443` になるため説明が一手間増える。**開発中は headless、レビュー用 VM は GUI** という使い分けも合理的。

### 10.4 VM プロビジョニング手順（校舎用 VM）

```
1. Debian 13 netinst をインストール
   - ホスト名: <login>42 など任意
   - ソフトウェア選択: XFCE + standard system utilities（SSH server は任意）
2. sudo の設定（インストール時に root パスワードを空にすると自動で sudo 付与される）
3. 基本パッケージ
     sudo apt update && sudo apt install -y git make curl ca-certificates
4. Docker Engine + Compose v2 を公式 apt リポジトリから導入
     https://docs.docker.com/engine/install/debian/ の手順に従う
     パッケージ: docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
5. 自ユーザーを docker グループへ
     sudo usermod -aG docker $USER   （再ログインで有効）
6. hosts 設定
     echo "127.0.0.1 <login>.42.fr" | sudo tee -a /etc/hosts
7. 動作確認
     docker run --rm hello-world
     docker compose version
8. VM のスナップショットを取る  ← 重要
```

**8 のスナップショットを必ず取ること。** 「クリーンな状態からクローンして `make` が通る」ことを何度でも再現でき、レビュー直前のリハーサルが安全になる。

`tools/vm-setup.sh` として 3〜7 をスクリプト化しておくと、2台目の構築が数分で終わる。ただしこれは提出物の必須要素ではないので、時間が無ければ DEV_DOC.md の手順書だけでもよい。

### 10.5 校舎マシンでのレビュー準備

```
1. sgoinfre 上の VM を起動（またはスナップショットから復元）
2. git clone <repo> && cd inception
3. cp srcs/.env.example srcs/.env  → LOGIN / DOMAIN_NAME / DATA_PATH を自分のものに
4. secrets/*.txt を作成（.example をコピーして中身を書き換え）
5. make
6. VM 内 Firefox で https://<login>.42.fr を開く
```

3〜4 が手作業になるのは R15（機密を Git に置かない）の必然的な帰結。**この手順を USER_DOC.md / DEV_DOC.md に明記しておき、レビュー冒頭で「機密はコミットしていないので、ここだけ手動です」と説明する。** 説明できていれば減点要素ではなく、むしろ理解を示す材料になる。

---

## 11. 受入基準（レビュー前セルフチェック）

各項目に **確認コマンド** を紐づける。TODO.md の最終フェーズで実行する。

| # | 確認事項 | コマンド / 手順 | 期待 |
|---|---|---|---|
| 1 | 3コンテナが稼働 | `docker ps` | nginx / wordpress / mariadb が Up |
| 2 | イメージ名がサービス名 | `docker images` | `nginx:1.0` / `wordpress:1.0` / `mariadb:1.0`。`latest` タグが無い |
| 3 | ベースが penultimate | `grep -r '^FROM' srcs/requirements/` | すべて `alpine:3.23` |
| 4 | 公開ポートは 443 のみ | `docker ps --format '{{.Names}} {{.Ports}}'` | nginx のみ `0.0.0.0:443->443/tcp` |
| 5 | サイト表示 | ブラウザで `https://<login>.42.fr` | WordPress のサイトが表示。インストールウィザードは出ない |
| 6 | 管理画面 | `https://<login>.42.fr/wp-admin` | 管理者でログインできる |
| 7 | TLS 1.2/1.3 のみ | `openssl s_client -connect <login>.42.fr:443 -tls1_1` | 失敗する。`-tls1_2` / `-tls1_3` は成功 |
| 8 | HTTP が開いていない | `curl -I http://<login>.42.fr` | 接続拒否 |
| 9 | PID 1 が本体 | `docker exec nginx ps` 等を3つとも | PID 1 が nginx / php-fpm84 / mariadbd |
| 10 | 無限ループ不使用 | `grep -rn 'tail -f\|sleep infinity\|while true' srcs/` | ヒットなし |
| 11 | ネットワーク宣言 | `docker network ls` / compose 確認 | `inception` bridge。`links` / `host` 不使用 |
| 12 | named volume | `docker volume ls` / `docker volume inspect` | 2つ。`device` が `/home/<login>/data/...` |
| 13 | データ永続化 | 投稿を作成 → `make down` → `make` | 投稿が残っている |
| 14 | クラッシュ復帰 | `docker kill wordpress` → 10秒後 `docker ps` | 再起動している |
| 15 | Dockerfile に秘密なし | `grep -rniE 'password|passwd' srcs/requirements/*/Dockerfile` | ヒットなし |
| 16 | 環境変数に秘密なし | `docker inspect mariadb \| grep -i pass` | パスワード値が出ない |
| 17 | Git に秘密なし | `git ls-files \| grep -E '\.env$\|secrets/.*\.txt$'` / `git log -p \| grep -i password` | 空 |
| 18 | WP ユーザー2名 | `docker exec wordpress wp user list --allow-root` | 2名、1名が administrator、名前に admin を含まない |
| 19 | 必須ドキュメント | `ls README.md USER_DOC.md DEV_DOC.md` | 3つ存在。README 1行目が斜体の規定文 |
| 20 | クリーン再現 | 別ディレクトリに clone → 手順 → `make` | 何も足さずに 1〜19 が再現 |

---

## 12. 要件トレーサビリティ

| DEFINE の要件 | 実装箇所 |
|---|---|
| R1 VM | §10 |
| R2 構成 / Makefile | §3, §7 |
| R3 compose / イメージ名 | §6 |
| R4 ベースイメージ | §2.1, 各 Dockerfile |
| R5 既製イメージ禁止 | 各 Dockerfile（`FROM alpine:3.23` のみ） |
| R6 nginx / TLS / 443 | §5.3, §6（`ports`） |
| R7 WordPress + php-fpm | §5.2 |
| R8 MariaDB | §5.1 |
| R9 named volume | §6（`driver_opts`）, §7（`dirs`） |
| R10 network | §6（`networks`） |
| R11 restart | §6（`unless-stopped`） |
| R12 PID 1 | §5.1〜5.3（`exec` / `-F` / `daemon off`）, §6（healthcheck で待機ループを排除） |
| R13 WP ユーザー2名 | §4.1, §5.2 |
| R14 ドメイン | §10.4（hosts）, §5.3（server_name / CN） |
| R15 機密情報 | §4.2, §4.3, §8 |
| R16 README | §9 |
| R17 USER_DOC / DEV_DOC | §9 |
| R18 小改修対応 | §4（設定の外出し） |
