# PROJECT_DEFINE.md — Inception 要件定義

> 対象: 42school「Inception」subject v5.3 / **mandatory part のみ**
> 作成日: 2026-08-17
> 目的: subject の記述を「実装可能な要求」と「ディフェンス可能な根拠」に翻訳する

---

## 0. このドキュメントの位置づけ

subject は仕様書ではなく **課題文** である。「〜すべきでない」「〜について調べよ」といった示唆に留まる箇所が多く、そのままでは実装に落とせない。本書はそれらを以下の3層に分解して確定させる。

| 層 | 内容 |
|---|---|
| **REQ（要求）** | subject の記述から一意に読み取れる、満たさなければ落ちる条件 |
| **INTERP（解釈）** | 記述が曖昧な箇所について、課題の目的に照らして確定させた解釈 |
| **DEFENSE（防衛）** | レビューで「なぜそうしたのか」を聞かれたときの回答 |

**本プロジェクトの設計原則**（以降すべての判断の基準）:

1. **要件充足 > シンプルさ > 汎用性**。要件を満たさないシンプルさは無価値、要件を満たした上での過剰装飾も無価値。
2. **説明できないものは入れない**。動くが理由を語れないコードは、42のレビューでは減点でなく失格要因になりうる（subject Ch.IV 参照）。
3. **設定の単一情報源（single source of truth）**。同じ値を2箇所に書かない。
4. **暗黙の前提を作らない**。「たまたま動く」状態を作らず、なぜ動くかを構造で示す。

---

## 1. この課題が測っているもの

subject の Introduction は「Docker を使ってシステム管理の知識を広げる」としか書いていないが、要求の集合を見ると、測られている能力は次の4つに整理できる。

| 測定対象 | subject 上の現れ方 |
|---|---|
| **プロセスモデルの理解** | PID 1、`tail -f` 等の禁止、デーモン化の是非 |
| **境界の設計** | 1サービス1コンテナ、nginx なしの WordPress/MariaDB、443 のみの入口 |
| **状態の分離** | named volume 2つ、コンテナ再作成後もデータが残ること |
| **機密情報の扱い** | .env 必須、Dockerfile へのパスワード禁止、secrets 推奨、Git 混入で即失格 |

つまり **「3つのコンテナを動かす」課題ではなく「独立したプロセス群を協調させる最小のインフラを設計する」課題** である。この視点は「なぜこう作ったか」を問われたときの一貫した軸になる。

---

## 2. 前提用語の確定

### 2.1 `login`
subject 中の `login` はすべて **自分の 42 intra ログイン名**。本書では `<login>` と表記する。影響範囲は3箇所:

- ドメイン名 `<login>.42.fr`
- ホスト側データ配置 `/home/<login>/data`
- README 1行目の署名

> **確定タスク**: 実装開始前に `<login>` を確定し、`.env` の1変数として持たせ、他のファイルには直書きしない（原則3）。

### 2.2 "penultimate stable version"（最後から2番目の安定版）

**INTERP**: 「メジャー／マイナーの安定系列のうち、最新から1つ前の系列」を指す。パッチ版ではなく系列で数える。

2026-08-17 時点の事実（要・提出直前の再確認）:

| ディストリ | 最新安定系列 | **penultimate（採用対象）** |
|---|---|---|
| Alpine Linux | 3.24 系（3.24.0 = 2026-06-09 リリース） | **3.23 系** |
| Debian | 13 "trixie"（2025-08-09 リリース、現 stable） | **12 "bookworm"**（oldstable） |

- 確認先: `https://alpinelinux.org/releases/` / `https://www.debian.org/releases/`
- **DEFENSE**: 「latest は再現性がないため禁止。penultimate を指定するのは、最新系列の初期不具合を避けつつ、パッケージが十分に揃っている系列を選ぶため」と説明できるようにする。
- **注意**: この規則が適用されるのは **コンテナのベースイメージ** のみ。ホスト VM の OS は最新安定版でよい（VM は subject の制約対象外）。

### 2.3 「レビュー可能な状態」
本プロジェクトの完成条件は「動く」ではなく **「レビュアーの前で、クローン直後の状態から数分で立ち上がり、各要件を指差し確認できる」** こと。この定義は TODO.md の受入基準に直結する。

---

## 3. 要件の逐条定義

### R1. 仮想マシン上で実施すること

