# TODO.md — Inception 作業手順

> 前提: `PROJECT_DEFINE.md`（要件定義）/ `PROJECT_SPEC.md`（構成仕様）
> 対象: mandatory part のみ

**記法**
- `[ ]` 通常のタスク
- **【判断】** 開発者の意思決定が必要な項目。着手前に決めて、決めた内容をこのファイルに追記する
- **▶ 検証:** そのタスクが完了したと言える条件。**通らなければ次に進まない**

**進め方の原則**
1. **1コンテナずつ完成させる。** 3つ同時に書き始めると、どの層で落ちているのか切り分けられなくなる。順序は `mariadb → wordpress → nginx`（依存の下流から）。
2. **各コンテナは単体で立ち上げて確認してから compose に統合する。** `docker build` + `docker run` で確認できる範囲は先に潰す。
3. **理解できていない行を残さない。** 動いたが理由が言えない箇所は、その場で公式ドキュメントを引く。後回しにするとレビューまで残る。

**目安工数**: Phase 0〜9 合計で実作業 15〜25時間程度。Phase 3〜5（3コンテナ）が半分を占める。

---

## Phase 0 — 事前の意思決定と確認 【最初に片付ける】

- [ ] **【判断】42校舎マシンのハードウェア確認**
  - Apple Silicon か Intel か。VirtualBox が使えるか、UTM が必要か
  - 決めた内容: **未確認**（校舎で確認する。現時点では VirtualBox + Debian GUI を想定）
- [x] **【判断】ハイパーバイザの選定**（校舎とラップトップで揃える）
  - 決めた内容: **開発は WSL2 + Docker Desktop、校舎の本番想定テストは VirtualBox + Debian GUI**。環境の目的が異なるため、同一ハイパーバイザには揃えない
- [x] `<login>` を確定し、以下3箇所で使う値を書き出す
  - ドメイン: `tasugiya.42.fr` / データパス: `/home/tasugiya/data` / README 署名: `tasugiya`
- [x] **ベースイメージのバージョンを再確認**
  - `https://alpinelinux.org/releases/` で最新安定系列を確認
  - 最新が 3.24 系なら penultimate は **3.23**。3.25 が出ていれば 3.24 に変更
  - 確認結果（2026-08-19）: **最新 v3.24、採用 v3.23**。公式リリース一覧で確認済み
- [x] **【判断】WordPress のユーザー名を決める**
  - 管理者名（`admin` / `administrator` を **部分文字列としても** 含まない）: `tasu_owner`
  - 2人目のユーザー名とロール（`author` 推奨）: `tasu_writer`（`author`）
- [x] **【判断】DB root パスワードを持つか**（SPEC §4.2）
  - 既定方針: 持たない（`unix_socket` 認証のみ）
  - 決めた内容: **持たない**。root はコンテナ内 Unix socket 認証のみとする
- [x] **【判断】レビュー用 VM に GUI を入れるか**（SPEC §10.3）
  - 既定方針: XFCE + Firefox ESR を入れる
  - 決めた内容: **入れる**。校舎の VirtualBox 上 Debian に GUI を導入し、VM 内ブラウザで確認する。WSL2 開発環境は GUI なし

▶ 検証: 上記すべての空欄が埋まっている。

---

## Phase 1 — 実行環境の準備

> 開発中は WSL2 で動作確認し、42校舎での最終リハーサルは VirtualBox 上の Debian GUI で行う。subject の「Virtual Machine」要件を提出時に満たすため、WSL2 での確認結果だけを最終判定にしない。

- [x] **開発用 WSL2**: Docker Desktop の `Use WSL 2 based engine` を有効化
- [x] **開発用 WSL2**: Docker Desktop Settings > Resources > WSL Integration で Ubuntu を有効化
- [ ] **校舎用 VM**: Debian 13 (trixie) netinst ISO を入手
- [ ] **校舎用 VM**: VM を作成（2 vCPU / 4096 MB / 20 GB 可変）
  - 校舎マシンの場合は VM の保存先を **`sgoinfre`（または `goinfre`）配下** にする
- [ ] **校舎用 VM**: Debian をインストール（XFCE + standard system utilities）
- [ ] **校舎用 VM**: `sudo apt update && sudo apt install -y git make curl ca-certificates`
- [ ] **校舎用 VM**: Docker Engine + Compose v2 を **公式 apt リポジトリ** から導入
  - 手順: `https://docs.docker.com/engine/install/debian/`
  - `docker.io`（Debian 同梱版）は使わない
