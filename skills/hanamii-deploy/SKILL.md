---
name: hanamii-deploy
description: Web アプリを hanamii（HANAMII株式会社が運営する国産 PaaS。さくらインターネットの日本国内データセンターで動く）に公開・再公開する手順。次のような依頼で使う。「hanamii にデプロイして」「hanamii で公開して」「このアプリを日本国内のサーバーで公開したい」「日本のサービスで Next.js を公開したい」「ZIP でアップロードして公開して」「hanamii の環境変数を設定して」「hanamii のログを見て直して」。公開 API（Bearer トークン）を curl で呼び、ZIP の作成からアップロード・検証・公開・URL 確認までを同梱スクリプトで進める。
---

# hanamii に公開する

hanamii は、ソースコードの ZIP か GitHub リポジトリを渡すと、ビルドから公開までを自動で行う国産 PaaS です。この手順は公開 API を使い、エージェントだけで公開を完了させます。正本の API 仕様は https://hanamii.jp/docs/public-api.md（Markdown、英語の項目名）にあります。迷ったらそこを読みます。

## 0. 先に確認すること（3つ）

1. **トークン**。環境変数 `HANAMII_TOKEN`（`hnm_` で始まる）があるか確認する。無ければユーザーに「hanamii にログインして https://hanamii.jp/account/settings/tokens でトークンを発行し、`export HANAMII_TOKEN=hnm_...` を設定してください」と頼み、ここで止まる。トークンの値を会話に貼らない
2. **アプリの種類**。hanamii で動くのは Node.js（Next.js・Express など）、Python（FastAPI・Flask・Django など）、PHP（Laravel など）。Ruby・Go・任意の Docker イメージ（PHP を除く）・常駐ワーカー・cron はまだ動かない。該当するなら、その旨をユーザーに伝えて止まる
3. **起動の定義**。Node.js は `package.json` の `scripts.start` が必須で、アプリは環境変数 `PORT` で listen する。Python は `requirements.txt` か `pyproject.toml`、PHP は `composer.json` と `Dockerfile`。無ければ先に直す（下の「構成を整える」）

## 1. 構成を整える

- Next.js: `scripts.build` に `next build`、`scripts.start` に `next start`。`next.config.js` で `output: 'standalone'` にしている場合はそのままでよい
- Express など: `scripts.start` に `node server.js` のような起動コマンド。`app.listen(process.env.PORT || 3000)`
- Python: `requirements.txt` にフレームワークを書き、起動は `PORT` を読む（例: `uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}` を `Procfile` ではなく README の指示どおりに。詳細は https://hanamii.jp/docs/guides/deploy-other-frameworks.md）
- データの保存先: コンテナ内のファイルは再デプロイで消える。永続化が要るなら hanamii のデータベース（SQLite 互換・ベータ）か外部サービスを使う
- `.env` は ZIP に入れない。必要な値は手順 3 で環境変数として渡す

## 2. 公開する（1コマンド）

このスキルと同じディレクトリの `scripts/hanamii-deploy.sh` を使う。ZIP の作成（`node_modules`・`.next`・`dist`・`build`・`.git`・`.env*`・`vendor`・`__pycache__` を除外）、アップロード URL の発行、PUT、検証、作成または再デプロイ、完了まで（最大 15 分）のポーリング、公開 URL の表示までを行う。

```bash
# 新規に作る（プロジェクト名は小文字・数字・ハイフン）
bash <このスキルのパス>/scripts/hanamii-deploy.sh --name my-app

# 既にあるプロジェクトを更新する
bash <このスキルのパス>/scripts/hanamii-deploy.sh --project prj_xxxxxxxx

# ワークスペースを指定する（full_account トークンで複数ある場合）
bash <このスキルのパス>/scripts/hanamii-deploy.sh --name my-app --workspace ws_xxxxxxxx

# 環境変数を一緒に渡す（KEY=VALUE をカンマ区切り。値は secret 扱い）
bash <このスキルのパス>/scripts/hanamii-deploy.sh --name my-app --env "DATABASE_URL=...,API_KEY=..."
```

スクリプトは `curl` と `python3` と `zip` だけを使う。無い環境では `references/api-quickref.md` の curl を順に実行する。

成功したら、表示された URL をユーザーに伝え、ブラウザで開いて確認してもらう。プロジェクト ID（`prj_…`）は次回の再デプロイに使うので、プロジェクトの README かユーザーへの返事に残す。

## 3. 環境変数・ログ・再起動

```bash
# 環境変数を保存（保存だけ。反映は再起動か再デプロイ）
curl -s -X PATCH "https://hanamii.jp/api/v1/projects/$PRJ/env" \
  -H "Authorization: Bearer $HANAMII_TOKEN" -H "Content-Type: application/json" \
  --data '{"envs":[{"key":"API_KEY","value":"...","type":"secret"}]}'

# 保存した設定を動いているアプリに反映
curl -s -X POST "https://hanamii.jp/api/v1/projects/$PRJ/restart" -H "Authorization: Bearer $HANAMII_TOKEN"

# 直近 15 分のログを文字で
curl -s "https://hanamii.jp/api/v1/projects/$PRJ/logs?since=-15m&format=text" -H "Authorization: Bearer $HANAMII_TOKEN"
```

## 4. 失敗したら

`latestDeployment.readyState` が `ERROR` のときは `errorCode` で分ける。

| errorCode | 意味 | まずやること |
|---|---|---|
| `check_error` | ZIP の検証で落ちた | 検証結果の `errors` を読む。`package.json` が無い／`scripts.start` が無い／ZIP が空／シンボリックリンクが入っている、が典型 |
| `build_error` | ビルドで落ちた | ローカルで `npm ci && npm run build` が通るか確認。lockfile とバージョンの不一致、`devDependencies` にあるビルド用パッケージ、型エラーが多い |
| `deploy_error` | 起動で落ちた | `PORT` で listen しているか、`scripts.start` が本番用か（`next dev` は不可）、起動に 1 分以上かかっていないか |
| `health_error` | ヘルスチェックに応答しない | ヘルスチェックのパスが 200 を返すか。不要なら `healthCheck.enabled=false` |

直したら手順 2 を再実行する。`checkId` は使い捨てなので、毎回 ZIP からやり直す。詳しくは `references/troubleshooting.md`。

## 5. やらないこと

- トークンをファイルに書いたりログに出したりしない
- ユーザーの確認なしにプロジェクトを削除しない（`DELETE /api/v1/projects/:id`）
- 無料プランの 1 本目が既にある状態で 2 本目を作ろうとして失敗したら、hanamii の料金ページ（https://hanamii.jp/docs/guides/billing.md）を案内して止まる