> *This project needs to be done on a Virtual Machine.*

**REQ**: Docker デーモンは VM のゲスト OS 上で動くこと。
**INTERP**: macOS/Windows の Docker Desktop は「内部的に VM を使っている」が、本要件を満たすとは見なされない。ホスト OS から独立したゲスト OS に SSH/コンソールでログインし、そこで `docker` が動く構成にする。
**DEFENSE**: 「VM = カーネルごと仮想化、コンテナ = カーネル共有のプロセス隔離。この課題は両者の違いを体感させるために VM を要求している」（README の VM vs Docker 比較節と一貫させる）。

### R2. ディレクトリ構成と Makefile

> *All the files required for the configuration... must be placed in a `srcs` folder.*
> *A Makefile is also required and must be located at the root... It must set up your entire application (i.e., it has to build the Docker images using docker-compose.yml).*

**REQ**:
- 設定ファイル一式は `srcs/` 配下。
- `Makefile` はリポジトリルート。
- `make`（デフォルトターゲット）だけでイメージビルド〜起動まで完了すること。

**INTERP**: 「Makefile が docker-compose.yml を呼び、docker-compose.yml が Dockerfile を呼ぶ」という3段の呼び出し関係を明示せよ、という指示（subject Ch.V の "The Dockerfiles must be called in your docker-compose.yml by your Makefile" と対応）。Makefile が `docker build` を直接叩く構成は要件違反。

**INTERP（secrets の位置）**: Ch.V のディレクトリ例では `secrets/` は **ルート直下**（`srcs/` の外）。これに従う。

### R3. docker compose / 1サービス1コンテナ / イメージ名

> *You have to use `docker compose`. Each Docker image must have the same name as its corresponding service. Each service has to run in a dedicated container.*

**REQ**:
- `docker compose`（v2、ハイフンなし）を使う。
- サービスは `nginx` / `wordpress` / `mariadb` の3つ。
- 各イメージ名 = サービス名。

**INTERP（`latest` 禁止との衝突）**: `image: mariadb` とだけ書くと Docker は自動的に `mariadb:latest` とタグ付けし、`docker images` に `latest` が現れる。一方 subject は "The latest tag is prohibited" と明記している。
→ **確定解釈**: イメージ**名**とイメージ**タグ**は別概念である。`image: mariadb:1.0` のように書けば、名前は `mariadb`（= サービス名）でタグは `latest` ではない、という両立が成り立つ。
**DEFENSE**: 「名前はサービス名と一致、タグは明示指定して `latest` を回避した。両要件を同時に満たす唯一の書き方」。

### R4. ベースイメージ

> *the containers must be built either from the penultimate stable version of Alpine or Debian.*
> *The latest tag is prohibited.*

**REQ**: `FROM alpine:3.23` または `FROM debian:bookworm`（2026-08 時点。§2.2 参照）。`FROM alpine` / `FROM alpine:latest` / `FROM debian:stable` は不可。
**INTERP**: `debian:bookworm-slim` のような variant タグも「bookworm 系列」なので許容されるが、`slim` を選ぶ積極的理由がなければ素直に `bookworm` でよい。3コンテナすべてで同一ベースを使う（比較・説明が単純になる）。

### R5. 既製イメージの禁止

> *It is then forbidden to pull ready-made Docker images, as well as using services such as DockerHub (Alpine/Debian being excluded from this rule).*

**REQ**: `nginx:*` / `wordpress:*` / `mariadb:*` / `php:*-fpm` などの公式イメージを `FROM` してはいけない。Alpine / Debian のベースイメージのみ許可。
**INTERP（何が「pull」か）**: 禁止されているのは **アプリケーションイメージの取得**。ベース OS のパッケージマネージャ（`apk` / `apt`）でのソフトウェア取得、および WordPress 本体や WP-CLI の HTTP ダウンロードは禁止対象ではない（そうでなければ課題自体が成立しない）。
**DEFENSE**: 「イメージの中身を自分で組み立てさせることで、公式イメージが裏でやっている初期化・権限設定・プロセス起動を自分で書かせるのが狙い」。

### R6. NGINX コンテナ

> *A Docker container that contains NGINX with TLSv1.2 or TLSv1.3 only.*
> *Your NGINX container must be the only entrypoint into your infrastructure via the port 443 only, using the TLSv1.2 or TLSv1.3 protocol.*