- [ ] **校舎用 VM**: `sudo usermod -aG docker $USER` → 再ログイン
- [ ] **校舎用 VM**: `echo "127.0.0.1 tasugiya.42.fr" | sudo tee -a /etc/hosts`
- [ ] **校舎用 VM**: **VM のスナップショットを取る**（名前: `clean-docker-ready`）

▶ 検証:
```
docker run --rm hello-world      # WSL2 / 校舎 VM ともに成功する
docker compose version           # v2.x が出る
getent hosts tasugiya.42.fr      # 校舎 VM で 127.0.0.1 が返る
groups                           # 校舎 VM で docker が含まれる
```

---

## Phase 2 — リポジトリの骨格

- [x] リポジトリを作成し、SPEC §3 のディレクトリツリーを作る（実装前のプレースホルダを含む）
- [x] `.gitignore` を作成（`srcs/.env`, `secrets/*.txt`, `!secrets/*.txt.example`）
      **最初のコミットの前に作る。** 後から追加しても履歴からは消えない
- [x] `srcs/.env.example` を作成（SPEC §4.1 の全変数、値は `CHANGE_ME` かダミー）
- [x] `secrets/*.txt.example` を3つ作成（中身は `CHANGE_ME`）
- [x] ローカル用に `srcs/.env` と `secrets/*.txt` を作成し、実値を入れる（すべて Git ignored）
- [ ] 最初のコミット

▶ 検証:
```
git ls-files | grep -E '\.env$|secrets/.*[^e]\.txt$'   # 何も出ない
git status                                              # .env と *.txt が untracked にも出ない
```

---

## Phase 3 — MariaDB コンテナ

### 3.1 Dockerfile
- [x] `FROM alpine:3.23`
- [x] `apk add --no-cache mariadb mariadb-client`（1つの RUN にまとめる）
- [x] `conf/zz-inception.cnf` を `/etc/my.cnf.d/` に COPY
- [x] `tools/entrypoint.sh` を配置し実行権限を付与
- [x] `ENTRYPOINT ["...entrypoint.sh"]` を **exec 形式** で書く

### 3.2 設定ファイル `conf/zz-inception.cnf`
- [x] `[mysqld]` セクションに `skip-networking = 0` / `bind-address = 0.0.0.0` / `skip-name-resolve` / `datadir = /var/lib/mysql`
- [x] **なぜファイル名が `zz-` で始まるか説明できるようにする**（`/etc/my.cnf.d/` の読み込み順、SPEC §5.1）

### 3.3 entrypoint.sh
- [x] `[ ! -d /var/lib/mysql/mysql ]` で未初期化を判定
- [x] 起動ごとに `/run/mysqld` を作成（`/run` は永続 volume ではないため）
- [x] 未初期化時のみ、初期化 SQL を `/tmp` に生成
  - DB 作成 / ユーザー作成（`'%'` から接続可）/ GRANT / FLUSH
  - パスワードは `$(cat /run/secrets/db_password)` から取得
- [x] `mariadb-install-db --user=mysql --datadir=/var/lib/mysql --auth-root-authentication-method=socket --skip-test-db`
- [x] 一時 socket 専用の `mariadbd` を起動し、有限回数の readiness 待機後に `mariadb` で初期化 SQL を実行
- [x] `mariadb-admin shutdown` で一時サーバを停止し、PID を `wait` してから本体を起動
- [x] 初期化 SQL を削除
- [x] 最終行 `exec /usr/bin/mariadbd --user=mysql`

### 3.4 単体確認
- [x] `docker build -t mariadb-test srcs/requirements/mariadb`
- [x] ローカル secret を read-only mount した一時コンテナで起動して確認

▶ 検証:
```
docker exec -it <c> ps                              # PID 1 が mariadbd
docker exec -it <c> mariadb -u root -e "SHOW DATABASES;"        # wordpress DB がある
docker exec -it <c> mariadb -u root -e "SELECT User,Host FROM mysql.user;"  # wp ユーザーが '%' で存在
docker exec -it <c> mariadb-admin ping -u root --protocol=socket # 成功（healthcheck の下見）
docker logs <c>                                     # 起動ログが stdout/stderr に出ている
docker stop <c>                                     # 10秒待たずに即座に止まる（= SIGTERM が届いている）
```
- [x] **コンテナを消して再度 `docker run`（同じ volume）** → 初期化がスキップされ、DB が残っていることを確認（冪等性）

---

