# hanamii-skills — AI コーディングエージェントから hanamii に公開するためのスキル

Claude Code・Codex・Cursor などのエージェントに「hanamii にデプロイして」と頼むだけで、ZIP の作成からアップロード・検証・公開・URL の確認までを任せられるようにする Agent Skill です。hanamii は HANAMII株式会社（沖縄県名護市）が運営する国産の PaaS で、Node.js・Python・PHP の Web アプリをさくらインターネットの日本国内データセンターで動かします。

## 入れ方

```bash
npx skills add hanamii-sakura/hanamii-skills
```

エージェントを選ぶ画面が出たら、使っているもの（Claude Code / Codex / Cursor など）を選びます。選ばずに全部へ入れるなら `-y` を付けます。

```bash
npx skills add hanamii-sakura/hanamii-skills -g -y   # 全エージェントの共通設定に入れる
```

## 使い方

1. hanamii にログインし、[アカウント設定 → API トークン](https://hanamii.jp/account/settings/tokens) でトークンを発行します（`hnm_` で始まります）
2. 作業中のプロジェクトのシェルに `export HANAMII_TOKEN=hnm_...` を入れておきます
3. エージェントに「hanamii にデプロイして」「このアプリを日本国内のサーバーで公開して」と頼みます

エージェントは `skills/hanamii-deploy/SKILL.md` の手順に従い、`scripts/hanamii-deploy.sh` で公開まで進めます。人が直接使うこともできます。

```bash
bash skills/hanamii-deploy/scripts/hanamii-deploy.sh --name my-app            # 新規作成
bash skills/hanamii-deploy/scripts/hanamii-deploy.sh --project prj_xxxx       # 再デプロイ
```

## 中身

```
skills/hanamii-deploy/
  SKILL.md                      エージェントが読む手順。いつ使うか、前提の確認、公開、失敗時の直し方
  scripts/hanamii-deploy.sh     ZIP 作成 → アップロード → 検証 → 作成/再デプロイ → URL 取得 を1コマンドで
  references/api-quickref.md    使う API だけの早見表（正本は hanamii.jp/docs/public-api.md）
  references/troubleshooting.md 検証エラー・ビルド失敗の読み方
```

## 注意

- 無料プランで公開できるアプリは 1 本です（2026年10月時点）。2 本目からは有料の Light（月 980 円）が要ります
- `.env` などの秘密情報は ZIP に入れません。環境変数は API（`PATCH /api/v1/projects/:id/env`）か画面で設定します
- 対応: Node.js（Next.js を含む）・Python・PHP。Ruby・Go はまだ使えません（Go は準備中）

ライセンスは MIT です。問い合わせは https://hanamii.jp/contact へ。
