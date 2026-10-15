# hanamii 公開 API 早見表（このスキルで使う分だけ）

正本: https://hanamii.jp/docs/public-api.md（2026年10月時点）。Base URL `https://hanamii.jp`、全エンドポイントは `/api/v1`、認証は `Authorization: Bearer $HANAMII_TOKEN`。JSON を送るときは `Content-Type: application/json`。時刻は Unix ミリ秒。

| 目的 | 呼び方 |
|---|---|
| ワークスペース一覧 | `GET /workspaces` → `workspaces[].id` |
| プロジェクト一覧 | `GET /projects?limit=20` |
| アップロード URL 発行 | `POST /uploads` body `{"workspaceId":"<workspace-id>","fileName":"app.zip","contentType":"application/zip"}` → `upload.id`, `upload.uploadUrl`, `upload.putCurl` |
| ZIP を置く | `curl -X PUT '<uploadUrl>' -H 'Content-Type: application/zip' --data-binary '@app.zip'` |
| 検証して checkId | `POST /uploads/<upload.id>/check` body `{}`、`-N` を付ける → `result.checkId`, `result.canDeploy`, `result.errors` |
| 新規作成 | `POST /projects` body `{"workspaceId":"<workspace-id>","name":"my-app","source":{"type":"zip","checkId":"check_…"},"envs":[…任意]}` → `project.id` |
| 再デプロイ | `POST /projects/<id>/deploy` body `{"source":{"type":"zip","checkId":"check_…"}}` |
| GitHub から作成 | `POST /projects` body `{"workspaceId":"<workspace-id>","name":"my-app","source":{"type":"git","repoFullName":"owner/repo","ref":"main"}}`（GitHub 連携は先に画面で接続） |
| 状態と URL | `GET /projects/<id>` → `project.url`, `project.latestDeployment.readyState`（QUEUED / BUILDING / READY / ERROR）, `errorCode` |
| ログ | `GET /projects/<id>/logs?since=-15m&format=text` |
| 環境変数を保存 | `PATCH /projects/<id>/env` body `{"envs":[{"key":"K","value":"V","type":"secret"}]}`（保存のみ） |
| 保存を反映 | `POST /projects/<id>/restart` |
| 削除 | `DELETE /projects/<id>`（ユーザー確認なしに呼ばない） |

決まりごと:
- `checkId` は使い捨て。再デプロイのたびに upload → check をやり直す
- check と作成/再デプロイは応答まで時間がかかるので `curl -N`
- ZIP に `node_modules` `.next` `dist` `build` `.git` `.env*` `vendor` を入れない（入っていても除外されるが遅くなる）
- プロジェクト名は小文字・数字・ハイフン
- `POST /projects` の応答に URL は含まれない。`GET /projects/<id>` をポーリングして `READY` になったら `project.url` を読む
- レート制限は 1 ユーザーあたり概ね数十回/分。429 が返ったら待つ