**REQ**:
1. TLS は 1.2 と 1.3 のみ有効（1.0 / 1.1 / SSLv3 は無効）。
2. ホストに公開するポートは **443 のみ**。80 番は listen すらしない。
3. 他のコンテナはホストにポートを公開しない。

**INTERP（証明書）**: subject は証明書の入手方法を規定していない。ローカルドメインなので **自己署名証明書** で足りる。ブラウザの警告は仕様どおり（レビュー時に説明できればよい）。
**INTERP（"only entrypoint"）**: docker-compose の `ports:` を持つのは nginx だけ、という構造要件。デバッグ目的で mariadb に `ports: - "3306:3306"` を残したまま提出すると要件違反になる（よくある事故）。
**DEFENSE**: 「`ssl_protocols TLSv1.2 TLSv1.3;` の1行で、それ以前のプロトコルをすべて拒否している。検証は `openssl s_client -tls1_1` が失敗し `-tls1_2` / `-tls1_3` が成功することで示せる」。

### R7. WordPress + php-fpm コンテナ

> *A Docker container that contains WordPress + php-fpm (it must be installed and configured) only, without nginx.*

**REQ**:
- WordPress 本体と php-fpm が入っている。
- **Web サーバは入れない**（nginx / apache を `apk add` しない）。
- 「installed and **configured**」= 素の WordPress を置くだけでなく、DB 接続設定（`wp-config.php`）とサイト初期化（管理者・一般ユーザー作成）まで済んでいること。ブラウザで開いた時に WordPress のインストールウィザードが出る状態は **未達**。

**INTERP（設定手段）**: `wp-config.php` を手書きテンプレートで埋める方法と、WP-CLI（`wp config create` / `wp core install`）を使う方法がある。後者を採用する。理由: (a) salt キーが自動生成される、(b) 冪等性チェック（`wp core is-installed`）が1コマンドで書ける、(c) ユーザー作成まで同じ道具で完結する。
**INTERP（php-fpm の待受）**: nginx とは別コンテナなので、Unix ソケットではなく **TCP 9000** で待ち受け、`127.0.0.1` ではなく全インタフェース（`9000`）にバインドする必要がある。ディストリの既定値は `127.0.0.1:9000` なので **必ず変更が要る**。

### R8. MariaDB コンテナ

> *A Docker container that contains MariaDB only, without nginx.*

**REQ**: MariaDB サーバのみ。Web サーバを含めない。
**INTERP（ネットワーク待受）**: 既定では localhost のみを向いている（ディストリによっては `skip-networking` が入る）。WordPress コンテナから TCP で繋ぐため、`bind-address=0.0.0.0` かつ `skip-networking` 無効が必要。
**INTERP（初期化）**: データディレクトリは volume で永続化されるため、**初回起動時のみ** 初期化し、2回目以降はスキップする分岐が必須。ここを書かないと再起動のたびに初期化を試みて失敗する。

### R9. ボリューム

> *A volume that contains your WordPress database. A second volume that contains your WordPress website files.*
> *You must use Docker **named volumes** for these two persistent storages. Bind mounts are **not allowed** for these volumes.*
> *Both named volumes must store their data inside `/home/login/data` on the host machine.*

**この3行は一見矛盾している。** 素の named volume は `/var/lib/docker/volumes/` に置かれ、`/home/<login>/data` には行かない。一方、`- /home/<login>/data/db:/var/lib/mysql` と書くのは禁止された bind mount である。

**INTERP（確定解）**: compose の **トップレベル `volumes:` で named volume を宣言し、`local` ドライバの `driver_opts` でホストパスを指定する**。

```yaml
volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/<login>/data/mariadb
```

- Docker 公式ドキュメント（Compose file reference / volumes）が "named bind mount" として明示的に紹介しているパターンである。
- サービス側の記述は `- mariadb_data:/var/lib/mysql` という **named volume の参照** であり、`services.*.volumes` に生のホストパスを書く bind mount ではない。
- **禁止されているのは「bind mount という記法／宣言方法」であり、named volume の実体保管先の指定はボリューム管理の一部** — と読むのが、3行すべてを同時に満たす唯一の解釈。
- 制約: `device` に指定するホストディレクトリは **事前に存在していなければならない**（Docker 公式が明記）。→ Makefile で `mkdir -p` する責務が発生する。

