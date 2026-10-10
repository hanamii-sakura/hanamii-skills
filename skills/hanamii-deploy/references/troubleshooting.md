# つまずいたときの読み方

## 検証（check）で落ちる
| メッセージの例 | 原因 | 直し方 |
|---|---|---|
| 対応する言語を検出できませんでした | `package.json` / `requirements.txt` / `pyproject.toml` / `composer.json` が ZIP の直下にない | フォルダを一段深く圧縮している。プロジェクト直下で `zip -r` する |
| scripts.start がありません | Node.js の起動コマンド未定義 | `"start": "next start"` や `"start": "node server.js"` を足す |
| ZIP ファイルが空です | 除外しすぎ、または別フォルダで圧縮 | `--dir` を確認 |
| シンボリックリンク | ZIP に symlink が入っている | 実体に置き換えるか除外 |
| サイズ | 約 1GB 超 | ビルド成果物・動画・`node_modules` を除外 |

## ビルド（build_error）で落ちる
- ローカルで `rm -rf node_modules && npm ci && npm run build` を通す。通らなければ同じ原因
- ビルドに要るパッケージが `devDependencies` にあると本番インストールで入らないことがある。`dependencies` へ
- TypeScript の型エラーは `next build` を止める。`ignoreBuildErrors` で逃げるより直す
- Python は `requirements.txt` のバージョン固定が無いと依存解決で落ちることがある

## 起動（deploy_error / health_error）で落ちる
- `PORT` で listen していない（固定の 3000 や 8000 を使っている）
- `scripts.start` が `next dev` や `nodemon` になっている
- 起動時に外部 DB へ接続して失敗している。環境変数が未設定なら `PATCH /env` → `POST /restart`
- ヘルスチェックのパスが 200 以外を返す。不要なら `healthCheck.enabled=false`

## ログの見方
`GET /api/v1/projects/<id>/logs?since=-30m&format=text` で直近 30 分の実行ログが文字で取れる。ビルドログは API では取れないので、ビルド失敗はローカル再現で追う。

## 動いたのに真っ白／404
- Next.js で `basePath` や `assetPrefix` を設定している
- 静的ファイルを `public/` 以外に置いている
- 環境変数が `NEXT_PUBLIC_` 無しでクライアントから参照されている（ビルド時に埋め込まれないので再デプロイが要る）