## Phase 4 — WordPress + php-fpm コンテナ

### 4.1 Dockerfile
- [x] `FROM alpine:3.23`
- [x] `php84-fpm` + 拡張群 + `curl` を `apk add --no-cache`
- [x] WP-CLI の PHAR を取得 → `/usr/local/bin/wp` に実行権限付きで配置
- [x] `wp core download --path=/usr/src/wordpress --allow-root` で **ビルド時に** WordPress 本体を取得
      （`/var/www/html` に置かないこと。volume に覆われて消える）
- [x] `conf/www.conf` を `/etc/php84/php-fpm.d/www.conf` に COPY
- [x] entrypoint を配置、`ENTRYPOINT` は exec 形式

### 4.2 `conf/www.conf`
- [x] `listen = 0.0.0.0:9000`（`127.0.0.1:9000` から変更する。**ここを忘れると後で 502 になる**）
- [x] `user` / `group` は `nobody` のまま

### 4.3 entrypoint.sh
- [x] `/var/www/html` が空なら `/usr/src/wordpress` からコピー
- [x] `wp core is-installed --allow-root` が失敗する場合のみ以下を実行
  - [x] `wp config create`（`--dbhost=mariadb:3306`、パスワードは secrets から）
  - [x] `wp core install`（`--url=https://$DOMAIN_NAME`、`--skip-email`）
  - [x] `wp user create`（2人目、`--role=author`）
- [x] `chown -R nobody:nobody /var/www/html`
- [x] 最終行 `exec /usr/sbin/php-fpm84 -F`

▶ 検証（この時点では compose で mariadb と一緒に起動して確認するのが早い）:
```
docker exec -it <c> ps                                    # PID 1 が php-fpm: master
docker exec -it <c> ls /var/www/html                      # wp-config.php と wp-content がある
docker exec -it <c> wp user list --allow-root             # 2名、1名が administrator
docker exec -it <c> netstat -ltn                          # 0.0.0.0:9000 で待受（127.0.0.1 ではない）
```
- [x] コンテナを消して再起動 → 再インストールが走らないことを確認（冪等性）

---

## Phase 5 — NGINX コンテナ

### 5.1 Dockerfile
- [x] `FROM alpine:3.23`
- [x] `ARG DOMAIN_NAME`
- [x] `apk add --no-cache nginx openssl`
- [x] `openssl req -x509 -nodes -newkey rsa:2048 -days 365 -subj "/CN=${DOMAIN_NAME}" ...` で自己署名証明書を生成（SAN も付与）
- [x] `conf/default.conf` を `/etc/nginx/http.d/default.conf` に COPY（既定を置き換える）
- [x] `sed` で conf 内のドメインを `${DOMAIN_NAME}` に置換
- [x] `CMD ["nginx", "-g", "daemon off;"]`

### 5.2 `conf/default.conf`
- [x] `listen 443 ssl;`（**80 は書かない**）
- [x] `server_name` / `ssl_certificate` / `ssl_certificate_key`
- [x] `ssl_protocols TLSv1.2 TLSv1.3;` ← 要件の中核
- [x] `root /var/www/html;` / `index index.php;`
- [x] `location / { try_files $uri $uri/ /index.php?$args; }`
- [x] `location ~ \.php$ { fastcgi_pass wordpress:9000; include fastcgi.conf; }`

▶ 検証:
```
docker exec -it <c> nginx -t                        # 構文 OK
docker exec -it <c> ps                              # PID 1 が nginx: master process
curl -kI https://<login>.42.fr                      # 200 か 30x
openssl s_client -connect <login>.42.fr:443 -tls1_1 </dev/null   # 失敗する
openssl s_client -connect <login>.42.fr:443 -tls1_2 </dev/null   # 成功する
openssl s_client -connect <login>.42.fr:443 -tls1_3 </dev/null   # 成功する
curl -I http://<login>.42.fr                        # 接続拒否
```

> **502 Bad Gateway が出たら**: (1) `www.conf` の `listen` が `9000` になっているか、(2) 両コンテナが同じ network にいるか、(3) `fastcgi.conf` に `SCRIPT_FILENAME` が含まれているか、の順に確認する。

---

## Phase 6 — docker-compose.yml と Makefile による統合