**DEFENSE**: 「`docker volume ls` に named volume として現れ、`docker volume inspect` で `device=/home/<login>/data/...` が確認できる。サービス定義側にホストパスは一切書いていない」と、2つのコマンドで示せる状態にしておく。

**代替案（不採用）**: Docker デーモンの `data-root` 自体を `/home/<login>/data` に変更する方法。要件は満たすが、VM 全体の設定変更でありプロジェクト外への副作用が大きく、レビュアーへの説明コストも高い。原則2に反するため不採用。

### R10. ネットワーク

> *A `docker-network` that establishes the connection between your containers.*
> *using `network: host` or `--link` or `links:` is forbidden. The network line must be present in your docker-compose.yml file.*

**REQ**:
- compose に **トップレベル `networks:`** 宣言があり、3サービスがそれに属する。
- `network_mode: host` / `links:` / `--link` を使わない。

**INTERP**: 禁止されている `links:` は「レガシーなコンテナ間接続機構」。user-defined bridge network 上では **サービス名が Docker 内蔵 DNS で解決される** ので `links:` は不要。この事実そのものが問われている。
**DEFENSE**: 「WordPress は `mariadb:3306`、nginx は `wordpress:9000` という名前で相手を呼んでいる。これは user-defined network の埋め込み DNS による解決で、`links:` は不要かつ非推奨」。
**注記**: `depends_on:` は `links:` とは無関係な起動順序制御であり、禁止対象ではない。

### R11. 再起動ポリシー

> *Your containers have to restart in case of a crash.*

**REQ**: 各サービスに `restart:` を設定する。
**INTERP**: 「クラッシュ時に復帰する」ことが要件。候補は `always` / `unless-stopped` / `on-failure`。
- `on-failure`: 異常終了時のみ再起動。要件に最も忠実。
- `unless-stopped`: 明示停止していない限り再起動。`make down` の意図は尊重される。
- `always`: 明示停止しても daemon 再起動時に復活する。運用上やや強すぎる。

→ **確定**: `unless-stopped` を採用（明示的停止の意図を壊さずクラッシュ復帰を保証）。レビューでは `docker kill <container>` → `docker ps` で復帰を実演できる。

### R12. PID 1 / デーモン化 / 無限ループ禁止 ★最重要

> *A Docker container is not a virtual machine. Thus, it is not recommended to use any hacky patches based on 'tail -f' and similar methods... Read about how daemons work and whether it's a good idea to use them or not.*
> *Your containers must not be started with a command running an infinite loop... prohibited hacky patches: `tail -f`, `bash`, `sleep infinity`, `while true`.*
> *Read about PID 1 and the best practices for writing Dockerfiles.*

subject 中で最も曖昧かつ最も配点の重い箇所。以下に意図と要求を確定する。

**背景にある問題**:
コンテナのライフサイクルは **PID 1 のプロセスの寿命** と等しい。従来のデーモンは「起動 → fork → 親プロセス終了」という動作をするため、コンテナ内でデーモンとして起動すると **PID 1 が即座に終了 → コンテナが終了** する。これを回避しようとして「本体をデーモン起動し、PID 1 には `tail -f /dev/null` を置いてコンテナを生かす」という回避策が広く出回っている。これが禁止されている "hacky patch"。

**なぜダメか（DEFENSE の中身）**:
1. **ヘルスの意味が壊れる**: 本体プロセスが死んでも `tail` は生きているため、コンテナは「動いている」ままになる。R11 の restart ポリシーが機能しなくなる。
2. **シグナルが届かない**: `docker stop` は PID 1 に SIGTERM を送る。PID 1 が `tail` や `sh` だと本体に転送されず、10秒後に SIGKILL される（＝DB なら不正終了）。
3. **ログが取れない**: `docker logs` は PID 1 の stdout/stderr を拾う。デーモン化すると本体のログはコンテナ内のファイルに落ち、外から見えない。

**REQ（確定）**:
1. 各コンテナの PID 1 は **そのサービスの本体プロセス** であること。
   - nginx → `nginx -g "daemon off;"`
   - php-fpm → `php-fpm<ver> -F`（`--nodaemonize`。デーモン化せず前景に留まる）
   - MariaDB → `mariadbd`（前景動作が既定）
