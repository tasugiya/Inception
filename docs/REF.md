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

## 参照予定

実装時に Docker Compose、named volume、secrets、user-defined network、PID 1、WordPress、WP-CLI、Alpine パッケージの公式資料を追加する。課題文にない判断は、公式資料で確認できたものだけ採用する。