### 6.1 docker-compose.yml
- [x] `services` に3つ。各サービスに `build` / `image: <name>:1.0` / `container_name` / `networks` / `restart: unless-stopped`
- [x] トップレベル `networks: inception (bridge)`
- [x] トップレベル `volumes`（`local` + `driver_opts` で `${DATA_PATH}/...`）
- [x] トップレベル `secrets`（`file: ../secrets/*.txt`）
- [x] `environment` はサービスごとに必要な変数だけ列挙（`env_file` で一括投入しない）
- [x] nginx にのみ `ports: ["443:443"]`
- [x] nginx の volume マウントは `:ro`
- [x] mariadb に `healthcheck`
- [x] wordpress に `depends_on: {mariadb: {condition: service_healthy}}`
- [x] nginx に `depends_on: [wordpress]`
- [x] `version:` キーは書かない

### 6.2 Makefile
- [x] `COMPOSE := docker compose --env-file srcs/.env -f srcs/docker-compose.yml`
- [x] `DATA_PATH` を `.env` から読む（直書きしない）
- [x] ターゲット: `all` / `check` / `dirs` / `up` / `down` / `re` / `clean` / `fclean` / `logs` / `ps`
- [x] `check`: `.env` と `secrets/*.txt` の存在＋`CHANGE_ME` が残っていないかを確認し、無ければ手順を表示して失敗
- [x] `dirs`: `mkdir -p $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress`
- [x] `.PHONY` を全ターゲットに設定

▶ 検証:
```
make            # 3コンテナが Up になる
docker ps       # 3つとも Up、公開ポートは nginx の 443 のみ
```
ブラウザで `https://<login>.42.fr` → WordPress のサイトが表示される（インストールウィザードが出たら Phase 4.3 の `wp core install` が動いていない）

実機検証（WSL2）: `make up`、`docker compose config --quiet`、`docker compose ps`、`docker volume inspect`、`curl -kI --resolve tasugiya.42.fr:443:127.0.0.1 https://tasugiya.42.fr/` が成功した。

---

## Phase 7 — 永続性・耐障害性・機密の確認

- [ ] 管理画面から投稿を1件作成する
- [x] `make down` → `make` → **投稿が残っている**
- [x] `docker volume inspect <project>_mariadb_data` → `device` が `/home/<login>/data/mariadb`
- [x] ホストデータディレクトリの直接`ls`確認は課題要件外として、Phase 7の合否判定から除外する
- [x] `docker exec wordpress kill -TERM 1` → 数秒後 `docker ps` で復帰している
- [x] `docker exec mariadb kill -TERM 1` → 復帰し、サイトも復旧する
- [x] `grep -rn 'tail -f\|sleep infinity\|while true' srcs/` → ヒットなし
- [x] `grep -rniE 'password|passwd' srcs/requirements/*/Dockerfile` → ヒットなし
- [x] `docker inspect mariadb | grep -i pass` → パスワードの値が出ない
- [x] 各コンテナで `docker exec <c> ps` → PID 1 が本体プロセス
- [x] `docker stop <c>` が即座に完了する（3コンテナとも）

▶ 2026-08-20 WSL2検証結果:

- 成功: WP-CLIによる投稿作成、`make down` → `make` 後の投稿維持、named volumeのdevice確認、無限ループ/Dockerfile/Git追跡secretの静的チェック、`make check`、entrypoint構文、PID 1、3コンテナの停止時間。
- 未実施: ブラウザの管理画面からの投稿作成（WP-CLIによる投稿作成で代替確認）。
- 成功: `docker inspect mariadb` にはsecretのマウントパスが表示されたが、パスワードの値は表示されなかった。
- 補足（合否対象外）: `/home/tasugiya/data/mariadb` は通常ユーザーの `ls` で `Permission denied` となった。
- 過去の補助検証: 手動停止扱いになる `docker kill wordpress/mariadb` では自動復帰せず、サイトがそれぞれ502/500を返した。
- テスト終了後、`make`で3サービスを起動状態に戻した。原因調査・修正は未実施。
- 検討したテスト方針: 手動停止扱いになる`docker kill`ではなく、予期しないPID 1終了を再現する`docker exec <container> kill -9 1`を使用する。
- 2026-08-20追加検証: 両コンテナで`docker exec ... kill -9 1`は終了コード0だったが、コンテナ停止・再起動時刻の変化を確認できず、PID 1終了後の自動復帰は未確認。サイトは継続して応答した。PID namespaceとPID 1の実体は確認済み。原因調査・修正は未実施。
- 方針再変更: PID namespace内からSIGKILLをPID 1へ送る方法は機能しなかったため、SIGTERMを使用する検証へ変更した。
- 成功: `docker exec wordpress kill -TERM 1`後、約2秒でWordPressが再起動し、サイトが応答した。
- 成功: `docker exec mariadb kill -TERM 1`後、約6秒でMariaDBが再起動・healthy化し、サイトが応答した。