2. Dockerfile の `ENTRYPOINT` / `CMD` は **exec 形式（JSON 配列）** で書く。shell 形式は `/bin/sh -c` を挟むためシグナルが本体に届かない（Docker 公式 Dockerfile reference が明記）。
3. entrypoint スクリプトを使う場合、最終行は必ず **`exec <本体コマンド>`**。`exec` を付けないとスクリプトの `sh` が PID 1 のまま残り、(2) と同じ問題が起きる。
4. `tail -f` / `sleep infinity` / `while true` / 単体の `bash` を起動コマンドに使わない。

**INTERP（起動待ちループの扱い）**: 「WordPress が MariaDB の準備完了を待つ」処理は必要になる。ここで `until mysqladmin ping; do sleep 1; done` と書くのは、**終了条件のある有限ループ** であり subject が禁じる「コンテナを生かし続けるための無限ループ」とは別物。とはいえ疑義を招くため、**本プロジェクトでは compose の `healthcheck` + `depends_on: condition: service_healthy` を第一選択とする**（宣言的で、スクリプトにループを書かずに済む）。回数上限つきリトライは代替手段として許容する。

### R13. WordPress ユーザー

> *In your WordPress database, there must be two users, one of them being the administrator. The administrator's username can't contain admin/Admin or administrator/Administrator.*

**REQ**:
- WordPress のユーザーが **2名**（DB のユーザーではなく WordPress のユーザー）。
- 1名は管理者ロール。
- 管理者のユーザー名に `admin` / `Admin` / `administrator` / `Administrator` を **部分文字列として含めない**。`admin-123`, `wpadmin`, `siteadministrator` はすべて不可。

**INTERP**: 2人目のロールは指定なし。`author` または `subscriber` とする。
**確定**: 管理者名は `<login>` 由来の文字列（例: `tasu_boss`）等、`admin` を含まないものにする。レビュー時に `wp user list` で2名とロールを提示できるようにする。

### R14. ドメイン名

> *you have to configure your domain name so it points to your local IP address. This domain name must be `login.42.fr`.*

**REQ**: VM 上で `<login>.42.fr` が `127.0.0.1` に解決され、`https://<login>.42.fr` で WordPress が表示される。
**INTERP**: DNS サーバを立てる必要はない。**ゲスト VM の `/etc/hosts` に1行追加** すればよい。
**INTERP（所在）**: この設定は「プロジェクトの成果物」ではなく「VM のセットアップ」に属する。`sudo` が必要なので Makefile の必須経路には入れず、VM セットアップ手順（および DEV_DOC.md）に記載する。
**注意**: nginx の `server_name` とも一致させること。証明書の CN も同じドメインにしておくと説明が一貫する。

### R15. 機密情報の扱い ★失格リスク

> *No password must be present in your Dockerfiles. It is mandatory to use environment variables. Also, it is mandatory to use a `.env` file... It is strongly recommended that you use Docker secrets... Any credentials, API keys, or passwords found in your Git repository (outside of properly configured secrets) will result in project failure.*

**REQ（絶対条件）**:
1. Dockerfile にパスワードを書かない（`ENV MYSQL_PASSWORD=...` も不可）。
2. `srcs/.env` が存在し、環境変数がそこに定義されている。
3. パスワード類が Git リポジトリに含まれない。

**この2つの要件は緊張関係にある**（.env は必須、しかし credentials は Git に置けない）。**確定解**:

| 情報の種類 | 置き場所 | Git 追跡 |
|---|---|---|
| 非機密の設定値（ドメイン名、DB 名、DB ユーザー名、サイト名、WP ユーザー名、メールアドレス、データ配置パス） | `srcs/.env` | **する**（ただし §4 の判断を参照） |
| パスワード類（DB パスワード、WP 管理者/一般ユーザーのパスワード） | `secrets/*.txt` → Docker secrets として `/run/secrets/<name>` にマウント | **しない**（`.gitignore`） |

**INTERP（.env を Git に含めるか）**: 「credentials が入っていない .env」なら追跡しても失格条件には触れない。しかし .env にパスワードを書く実装例が多く、レビュアーの目には「.env = 危険」と映りやすい。
→ **確定**: `.env` も **`.gitignore` に入れ、`srcs/.env.example` をテンプレートとして追跡する**。理由: (a) 誤ってパスワードを書き足しても事故らない、(b) 「機密は一切コミットしない」という単一のルールで運用でき、説明が単純（原則1・4）。
**DEFENSE**: 「.env はコミットしていない。代わりに `.env.example` とセットアップ手順を用意した。git log 全体を grep してもパスワードは出てこない」。

