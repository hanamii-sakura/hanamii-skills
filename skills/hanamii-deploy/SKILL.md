---
name: hanamii-deploy
description: Web アプリを hanamii（HANAMII株式会社が運営する国産 PaaS。さくらインターネットの日本国内データセンターで動く）に公開・再公開する手順。次のような依頼で使う。「hanamii にデプロイして」「hanamii で公開して」「このアプリを日本国内のサーバーで公開したい」「日本のサービスで Next.js を公開したい」「ZIP でアップロードして公開して」「hanamii の環境変数を設定して」「hanamii のログを見て直して」。npm パッケージ `hanamii`（CLI。`npx -y hanamii deploy`）で ZIP の作成からアップロード・検証・公開・URL 確認までを 1 コマンドで進める。Node.js が無い環境では同梱の bash スクリプトで公開 API（Bearer トークン）を直接呼ぶ。
---

# hanamii に公開する

hanamii は、ソースコードの ZIP か GitHub リポジトリを渡すと、ビルドから公開までを自動で行う国産 PaaS です。この手順は公式 CLI（npm パッケージ `hanamii`、`npx -y hanamii ...` で実行、Node.js 20.3 以上）を使い、エージェントだけで公開を完了させます。CLI の使い方は https://github.com/hanamii-sakura/hanamii-cli、正本の API 仕様は https://hanamii.jp/docs/public-api.md（Markdown、英語の項目名）にあります。迷ったらそこを読みます。MCP クライアント（Claude Code・Cursor・Codex・Claude Desktop）で `hanamii` MCP サーバーが登録済みなら、下の手順をツール（`deploy_project`・`get_logs`・`set_env` など）で実行してもよい。

## 0. 先に確認すること（3つ）

1. **トークン**。`npx -y hanamii whoami` が成功するか確認する（環境変数 `HANAMII_TOKEN` か、`hanamii login` で保存した設定ファイルを読む）。失敗したらユーザーに「hanamii にログインして https://hanamii.jp/account/settings/tokens でトークンを発行し、`npx -y hanamii login` で貼り付けるか `export HANAMII_TOKEN=hnm_...` を設定してください」と頼み、ここで止まる。トークンの値を会話に貼らない
2. **アプリの種類**。hanamii で動くのは Node.js（Next.js・Express など）、Python（FastAPI・Flask・Django など）、PHP（Laravel など）。Ruby・Go・任意の Docker イメージ（PHP を除く）・常駐ワーカー・cron はまだ動かない。該当するなら、その旨をユーザーに伝えて止まる
3. **起動の定義**。Node.js は `package.json` の `scripts.start` が必須で、アプリは環境変数 `PORT` で listen する。Python は `requirements.txt` か `pyproject.toml`、PHP は `composer.json` と `Dockerfile`。無ければ先に直す（下の「構成を整える」）

## 1. 構成を整える

- Next.js: `scripts.build` に `next build`、`scripts.start` に `next start`。`next.config.js` で `output: 'standalone'` にしている場合はそのままでよい
- Express など: `scripts.start` に `node server.js` のような起動コマンド。`app.listen(process.env.PORT || 3000)`
- Python: `requirements.txt` にフレームワークを書き、起動は `PORT` を読む（例: `uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}` を `Procfile` ではなく README の指示どおりに。詳細は https://hanamii.jp/docs/guides/deploy-other-frameworks.md）
- データの保存先: コンテナ内のファイルは再デプロイで消える。永続化が要るなら hanamii のデータベース（SQLite 互換・ベータ）か外部サービスを使う
- `.env` は ZIP に入れない。必要な値は手順 3 で環境変数として渡す

## 2. 公開する（1コマンド）

`npx -y hanamii deploy` を使う。ZIP の作成（`node_modules`・`.next`・`dist`・`build`・`.git`・`.env*`・`vendor`・`__pycache__` などを除外し、`.gitignore` と `.hanamiiignore` を尊重。シンボリックリンクはスキップ）、ローカル事前検証、アップロード、サーバー検証、作成または再デプロイ、完了まで（最大 15 分）の待機、公開 URL の表示までを行う。