---

## Phase 8 — ドキュメント作成

- [x] **README.md**（英語）
  - [x] 1行目: `*This project has been created as part of the 42 curriculum by <login>.*`（斜体）
  - [x] `Description`
  - [x] `Instructions`
  - [x] `Project description`: Docker の使い方 / 同梱ソース / 主要な設計判断
  - [x] 4つの比較: VM vs Docker / Secrets vs Env / Docker Network vs Host Network / Volumes vs Bind Mounts
  - [x] `Resources`: 公式ドキュメントのリンク **＋ AI をどのタスクに使ったかの明記**（v5.3 の新要件。忘れやすい）
- [x] **USER_DOC.md**（SPEC §9 の5項目）
- [x] **DEV_DOC.md**（SPEC §9 の6項目）
- [x] 3ファイルとも **リポジトリルート** に置く

▶ 検証: `ls README.md USER_DOC.md DEV_DOC.md` が3つとも通る。README を GitHub で表示して1行目が斜体になっている。

2026-08-20検証済み: 3ファイルの存在、READMEの1行目、必須見出し・比較項目、USER_DOCの5項目、DEV_DOCの6項目、`git diff --check`を確認した。コミットは未実施。

---

## Phase 9 — 校舎マシンでのリハーサル

**このフェーズを飛ばさない。** 開発環境でしか動かないプロジェクトは、レビュー当日に落ちる。

- [ ] 校舎マシンで VM を用意（Phase 1 と同一手順、または `sgoinfre` の VM を起動）
- [ ] **まっさらなディレクトリに `git clone`**
- [ ] `cp srcs/.env.example srcs/.env` → 値を埋める
- [ ] `secrets/*.txt` を作成
- [ ] `make`
- [ ] SPEC §11 の受入基準 20項目を **上から順にすべて実行**
- [ ] 所要時間を計測する（クローンから表示まで。5分以内が目標）
- [ ] つまずいた箇所があれば DEV_DOC.md のトラブルシュートに追記する
- [ ] 動作確認後の VM スナップショットを取る

---

## Phase 10 — ディフェンス準備

- [ ] `PROJECT_DEFINE.md` §5 のチェックリストを **口頭で** 通しで答える
  - 答えに詰まった項目: ________________
  - 詰まった項目について公式ドキュメントを読み直す
- [ ] レビューで叩く**コマンドの順番を1枚に書き出す**（受入基準を実演する流れ）
- [ ] Ch.IX の「小改修」に備えて、以下を想定練習する
  - [ ] WP ユーザーをもう1人増やす（どのファイルを触るか即答できるか）
  - [ ] ドメイン名を変更する（`.env` の1行 + 再ビルドで済むか）
  - [ ] TLS を 1.3 のみに変更する（`default.conf` の1行 + 再ビルド）
- [ ] `make fclean` → `make` が通ることを最後に一度確認（完全再構築）
- [ ] 最終コミット・push。`git log -p | grep -i password` が空であることを再確認

---

## 付録: よくある詰まりどころ

| 症状 | 典型原因 | 確認先 |
|---|---|---|
| コンテナが起動直後に Exit 0 | 本体をデーモン起動している / entrypoint に `exec` がない | Phase 3.3, 4.3, 5.1 |
| `docker stop` に10秒かかる | PID 1 がシェルで SIGTERM を転送していない | ENTRYPOINT が exec 形式か |
| 502 Bad Gateway | php-fpm が `127.0.0.1:9000` で待受 | Phase 4.2 |
| WordPress のインストール画面が出る | `wp core install` が実行されていない / 失敗している | `docker logs wordpress` |
| DB 接続エラー | `bind-address` / `skip-networking` / ユーザーが `'%'` でない | Phase 3.2, 3.3 |
| volume 作成に失敗 | `device` のホストディレクトリが存在しない | Makefile の `dirs` ターゲット |
| `/var/www/html` が空になる | ビルド時に volume マウント先へ展開している | Phase 4.1（`/usr/src/wordpress` を使う） |
| 校舎マシンで容量不足 | VM をホームディレクトリに置いた | `sgoinfre` / `goinfre` へ移動 |
| ポート 443 が使用中 | ホスト（VM）側で別の web サーバが動いている | `sudo ss -ltnp \| grep 443` |