**INTERP（env と secrets の使い分け）**:
- 環境変数は `docker inspect` やプロセスの環境、ログに露出しうる。子プロセスにも自動的に継承される。
- Docker secrets はファイルとして `/run/secrets/<name>` にマウントされ、**そのサービスに明示的に許可した場合のみ** 見える。
→ 「機密か否か」ではなく「露出面の広さ」で使い分けている、と説明する。これは README の "Secrets vs Environment Variables" 節にそのまま使える。

### R16. README 要件

**REQ**（Ch.VI、すべて必須）:
1. 1行目が **斜体** で `This project has been created as part of the 42 curriculum by <login1>.`
2. `Description` 節（目的と概要）
3. `Instructions` 節（インストール・実行方法）
4. `Resources` 節（参考文献 + **AI をどのタスク・どの部分に使ったかの記述**）
5. `Project description` 節: Docker の使い方と同梱ソースの説明、主要な設計判断、および以下4つの比較
   - Virtual Machines vs Docker
   - Secrets vs Environment Variables
   - Docker Network vs Host Network
   - Docker Volumes vs Bind Mounts
6. **英語で書くこと**

**注意**: 4の「AI 利用の記述」は v5.3 で追加された項目で、書き漏らしやすい。本プロジェクトで AI を使った範囲（要件整理・調査・ドキュメント草稿など）を正直に列挙する。

### R17. 検証前提ドキュメント（Ch.VII）

**REQ**: リポジトリルートに Markdown で2ファイル。**これが無いと評価が始まらない可能性がある**（"Prerequisites for validation"）。

| ファイル | 必須内容 |
|---|---|
| `USER_DOC.md` | スタックが提供するサービスの説明 / 起動と停止 / サイトと管理画面へのアクセス / 認証情報の所在と管理 / サービスが正常稼働しているかの確認方法 |
| `DEV_DOC.md` | ゼロからの環境構築（前提・設定ファイル・secrets） / Makefile と Compose によるビルドと起動 / コンテナとボリュームの管理コマンド / データの保存先と永続化の仕組み |

**INTERP**: README との重複を恐れない。README は「何のプロジェクトか」、USER_DOC は「使う人向けの操作手順」、DEV_DOC は「再構築する人向けの内部仕様」と役割を分ける。

### R18. 評価時の小改修（Ch.IX）

**REQ**: レビュー中に「少し動作を変えて」と言われる可能性がある。
**INTERP**: 想定される改修は「WP ユーザーをもう1人足す」「ポートやドメインを変える」「TLS 設定を変える」「ボリュームのマウント先を変える」程度。
→ **設計要求**: 設定値がすべて `.env` / secrets / 各 conf ファイルに外出しされていること。ハードコードを減らしておけば、その場での改修が数行で済む。これは R12・原則3 と同じ方向を向いている。

---

## 4. 曖昧な示唆の解釈まとめ

subject が「調べよ」としか言っていない箇所について、本プロジェクトが採用する回答を1箇所にまとめる。レビュー想定問答の骨子でもある。

| subject の示唆 | 背景にある問題 | 本プロジェクトの回答 |
|---|---|---|
| "A Docker container is not a virtual machine" | コンテナを「小さな VM」と誤解すると、init / cron / sshd を詰め込みたくなる | コンテナ = **1つのプロセスを実行する隔離環境**。init システムは持たず、PID 1 は本体プロセス |
| "Read about how daemons work and whether it's a good idea" | 従来デーモンの fork + 親終了はコンテナと相性が悪い | 各ソフトの **前景実行オプション** を使う（`daemon off` / `-F`）。デーモン化はしない |
| "Read about PID 1" | シグナル伝播・ゾンビ回収・ログ収集がすべて PID 1 に依存 | exec 形式の ENTRYPOINT + スクリプト末尾の `exec` で、本体を PID 1 にする |
| "best practices for writing Dockerfiles" | レイヤ肥大・キャッシュ無効化・秘密情報の埋め込み | `apk add --no-cache` を1つの RUN にまとめる / `.dockerignore` を置く / パスワードは build 時に渡さず runtime に secrets で渡す |
| named volume なのに `/home/login/data` | 素の named volume はホストパスを選べない | `local` ドライバ + `driver_opts`（§R9） |
| ".env 必須" と "credentials を Git に置くと失格" | 両立が自明でない | .env は非機密のみ・かつ `.gitignore`、パスワードは Docker secrets（§R15） |