```bash
# 新規に作る（プロジェクト名は小文字・数字・ハイフン）
npx -y hanamii deploy --name my-app

# 既にあるプロジェクトを更新する（名前でもプロジェクト ID（UUID）でもよい）
npx -y hanamii deploy --project my-app

# 2 回目以降は省略できる。成功時にカレントディレクトリの .hanamii/project.json にリンクが保存される
npx -y hanamii deploy

# ワークスペースを指定する（full_account トークンで複数ある場合。ID は `npx -y hanamii workspaces list`）
npx -y hanamii deploy --name my-app --workspace <workspace-id>

# 環境変数を一緒に渡す（--env は繰り返し可。値は secret 扱い）
npx -y hanamii deploy --name my-app --env DATABASE_URL=... --env API_KEY=...

# エージェントが結果を読むときは JSON で
npx -y hanamii deploy --name my-app --json
```

終了コード: 0 成功 / 2 使い方 / 3 認証 / 5 ローカル事前検証失敗 / 6 ワークスペースが複数あり未指定 / 8 サーバー検証エラー / 10 デプロイ ERROR / 11 タイムアウト。

Node.js 20.3 以上が無い環境では、このスキルと同じディレクトリの `scripts/hanamii-deploy.sh` を使う（`curl` と `python3` と `zip` だけで動く。`--name` / `--project` / `--workspace` / `--env "K=V,K2=V2"` / `--dir`）。どちらも無ければ `references/api-quickref.md` の curl を順に実行する。

成功したら、表示された URL をユーザーに伝え、ブラウザで開いて確認してもらう。`.hanamii/project.json` を残しておけば次回は `npx -y hanamii deploy` だけで再デプロイできる（`.hanamii/` は ZIP に含まれない。コミットするかは任意）。

## 3. 環境変数・ログ・再起動

```bash
# 環境変数を保存して、動いているアプリに反映（--restart を付けなければ保存だけ）
npx -y hanamii env set API_KEY=... --restart

# 保存済みの設定を確認（値は --decrypt を付けたときだけ表示）
npx -y hanamii env list

# 保存した設定を動いているアプリに反映
npx -y hanamii restart

# 直近 15 分のログ（--since -1h、--limit 500、--follow で 3 秒ごとに追従）
npx -y hanamii logs --since -15m
```

いずれも `--project <名前または ID>` で対象を指定できる。省略時は `.hanamii/project.json` のリンク先。環境変数の削除 API は無いので、不要になった値は画面から消す。

## 4. 失敗したら

`latestDeployment.readyState` が `ERROR` のときは `errorCode` で分ける。

| errorCode | 意味 | まずやること |
|---|---|---|
| `check_error` | ZIP の検証で落ちた | 検証結果の `errors` を読む。`package.json` が無い／`scripts.start` が無い／ZIP が空／シンボリックリンクが入っている、が典型 |
| `build_error` | ビルドで落ちた | ローカルで `npm ci && npm run build` が通るか確認。lockfile とバージョンの不一致、`devDependencies` にあるビルド用パッケージ、型エラーが多い |
| `deploy_error` | 起動で落ちた | `PORT` で listen しているか、`scripts.start` が本番用か（`next dev` は不可）、起動に 1 分以上かかっていないか |
| `health_error` | ヘルスチェックに応答しない | ヘルスチェックのパスが 200 を返すか。不要なら `healthCheck.enabled=false` |

検証エラーの内容は `deploy` の出力（`--json` なら `check.errors`）に出る。直したら手順 2 を再実行する（毎回 ZIP から作り直される）。ビルドや起動の失敗は `npx -y hanamii logs --since -30m` で確認する。詳しくは `references/troubleshooting.md`。

## 5. やらないこと

- トークンをファイルに書いたりログに出したりしない
- ユーザーの確認なしにプロジェクトを削除しない（`npx -y hanamii projects delete <名前>` は名前の再入力を求める。`--yes` を勝手に付けない）
- 無料プランの 1 本目が既にある状態で 2 本目を作ろうとして失敗したら、hanamii の料金ページ（https://hanamii.jp/docs/guides/billing.md）を案内して止まる