---

## 5. ディフェンス想定質問チェックリスト

実装が終わったら、以下すべてに **口頭で・詰まらずに** 答えられる状態を目標とする。答えられない項目があれば、その部分は設計を見直すか理解を補う。

**プロセスとライフサイクル**
- [ ] 各コンテナの PID 1 は何か。`docker exec <c> ps` で示せるか
- [ ] `docker stop` を打つと各コンテナで何が起きるか
- [ ] なぜ `tail -f /dev/null` を使ってはいけないのか（3つの理由）
- [ ] entrypoint スクリプトの最後に `exec` を付ける理由
- [ ] ENTRYPOINT と CMD の違い、exec 形式と shell 形式の違い

**ネットワーク**
- [ ] WordPress は MariaDB をどうやって見つけているか
- [ ] `links:` と user-defined network の違い
- [ ] `network_mode: host` にすると何が壊れるか（ポート衝突・隔離の喪失）
- [ ] nginx → php-fpm は何プロトコルか（HTTP ではなく FastCGI）

**ストレージ**
- [ ] named volume と bind mount の違い
- [ ] このボリュームのデータは実際にホストのどこにあるか（`docker volume inspect` で提示）
- [ ] `make down` してもデータが消えないのはなぜか。消すにはどうするか

**機密情報**
- [ ] .env と Docker secrets の使い分けの基準
- [ ] `docker inspect` で MariaDB のパスワードは見えるか（見えないことを実演）
- [ ] Dockerfile にパスワードを書くと何が起きるか（イメージ履歴に残る）

**TLS / WordPress**
- [ ] TLS 1.1 を弾いていることをどう証明するか
- [ ] 証明書はいつ・どこで生成しているか。自己署名で問題ない理由
- [ ] WordPress ユーザーは何人いて、それぞれのロールは何か
- [ ] 初回起動と2回目以降で entrypoint の挙動がどう変わるか

**Docker 一般（README の比較節と対応）**
- [ ] VM と Docker の違いを、この課題の構成に即して説明できるか

---

## 6. スコープ外（本プロジェクトで実施しないこと）

- **bonus part 全体**（redis / FTP / static site / Adminer / 任意サービス）。subject は「mandatory が完璧でなければ bonus は一切評価されない」と明記しており、mandatory の完成度に資源を集中する。
- bonus 用の `srcs/requirements/bonus/` ディレクトリも作らない（Ch.V のディレクトリ例に登場するが、これは bonus 実施時の例示であり必須ではない）。
- 本番運用向けの強化（Let's Encrypt、ログ収集、バックアップ、リソース制限）。要件外であり、原則1に反する。

---

## 7. 参考にした一次情報

- Docker: Compose file reference — volumes / secrets, Dockerfile reference（ENTRYPOINT と PID 1・シグナル）, build checks（JSONArgsRecommended）
  - `https://docs.docker.com/reference/compose-file/volumes/`
  - `https://docs.docker.com/compose/how-tos/use-secrets/`
  - `https://docs.docker.com/reference/dockerfile/`
- nginx: Configuring HTTPS servers / ngx_http_ssl_module（`ssl_protocols`）
  - `https://nginx.org/en/docs/http/configuring_https_servers.html`
  - `https://nginx.org/en/docs/http/ngx_http_ssl_module.html`
- PHP: FastCGI Process Manager (FPM) / php-fpm(8)（`-F, --nodaemonize`）
  - `https://www.php.net/manual/en/install.fpm.php`
- MariaDB: mariadb-install-db（`--datadir` / `--user` / `--extra-file` / `--auth-root-authentication-method`）
  - `https://mariadb.com/docs/server/clients-and-utilities/deployment-tools/mariadb-install-db`
- Alpine Linux wiki: MariaDB（設定ファイル配置、`bind-address` / `skip-networking`）
  - `https://wiki.alpinelinux.org/wiki/MariaDB`
- WP-CLI handbook: Installing（PHAR 配布、PHP 7.2.24+ 要件）
  - `https://make.wordpress.org/cli/handbook/guides/installing/`
- リリース情報: `https://alpinelinux.org/releases/` / `https://www.debian.org/releases/`
